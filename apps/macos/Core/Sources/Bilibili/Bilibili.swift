// B 站（磁带渠道）音源（Swift 版，对应 packages/core/src/sources/bilibili.ts）：
// 搜视频（= 搜磁带）、DASH 音频解析、分P / 磁带详情、字幕作歌词（ADR-035）、扫码登录。
//
// 磁带在数据模型上就是 `source: "bilibili"` 的 `Playlist`：分P 即曲目、`trackCount` 为分P 数、
// `creator` 为 UP 主（ADR-044）。
//
// 反爬要点（2026-10 实测）：搜索走 `search/all/v2`（未被风控；`wbi/search/type` 会回人机验证）；
// 取音频 `pagelist` → `playurl(fnval=16)` 的 `dash.audio`；音频直链取字节**必须带
// `Referer: https://www.bilibili.com`**；字幕列表要求登录（未登录恒空）。
import Foundation

/// 调接口 / 取字节必需的上游来源页（否则直链 403）。
public let BILIBILI_REFERER = "https://www.bilibili.com"
private let API = "https://api.bilibili.com"

/// 会话必需 cookie 名单：登录态透传与登出清理**共用同一份**（登出漏清任一项即会绕开缺省凭证）。
public let BILIBILI_SESSION_COOKIE_NAMES = [
    "SESSDATA", "bili_jct", "DedeUserID", "DedeUserID__ckMd5", "buvid3", "bili_ticket",
]

/// 瞬时故障重试：首次 + 5 次重试 = 最多 6 次；业务码与 4xx 立即抛出，由调用点降级。
private let MAX_RETRIES = 5
private let RETRY_DELAY_MS = 333

/// 带分类重试的 GET（`code != 0` 抛业务错误）。
func bGet<T>(_ url: String, cookie: String?, _ convert: (JSON) -> T?) throws -> T {
    let json = try upstreamJSON(url, options: UpstreamOptions(
        referer: BILIBILI_REFERER, cookie: cookie,
        attempts: MAX_RETRIES + 1, retryDelayMs: RETRY_DELAY_MS))
    let code = (json["code"] as? NSNumber)?.intValue ?? -1
    guard code == 0 else { throw UpstreamError(code, "bilibili code \(code)") }
    guard let value = convert(json) else { throw UpstreamError(0, "bilibili 响应缺少 data") }
    return value
}

/* ============================ buvid3（匿名反爬标识） ============================ */

private let buvidCache = TtlCache<String>(max: 1, ttlMs: 6 * 3600_000)

private func buvid3() -> String? {
    if let hit = buvidCache.get("buvid3") { return hit }
    if let v = try? bGet("\(API)/x/frontend/finger/spi", cookie: nil, { ($0["data"] as? JSON).flatMap { $0["b_3"] as? String } }) {
        buvidCache.set("buvid3", v)
        return v
    }
    return nil
}

/// 在访客凭证基础上补一个 buvid3。
private func cookieWithBuvid(_ cred: String?) -> String? {
    let b = buvid3()
    let parts = [cred, b.map { "buvid3=\($0)" }].compactMap { $0 }.filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: "; ")
}

/* ============================ 搜索 ============================ */

private let searchCache = TtlCache<[JSON]>(max: 200, ttlMs: 5 * 60_000)

/// 关键词搜视频，返回 `search/all/v2` 的 `video` 分组原始条目（`page` 从 1 起）。
func fetchVideoGroup(_ keywords: String, _ page: Int, _ cred: String?) throws -> [JSON] {
    let cookie = cookieWithBuvid(cred)
    let key = "\(credentialFingerprint(cookie))|\(keywords)|\(max(1, page))"
    if let hit = searchCache.get(key) { return hit }
    let videos = try bGet(
        "\(API)/x/web-interface/search/all/v2?keyword=\(percentEncode(keywords))&page=\(max(1, page))",
        cookie: cookie
    ) { json -> [JSON]? in
        let groups = (json["data"] as? JSON)?["result"] as? [Any] ?? []
        return (groups.compactMap { $0 as? JSON }.first { $0["result_type"] as? String == "video" }?["data"] as? [Any] ?? [])
            .compactMap { $0 as? JSON }
    }
    searchCache.set(key, videos)
    return videos
}

/// 关键词搜索视频（归一化为 `Track`）。
public func searchBilibiliTracks(_ keywords: String, limit: Int = 30, cookie: String? = nil, page: Int = 1) throws -> [Track] {
    try fetchVideoGroup(keywords, page, cookie).prefix(limit).map(normalizeBilibiliTrack)
}

/* ============================ 取音频（DASH 分轨） ============================ */

/// 各抽象档位对应的目标码率（bps），用于从 `dash.audio[]` 里挑最接近的一条。
let LEVEL_TARGET_BPS: [AudioLevel: Int] = [
    .standard: 64_000, .higher: 132_000, .exhigh: 192_000, .lossless: 1_000_000, .hires: 2_000_000,
]

/// 从多档音频里挑与目标码率最接近的一条（并列取更高码率）。
public func pickAudio(_ audios: [JSON], _ level: AudioLevel) -> JSON? {
    let target = LEVEL_TARGET_BPS[level] ?? 192_000
    var best: JSON?
    for a in audios {
        guard let b = best else { best = a; continue }
        let bw = (a["bandwidth"] as? NSNumber)?.intValue ?? 0
        let bwBest = (b["bandwidth"] as? NSNumber)?.intValue ?? 0
        let d = abs(bw - target), dBest = abs(bwBest - target)
        if d < dBest || (d == dBest && bw > bwBest) { best = a }
    }
    return best
}

/// 候选 CDN 排序：官方 upos（`*.bilivideo.com`）优先，`mcdn` P2P 边缘殿后，并去重。
/// `baseUrl` 实测恒为 mcdn（对数据中心 IP 极不稳），稳定源藏在 `backupUrl[]` 里。
public func rankAudioUrls(_ urls: [String]) -> [String] {
    func score(_ u: String) -> Int {
        guard let parts = splitUrl(u) else { return 2 }
        let h = parts.hostname.lowercased()
        if h.range(of: #"(^|\.)mcdn\.bilivideo\.cn$"#, options: .regularExpression) != nil { return 3 }
        if h.hasSuffix(".bilivideo.com") { return 0 }
        if h.hasSuffix(".bilivideo.cn") { return 1 }
        return 2
    }
    var seen = Set<String>()
    return urls.filter { seen.insert($0).inserted }.enumerated()
        .sorted { (score($0.element), $0.offset) < (score($1.element), $1.offset) }
        .map(\.element)
}

private func cidOf(_ bvid: String, _ cidRaw: String?, _ cookie: String?) throws -> Int? {
    if let cidRaw, let n = Int(cidRaw), n > 0 { return n }
    return try bGet("\(API)/x/player/pagelist?bvid=\(percentEncode(bvid))", cookie: cookie) { json in
        (json["data"] as? [Any])?.first.flatMap { ($0 as? JSON)?["cid"] as? NSNumber }.map(\.intValue)
    }
}

/// 解析音频候选与选中条目（`songUrl` 与 `audioQuality` 共用）。
func resolveBiliAudio(_ id: String, _ cred: String?, _ level: AudioLevel) throws -> (urls: [String], picked: JSON?) {
    // id 形如 `<bvid>`（整视频取首P）或 `<bvid>:<cid>`（分P 展开后的具体一页）
    let parts = id.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
    let bvid = parts[0]
    let cookie = cookieWithBuvid(cred)
    guard let cid = try cidOf(bvid, parts.count > 1 ? parts[1] : nil, cookie) else { return ([], nil) }
    let data = try bGet(
        "\(API)/x/player/playurl?bvid=\(percentEncode(bvid))&cid=\(cid)&fnval=16&fnver=0&fourk=1",
        cookie: cookie) { $0["data"] as? JSON } 
    let audios = ((data["dash"] as? JSON)?["audio"] as? [Any] ?? []).compactMap { $0 as? JSON }
    let picked = pickAudio(audios, level)
    let candidates: [String]
    if let picked {
        candidates = [picked["baseUrl"] as? String ?? ""] + (picked["backupUrl"] as? [Any] ?? []).compactMap { $0 as? String }
    } else {
        candidates = (data["durl"] as? [Any] ?? []).compactMap { ($0 as? JSON)?["url"] as? String }
    }
    let urls = rankAudioUrls(candidates.filter { !$0.isEmpty }.map { toHttps($0) })
    return (urls, picked)
}

/// 解析某视频的**音频**直链有序候选；空数组即不可播放。
public func bilibiliSongUrl(_ id: String, cookie: String? = nil, level: AudioLevel = .defaultLevel) -> [String] {
    (try? resolveBiliAudio(id, cookie, level).urls) ?? []
}

/// 由 `codecs` / `mimeType` 归一为编解码显示名。
func biliCodecName(_ a: JSON) -> String? {
    let c = (a["codecs"] as? String ?? "").lowercased()
    if c.hasPrefix("mp4a") { return "AAC" }
    if c.hasPrefix("ec-3") || c.hasPrefix("ac-3") { return "AC3" }
    if c.hasPrefix("flac") { return "FLAC" }
    if c.hasPrefix("opus") { return "OPUS" }
    let m = (a["mimeType"] as? String ?? "").lowercased()
    if m.contains("flac") { return "FLAC" }
    if m.contains("mp4") || m.contains("aac") { return "AAC" }
    if m.contains("mpeg") { return "MP3" }
    return nil
}

/// 采样率探测缓存（`曲目id|音频流id` → Hz），永不过期（同一文件不变）。
public let sampleRateCache = TtlCache<Int>(max: 500, ttlMs: 0)

/// 逐个候选取文件头解析采率；任何失败只让 `sr` 缺席。带超时，防单个 CDN 挂起。
func probeSampleRate(_ urls: [String], _ cookie: String?) -> Int? {
    for url in urls {
        var headers = ["User-Agent": BROWSER_UA, "Referer": BILIBILI_REFERER,
                       "Range": "bytes=0-\(PROBE_BYTES - 1)"]
        if let cookie, !cookie.isEmpty { headers["Cookie"] = cookie }
        // 探测的是**二进制**文件头：`FetchResult.body` 是 UTF-8 文本，装不下任意字节。能取字节的宿主
        // （URLSession 实现 / 测试假网络）给原字节；取不到就跳过该候选——只让 `sr` 缺席，绝不误报。
        guard let bytes = (fetcher as? BinaryFetcher)?.fetchBytes(url, FetchRequest(headers: headers, timeoutMs: 5_000)) else { continue }
        if let sr = parseSampleRate(bytes) { return sr }
    }
    return nil
}

/// 解析给定档位**实际**得到的音频流参数（取选中音频条的实测码率与编解码）。
public func bilibiliAudioQuality(_ id: String, cookie: String? = nil, level: AudioLevel = .defaultLevel) -> AudioQuality? {
    guard let resolved = try? resolveBiliAudio(id, cookie, level), let picked = resolved.picked, !resolved.urls.isEmpty else { return nil }
    let urls = resolved.urls
    let bw = (picked["bandwidth"] as? NSNumber).flatMap { $0.intValue > 0 ? $0.intValue : nil }
    let key = "\(id)|\((picked["id"] as? NSNumber)?.intValue ?? bw ?? 0)"
    var sr = sampleRateCache.get(key)
    if sr == nil {
        sr = probeSampleRate(urls, cookieWithBuvid(cookie))
        if let sr { sampleRateCache.set(key, sr) }
    }
    return AudioQuality(codec: biliCodecName(picked), br: bw, sr: sr)
}

/// 音频 CDN 要求 `Referer`，否则 403。
public func bilibiliStreamHeaders() -> [String: String] { ["Referer": BILIBILI_REFERER] }

/* ============================ 磁带（分P / 合集） ============================ */

private let viewCache = TtlCache<JSON>(max: 200, ttlMs: DATA_CACHE_TTL_MS)

/// 取一个视频的 `view` 数据（标题 / 封面 / UP 主 / `pages[]` / 简介 / 统计），带源内 memo。
/// 失败向调用方抛错，由各调用点决定降级。
func fetchView(_ bvid: String, _ cred: String?) throws -> JSON {
    let cookie = cookieWithBuvid(cred)
    let key = "\(credentialFingerprint(cookie))|\(bvid)"
    if let hit = viewCache.get(key) { return hit }
    let data = try bGet("\(API)/x/web-interface/view?bvid=\(percentEncode(bvid))", cookie: cookie) {
        $0["data"] as? JSON
    }
    viewCache.set(key, data)
    return data
}

/// `view` → 分P 曲目（纯函数）。`id` 为 `<bvid>:<cid>`，`songUrl` 据此直接定位到该分P。
/// 多P 时标题取分P 名（不带序号前缀；缺失回落视频标题），单P 取视频标题；封面统一为视频封面。
public func buildParts(_ d: JSON?) -> [Track] {
    guard let d, let bvid = d["bvid"] as? String, !bvid.isEmpty else { return [] }
    let pages = (d["pages"] as? [Any] ?? []).compactMap { $0 as? JSON }
    if pages.isEmpty { return [] }
    let cover = canonicalBiliImage(d["pic"] as? String)
    let artist = (d["owner"] as? JSON)?["name"] as? String ?? "未知 UP 主"
    let multi = pages.count > 1
    let videoTitle = d["title"] as? String ?? "未知视频"
    return pages.map { p in
        let cid = (p["cid"] as? NSNumber)?.intValue ?? (p["page"] as? NSNumber)?.intValue ?? 0
        let part = (p["part"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Track(
            source: "bilibili",
            id: "\(bvid):\(cid)",
            title: multi ? (part.isEmpty ? videoTitle : part) : videoTitle,
            artist: artist,
            album: "",
            cover: cover,
            duration: (p["duration"] as? NSNumber)?.intValue ?? 0,
            fee: "free")
    }
}

/// `view` → **磁带**（`Playlist`，纯函数）。`trackCount` = 分P 数（缺失**留空**而非 0，
/// 以免卡片误判为空集合而置灰播放），`creator` = UP 主。
public func buildCassette(_ d: JSON?) -> Playlist {
    let title = decodeTitle(d?["title"] as? String ?? "")
    let desc = (d?["desc"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let pages = d?["pages"] as? [Any]
    return Playlist(
        source: "bilibili",
        id: d?["bvid"] as? String ?? "",
        name: title.isEmpty ? "未知视频" : title,
        cover: canonicalBiliImage(d?["pic"] as? String),
        description: desc.isEmpty ? nil : desc,
        trackCount: (pages?.isEmpty ?? true) ? nil : pages?.count,
        playCount: ((d?["stat"] as? JSON)?["view"] as? NSNumber)?.intValue,
        creator: (d?["owner"] as? JSON)?["name"] as? String ?? "未知 UP 主")
}

/// 仅凭一条**搜索结果**构造磁带（分P 数未知 → `trackCount` 留空）。
func cassetteFromVideo(_ v: JSON) -> Playlist {
    let title = decodeTitle(v["title"] as? String ?? "")
    return Playlist(
        source: "bilibili",
        id: jsonString(v["bvid"]) ?? jsonLong(v["aid"]).map(String.init) ?? "",
        name: title.isEmpty ? "未知视频" : title,
        cover: canonicalBiliImage(v["pic"] as? String),
        creator: v["author"] as? String ?? "未知 UP 主")
}

/// 磁带搜索的分P 补查并发上限与单条超时。
let CASSETTE_ENRICH_CONCURRENCY = 4
let CASSETTE_ENRICH_TIMEOUT_MS = 5_000

/// 并发受限的映射：至多 `limit` 个任务同时在跑，结果顺序不变。
/// 用 Worker 引用类型分发任务：Swift 6 下 `DispatchQueue.async` 的闭包会逃逸，不能直接捕获
/// 非逃逸的 `fn`，也不能写闭包捕获的 `var`。
final class MapWorker<Input, Output>: @unchecked Sendable {
    let items: [Input]
    let fn: (Int, Input) -> Output
    let slots: LockedBox<[Output?]>
    let sem: DispatchSemaphore
    let group = DispatchGroup()

    init(items: [Input], limit: Int, fn: @escaping (Int, Input) -> Output) {
        self.items = items
        self.fn = fn
        let box = LockedBox<[Output?]>()
        box.set([Output?](repeating: nil, count: items.count))
        self.slots = box
        self.sem = DispatchSemaphore(value: min(max(limit, 1), max(items.count, 1)))
    }

    func run() -> [Output] {
        guard !items.isEmpty else { return [] }
        DispatchQueue.concurrentPerform(iterations: items.count) { i in
            sem.wait()
            let out = fn(i, items[i])
            slots.mutate { $0[i] = out }
            sem.signal()
        }
        return (slots.get() ?? []).compactMap { $0 }
    }
}

public func mapLimit<T, R>(_ items: [T], _ limit: Int, _ fn: @escaping (Int, T) -> R) -> [R] {
    MapWorker(items: items, limit: limit, fn: fn).run()
}

/// 与超时竞速：超时返回 nil（并不取消底层请求，其结果仍会补进 `viewCache`）。
func withTimeout<T>(_ ms: Int, _ body: @escaping @Sendable () -> T) -> T? {
    let sem = DispatchSemaphore(value: 0)
    let box = LockedBox<T>()
    DispatchQueue.global().async {
        box.set(body())
        sem.signal()
    }
    if sem.wait(timeout: .now() + .milliseconds(ms)) == .timedOut { return nil }
    return box.get()
}

final class LockedBox<T>: @unchecked Sendable {
    private var value: T?
    private let lock = NSLock()
    init() {}
    func set(_ v: T) { lock.lock(); value = v; lock.unlock() }
    func get() -> T? { lock.lock(); defer { lock.unlock() }; return value }
    func mutate(_ body: (inout T) -> Void) {
        lock.lock()
        if var v = value { body(&v); value = v }
        lock.unlock()
    }
}

/// 补查单条的分P 数：成功用 `view` 归一化，失败 / 超时降级为「仅凭搜索结果构造」。
func enrichCassette(_ v: JSON, _ cred: String?) -> Playlist {
    let bvid = String(v["bvid"] as? String ?? "")
    if bvid.isEmpty { return cassetteFromVideo(v) }
    // `fetchView` 抛错当作补查失败：`withTimeout` 只负责「超时」这一种降级
    if let data = withTimeout(CASSETTE_ENRICH_TIMEOUT_MS, { (try? fetchView(bvid, cred)) ?? [:] }), !data.isEmpty {
        return buildCassette(data)
    }
    return cassetteFromVideo(v)
}

/// 关键词搜索**磁带**：逐条补查 `view` 取分P 数，单条失败即降级、绝不整批抛错。
public func searchCassettes(_ keywords: String, limit: Int = 20, cookie: String? = nil, page: Int = 1) throws -> [Playlist] {
    let videos = Array(try fetchVideoGroup(keywords, page, cookie).prefix(limit))
    return mapLimit(videos, CASSETTE_ENRICH_CONCURRENCY) { _, v in enrichCassette(v, cookie) }
}

/// 解析一个视频的**分P**（失败返回空）。
public func bilibiliParts(_ id: String, cookie: String? = nil) -> [Track] {
    let bvid = String(id.split(separator: ":").first ?? "")
    guard let data = try? fetchView(bvid, cookie) else { return [] }
    return buildParts(data)
}

/// **磁带**详情：一次 `view` 即得磁带档案与其分P 曲目。失败向上抛（页面出错误态 + 重试）。
public func bilibiliPlaylistTracks(_ id: String, cookie: String? = nil) throws -> PlaylistWithTracks {
    let bvid = String(id.split(separator: ":").first ?? "")
    let data = try fetchView(bvid, cookie)
    return PlaylistWithTracks(playlist: buildCassette(data), tracks: buildParts(data))
}

/* ============================ 字幕（作为歌词） ============================ */

/// 中文语言族判定：`zh` / `zh-CN` / `zh-Hans` / `ai-zh`…（剥 `ai-` 前缀后主代码为 `zh`）。
public func isChineseLan(_ lan: String?) -> Bool {
    guard let lan, !lan.isEmpty else { return false }
    let parts = lan.split(separator: "-")
    return (parts[0] == "ai" ? (parts.count > 1 ? parts[1] : "") : parts[0]) == "zh"
}

private func isAiTrack(_ s: JSON) -> Bool {
    ((s["type"] as? NSNumber)?.intValue ?? 0) == 1
        || ((s["ai_type"] as? NSNumber)?.intValue ?? 0) == 1
        || (s["lan"] as? String ?? "").hasPrefix("ai-")
}

/// 字幕轨挑选结果：主轨为歌词正文，中文轨（若有）为翻译。
public struct SubtitleTrackPick: @unchecked Sendable {
    public let main: JSON
    public let zh: JSON?
}

/// 选轨：原文轨优先（首条非中文人工轨 → 锁定轨 → 列表首条）；主轨已是中文则单语；
/// 否则再挑一条中文轨作翻译（人工 CC 优先、AI 兜底）。无 `subtitle_url` 的轨不参与。
public func pickSubtitleTracks(_ subs: [JSON]) -> SubtitleTrackPick? {
    let usable = subs.filter { s in
        guard let u = s["subtitle_url"] as? String else { return false }
        return !u.isEmpty
    }
    if usable.isEmpty { return nil }
    let manualNonZh = usable.filter { !isAiTrack($0) && !isChineseLan($0["lan"] as? String) }
    let main = manualNonZh.first
        ?? usable.first { ($0["is_lock"] as? NSNumber)?.boolValue == true }
        ?? usable[0]
    if isChineseLan(main["lan"] as? String) { return SubtitleTrackPick(main: main, zh: nil) }
    let chinese = usable.filter { isChineseLan($0["lan"] as? String) }
    if chinese.isEmpty { return SubtitleTrackPick(main: main, zh: nil) }
    let zh = chinese.first { !isAiTrack($0) } ?? chinese[0]
    return SubtitleTrackPick(main: main, zh: zh)
}

private func asSeconds(_ v: Any?) -> Double? {
    if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
    if let s = v as? String, let d = Double(s) { return d }
    return nil
}

/// 由字幕轨构建 `Lyric`（纯函数）：主轨逐行映射；中文轨按**时间窗最大重叠**挂为 `translation`
/// （两轨分段常不一致，不能按时间相等配对）；无有效重叠的中文行丢弃。
public func buildLyricFromSubtitles(_ main: [JSON], _ zh: [JSON]? = nil) -> Lyric {
    let EPS = 0.05
    func normalize(_ arr: [JSON]) -> [(from: Double, to: Double?, text: String)] {
        var out: [(Double, Double?, String)] = []
        for l in arr {
            guard let from = asSeconds(l["from"]) else { continue }
            let text = (l["content"] as? String ?? "")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            out.append((from, asSeconds(l["to"]), text))
        }
        return out.sorted { $0.0 < $1.0 }
    }
    let m = normalize(main)
    if m.isEmpty { return Lyric() }
    var lines = m.map { LyricLine(time: $0.from, text: $0.text) }
    let ends: [Double] = m.enumerated().map { i, l in l.to ?? (i + 1 < m.count ? m[i + 1].from : l.from + 3) }
    if let zh, !zh.isEmpty {
        let z = normalize(zh)
        var parts = [[String]](repeating: [], count: m.count)
        for line in z {
            let zs = line.from
            let ze = line.to ?? zs + 3
            var best = -1
            var bestOverlap = 0.0
            for i in m.indices {
                if m[i].from >= ze { break }
                let overlap = min(ends[i], ze) - max(m[i].from, zs)
                if overlap > bestOverlap + 1e-9 { bestOverlap = overlap; best = i }
            }
            if best >= 0 && bestOverlap > EPS { parts[best].append(line.text) }
        }
        for i in lines.indices where !parts[i].isEmpty {
            var seen = Set<String>()
            let merged = parts[i].filter { seen.insert($0).inserted }.joined(separator: " ")
            lines[i].translation = merged
        }
    }
    return Lyric(lines: lines, timed: true)
}

/* ---------- wbi 签名 ---------- */

/// 混淆盐表（B 站前端公开常量）。
let MIXIN_KEY_ENC_TAB: [Int] = [
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
    33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40, 61,
    26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36,
    20, 34, 44, 52,
]

/// `wbi_img` 图 URL（`…/bfs/wbi/<key>.png`）→ `<key>`。
public func extractWbiKey(_ url: String?) -> String {
    ((url ?? "").split(separator: "/").last.map(String.init) ?? "").components(separatedBy: ".").first ?? ""
}

/// img_key + sub_key（各 32 位）→ 32 位混淆密钥（纯函数）。
public func mixinKey(_ imgKey: String, _ subKey: String) -> String {
    let raw = Array(imgKey + subKey)
    return String(MIXIN_KEY_ENC_TAB.map { $0 < raw.count ? raw[$0] : nil }.compactMap { $0 }.prefix(32))
}

/// 与 JS `encodeURIComponent` 同口径、再转义 `!'()*`（对齐 B 站前端 / Python `quote` 的行为）。
func wbiEncode(_ s: String) -> String {
    encodeURIComponent(s)
        .replacingOccurrences(of: "!", with: "%21")
        .replacingOccurrences(of: "'", with: "%27")
        .replacingOccurrences(of: "(", with: "%28")
        .replacingOccurrences(of: ")", with: "%29")
        .replacingOccurrences(of: "*", with: "%2A")
}

/// 对查询参数做 wbi 签名，返回完整 query 串（含 `wts` 与 `w_rid`）：滤空值 → 按键排序 → 追加 `wts`
/// → `md5(query + mixinKey)`。`wts` 可注入以便单测。
public func signWbi(_ params: [(String, String)], key: String, wts: Int = Int(Date().timeIntervalSince1970)) -> String {
    let pairs = params.filter { !$0.1.isEmpty }.sorted { $0.0 < $1.0 }
    let query = (pairs.map { "\(wbiEncode($0.0))=\(wbiEncode($0.1))" } + ["wts=\(wts)"]).joined(separator: "&")
    let wr = Encoding.toHex(Digest.md5(Encoding.utf8(query + key)))
    return "\(query)&w_rid=\(wr)"
}

private let wbiKeyCache = TtlCache<String>(max: 1, ttlMs: 24 * 3600_000)

private func wbiMixinKey(_ cookie: String?) throws -> String {
    if let hit = wbiKeyCache.get("key") { return hit }
    let key = try bGet("\(API)/x/web-interface/nav", cookie: cookie) { json in
        let img = (json["data"] as? JSON)?["wbi_img"] as? JSON
        return mixinKey(extractWbiKey(img?["img_url"] as? String), extractWbiKey(img?["sub_url"] as? String))
    }
    if key.count == 32 { wbiKeyCache.set("key", key) }
    return key
}

/// 播放器信息里的字幕轨列表；wbi 版失败时回落非签名 `player/v2` 一次。
func playerInfo(_ bvid: String, _ cid: Int, _ cookie: String?) throws -> [JSON] {
    if let key = try? wbiMixinKey(cookie), !key.isEmpty,
       let subs = try? bGet("\(API)/x/player/wbi/v2?\(signWbi([("bvid", bvid), ("cid", String(cid))], key: key))",
                            cookie: cookie, { subtitlesOf($0) }) {
        return subs
    }
    return try bGet("\(API)/x/player/v2?bvid=\(percentEncode(bvid))&cid=\(cid)", cookie: cookie) { subtitlesOf($0) }
}

private func subtitlesOf(_ json: JSON) -> [JSON]? {
    let subs = (((json["data"] as? JSON)?["subtitle"] as? JSON)?["subtitles"] as? [Any] ?? []).compactMap { $0 as? JSON }
    return subs
}

/// 拉取字幕正文（`//` 补 https；AI 字幕地址自带签名，仍带 cookie 保险）。失败返回空。
private func fetchSubtitleLines(_ url: String, _ cookie: String?) -> [JSON] {
    let abs = url.hasPrefix("//") ? "https:" + url : toHttps(url)
    var headers = ["User-Agent": BROWSER_UA, "Referer": BILIBILI_REFERER]
    if let cookie, !cookie.isEmpty { headers["Cookie"] = cookie }
    let res = fetcher.fetch(abs, FetchRequest(headers: headers))
    guard res.ok,
          let json = (try? JSONSerialization.jsonObject(with: Data(res.body.utf8))) as? JSON,
          let body = json["body"] as? [Any] else { return [] }
    return body.compactMap { $0 as? JSON }
}

/// 取视频**字幕**作为歌词。任何失败一律降级为空歌词——歌词是锦上添花，不打挂播放链路。
public func bilibiliLyric(_ id: String, cookie: String? = nil) -> Lyric {
    do {
        let parts = id.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let bvid = parts[0]
        let cred = cookieWithBuvid(cookie)
        guard let cid = try cidOf(bvid, parts.count > 1 ? parts[1] : nil, cred) else { return Lyric() }
        guard let pick = pickSubtitleTracks(try playerInfo(bvid, cid, cred)) else { return Lyric() }
        let mainURL = pick.main["subtitle_url"] as? String ?? ""
        let main = fetchSubtitleLines(mainURL, cred)
        if main.isEmpty { return Lyric() }
        let zh = pick.zh.flatMap { $0["subtitle_url"] as? String }.map { fetchSubtitleLines($0, cred) }
        return buildLyricFromSubtitles(main, (zh?.isEmpty ?? true) ? nil : zh)
    } catch {
        return Lyric()
    }
}

/* ============================ 登录 ============================ */

/// 生成登录二维码：**返回二维码内容本身（登录 URL）作为 key**（poll 只认其中的 `qrcode_key`）。
public func bilibiliQrKey() throws -> String {
    let data = try bGet("https://passport.bilibili.com/x/passport-login/web/qrcode/generate", cookie: nil) {
        $0["data"] as? JSON
    }
    return data["url"] as? String ?? ""
}

/// 从 Set-Cookie 里挑出会话 cookie。
public func bilibiliCookieHeaderFromSetCookies(_ cookies: [String]?) -> String? {
    sessionCookieHeader(cookies, BILIBILI_SESSION_COOKIE_NAMES)
}

/// 从 URL 查询串里取**原始（未解码）**参数值——`SESSDATA` 含 `%2C`，解码会破坏其值。
public func rawQueryValue(_ url: String, _ name: String) -> String? {
    guard let q = url.firstIndex(of: "?") else { return nil }
    let rest = url[url.index(after: q)...]
    let query = rest.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    for pair in query.split(separator: "&") {
        guard let eq = pair.firstIndex(of: "="), String(pair[..<eq]) == name else { continue }
        return String(pair[pair.index(after: eq)...])
    }
    return nil
}

/// 汇总登录后的会话 cookie：优先取 poll 的 `Set-Cookie`，缺失的从回跳 URL 查询串补齐（保持原文）。
public func collectLoginCookies(_ setCookies: [String], _ url: String?) -> [String] {
    var out = setCookies
    let have = Set(out.map { String($0.prefix { $0 != "=" }) }.filter { !$0.isEmpty })
    if let url {
        for name in BILIBILI_SESSION_COOKIE_NAMES where !have.contains(name) {
            if let raw = rawQueryValue(url, name) { out.append("\(name)=\(raw)") }
        }
    }
    return out
}

/// 轮询扫码状态，归一为与网易云一致的 code 语义：
/// `0`→803 成功、`86090`→802 已扫码待确认、`86038`→800 已失效、其它（`86101` 未扫码）→801。
public func bilibiliQrCheck(_ key: String) -> QrCheckResult {
    let qrcodeKey = splitUrl(key).map { queryValues($0.rest, "qrcode_key").first ?? key } ?? key
    let res = fetcher.fetch(
        "https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=\(percentEncode(qrcodeKey))",
        FetchRequest(headers: ["User-Agent": BROWSER_UA, "Referer": BILIBILI_REFERER]))
    let json = (try? JSONSerialization.jsonObject(with: Data(res.body.utf8))) as? JSON ?? [:]
    let data = json["data"] as? JSON
    let inner = (data?["code"] as? NSNumber)?.intValue ?? -1
    let message = data?["message"] as? String
    if inner == 0 {
        let cookies = collectLoginCookies(res.setCookies, data?["url"] as? String)
        return QrCheckResult(code: 803, cookies: cookies, message: message ?? "登录成功")
    }
    let code = inner == 86090 ? 802 : inner == 86038 ? 800 : 801
    return QrCheckResult(code: code, message: message)
}

/// 查询登录态。
public func bilibiliLoginStatus(_ cred: String?) -> LoginStatus {
    guard let cred, !cred.isEmpty else { return LoginStatus() }
    guard let d = try? bGet("\(API)/x/web-interface/nav", cookie: cred, { $0["data"] as? JSON }) else { return LoginStatus() }
    guard (d["isLogin"] as? NSNumber)?.boolValue == true else { return LoginStatus() }
    let face = d["face"] as? String
    return LoginStatus(
        logged: true,
        nickname: d["uname"] as? String,
        avatarUrl: (face?.isEmpty ?? true) ? nil : canonicalBiliImage(face),
        userId: (d["mid"] as? NSNumber)?.stringValue,
        vip: ((d["vipStatus"] as? NSNumber)?.intValue ?? 0) != 0)
}

/// 磁带无专辑页：返回空壳以满足适配器的必选面。
public func bilibiliAlbumDetail(_ id: String) -> AlbumWithTracks {
    AlbumWithTracks(album: Album(source: "bilibili", id: id, name: "", cover: "", artist: ""), tracks: [])
}

/// 与 JS `encodeURIComponent` 同口径（不保留 `!'()*~`，其余 unreserved 保留）。
public func encodeURIComponent(_ s: String) -> String {
    var out = ""
    for ch in s.unicodeScalars {
        let letterOrDigit = CharacterSet.alphanumerics.contains(ch) && ch.isASCII
        switch ch {
        case "-", "_", ".", "~":
            out.unicodeScalars.append(ch)
        default:
            if letterOrDigit { out.unicodeScalars.append(ch) }
            else {
                for b in String(ch).utf8 { out += String(format: "%%%02X", b) }
            }
        }
    }
    return out
}

/// 关键词的百分号编码。
func percentEncode(_ s: String) -> String { encodeURIComponent(s) }
