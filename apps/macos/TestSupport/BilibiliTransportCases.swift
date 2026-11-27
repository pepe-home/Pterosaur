// 带假网络的用例：用假 Fetcher 核对请求形态与降级路径（不打真实上游）。
import Foundation
import PterosaurCore

/// 按 URL 前缀匹配的假网络：记录收到的请求，回预置响应；命中 `fail` 时回 status 0（网络错误）。
/// `raw` 里的地址按下发时的**原字节**回放（文本 `body` 走 UTF-8，装不下任意字节）。
final class FakeNet: BinaryFetcher, @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [(String, (FetchRequest) -> FetchResult)] = []
    private var log: [(String, FetchRequest)] = []
    private var rawBodies: [String: [UInt8]] = [:]
    var failPrefixes: [String] = []

    func route(_ prefix: String, _ body: @autoclosure @escaping () -> String, status: Int = 200, cookies: [String] = []) {
        lock.lock(); defer { lock.unlock() }
        routes.append((prefix, { _ in FetchResult(status: status, body: body(), setCookies: cookies) }))
    }

    /// 二进制响应（文件头探测等）。
    func raw(_ url: String, _ bytes: [UInt8]) {
        lock.lock(); defer { lock.unlock() }
        rawBodies[url] = bytes
    }

    var requests: [(String, FetchRequest)] {
        lock.lock(); defer { lock.unlock() }
        return log
    }

    func count(_ prefix: String) -> Int { requests.filter { $0.0.hasPrefix(prefix) }.count }

    func lastRequest(_ prefix: String) -> (String, FetchRequest)? { requests.last { $0.0.hasPrefix(prefix) } }

    func fetch(_ url: String, _ req: FetchRequest) -> FetchResult {
        lock.lock()
        log.append((url, req))
        let hit = routes.first { url.hasPrefix($0.0) }?.1
        let failing = failPrefixes.contains { url.hasPrefix($0) }
        lock.unlock()
        if failing { return FetchResult(status: 0, body: "") }
        return hit?(req) ?? FetchResult(status: 404, body: "{}")
    }

    func fetchBytes(_ url: String, _ req: FetchRequest) -> [UInt8]? {
        lock.lock()
        log.append((url, req))
        let raw = rawBodies[url]
        let failing = failPrefixes.contains { url.hasPrefix($0) }
        lock.unlock()
        if failing { return nil }
        return raw
    }
}

private func json(_ o: Any) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: o), encoding: .utf8)!
}

public enum BilibiliTransportCases {
    public static func run() throws {
        let real = fetcher
        defer { fetcher = real }

        // 1. 登录轮询：0 → 803 且汇总 cookie（URL 里的 SESSDATA 保持原文）
        let pollNet = FakeNet()
        pollNet.route("https://passport.bilibili.com/x/passport-login/web/qrcode/poll", json([
            "code": 0,
            "data": ["code": 0, "message": "ok", "url": "https://b/poll?SESSDATA=s%2C1&DedeUserID=9"],
        ]), cookies: ["bili_jct=jc"])
        fetcher = pollNet
        let ok = bilibiliQrCheck("https://passport.bilibili.com/x/passport-login/web/qrcode/generate?qrcode_key=KEY")
        try expectEqual(ok.code, 803, "扫码成功归一为 803")
        try expectEqual(ok.cookies, ["bili_jct=jc", "SESSDATA=s%2C1", "DedeUserID=9"], "成功时汇总 cookie")
        try expect(ok.cookies?.contains { $0.contains("%2C") } == true, "SESSDATA 不得解码")
        try expectEqual(pollNet.requests.first?.0, "https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=KEY",
                        "从登录 URL 里取 qrcode_key 轮询")
        try expectEqual(pollNet.requests.first?.1.headers["Referer"], BILIBILI_REFERER, "轮询带上游来源页")

        // 2. 轮询状态映射 + 瞬时失败重试（首次 + 5 次重试）
        for (inner, want) in [(86090, 802), (86038, 800), (86101, 801)] {
            let net = FakeNet()
            net.route("https://passport.bilibili.com/x/passport-login/web/qrcode/poll", json(["code": 0, "data": ["code": inner]]))
            fetcher = net
            try expectEqual(bilibiliQrCheck("k").code, want, "轮询码 \(inner) → \(want)")
        }
        let flaky = FakeNet()
        flaky.failPrefixes = ["https://passport.bilibili.com/"]
        fetcher = flaky
        let failed = bilibiliQrCheck("k")
        try expectEqual(failed.code, 801, "网络失败时解析不出业务码，按 801（等待扫码）处理")
        try expectEqual(flaky.count("https://passport.bilibili.com/"), 1, "poll 不走重试层（单次请求）")

        // 3. 磁带搜索：逐条补查 view 拿分P 数；单条失败降级、不整批抛错
        let searchNet = FakeNet()
        searchNet.route("https://api.bilibili.com/x/frontend/finger/spi", json(["code": 0, "data": ["b_3": "BUVID"]]))
        searchNet.route("https://api.bilibili.com/x/web-interface/search/all/v2", json([
            "code": 0,
            "data": ["result": [
                ["result_type": "video", "data": [
                    ["bvid": "BV1a", "title": "<em>甲</em>", "author": "A", "duration": "3:20"],
                    ["bvid": "BV1b", "title": "乙", "author": "B", "duration": "1:00"],
                ]],
                ["result_type": "media_bangumi", "data": [["bvid": "SHOULD_NOT"]]],
            ]],
        ]))
        searchNet.route("https://api.bilibili.com/x/web-interface/view?bvid=BV1a", json([
            "code": 0, "data": ["bvid": "BV1a", "title": "甲", "pages": [["cid": 1], ["cid": 2]], "owner": ["name": "A"]],
        ]))
        searchNet.failPrefixes = ["https://api.bilibili.com/x/web-interface/view?bvid=BV1b"]
        fetcher = searchNet
        let cassettes = try searchCassettes("甲", limit: 10)
        try expectEqual(cassettes.map(\.id), ["BV1a", "BV1b"], "磁带顺序与搜索结果一致")
        try expectEqual(cassettes[0].trackCount, 2, "补查得到分P 数")
        try expectEqual(cassettes[1].trackCount, nil, "补查失败时分P 数留空")
        try expectEqual(cassettes[1].name, "乙", "补查失败仍可构造磁带")
        try expectEqual(searchNet.count("https://api.bilibili.com/x/web-interface/search/all/v2"), 1, "搜索只打一次上游")
        try expect(searchNet.requests.first { $0.0.contains("/search/all/v2") }?.0.contains("page=1") == true,
                   "搜索分页参数")
        let searchCookie = searchNet.requests.first { $0.0.contains("/search/all/v2") }?.1.headers["Cookie"] ?? ""
        try expect(searchCookie.contains("buvid3=BUVID"), "匿名请求补 buvid3")

        // 4. 音频：分P 展开的 id 直接用 cid；候选 = baseUrl + backupUrl，官方 CDN 在前
        let audioNet = FakeNet()
        audioNet.route("https://api.bilibili.com/x/player/playurl", json([
            "code": 0,
            "data": ["dash": ["audio": [["id": 30280, "bandwidth": 190_000,
                                         "baseUrl": "http://xy.mcdn.bilivideo.cn/a",
                                         "backupUrl": ["https://upos-sz.bilivideo.com/a"]]]]],
        ]))
        fetcher = audioNet
        let urls = bilibiliSongUrl("BV1a:22")
        try expectEqual(urls, ["https://upos-sz.bilivideo.com/a", "https://xy.mcdn.bilivideo.cn/a"], "音频候选排序并改 https")
        try expect(audioNet.count("https://api.bilibili.com/x/player/pagelist") == 0, "带 cid 时不再查 pagelist")
        let quality = bilibiliAudioQuality("BV1a:22")
        try expectEqual(quality?.br, 190_000, "音质码率如实回报")
        try expectEqual(bilibiliStreamHeaders()["Referer"], BILIBILI_REFERER, "取流必须带上游来源页")

        // 5. 上游业务码：搜索被风控时向上抛（由 UI 出错误态）
        let blocked = FakeNet()
        blocked.route("https://api.bilibili.com/x/frontend/finger/spi", json(["code": 0, "data": [:]]))
        blocked.route("https://api.bilibili.com/x/web-interface/search/all/v2", json(["code": -352, "message": "风控"]))
        fetcher = blocked
        do {
            _ = try searchBilibiliTracks("x")
            throw SelfTestFailure("业务码失败应抛错")
        } catch let e as UpstreamError {
            try expectEqual(e.code, -352, "业务码透出")
        }

        // 6. 采样率探测：fMP4 头里的 stsd 采样率
        let probeNet = FakeNet()
        probeNet.route("https://api.bilibili.com/x/player/playurl", json([
            "code": 0, "data": ["dash": ["audio": [["id": 30280, "bandwidth": 190_000, "codecs": "mp4a.40.2",
                                                    "mimeType": "audio/mp4", "baseUrl": "https://cdn.bilivideo.com/x.m4s"]]]],
        ]))
        probeNet.raw("https://cdn.bilivideo.com/x.m4s", TestAudio.head(sampleRate: 44_100))
        fetcher = probeNet
        // 上一条同曲目已探测过时缓存会直接命中：清掉，确保本轮真的走 CDN 探测
        sampleRateCache.clear()

        let withSr = bilibiliAudioQuality("BV1a:1")

        try expectEqual(withSr?.sr, 44_100, "从文件头解析采样率")
        try expectEqual(withSr?.codec, "AAC", "编解码取自 codecs")
    }
}

/// 构造最小 fMP4 init segment：ftyp + moov/trak/mdia/minf/stbl/stsd（首个 sample entry 为 mp4a）。
enum TestAudio {
    static func head(sampleRate: Int) -> [UInt8] {
        func box(_ type: String, _ payload: [UInt8]) -> [UInt8] {
            let size = UInt32(payload.count + 8)
            return [UInt8(size >> 24 & 0xff), UInt8(size >> 16 & 0xff), UInt8(size >> 8 & 0xff), UInt8(size & 0xff)] + Array(type.utf8) + payload
        }
        // AudioSampleEntry（ISO 14496-12）：box 头 8（size + `mp4a`）+ SampleEntry 8 + 保留 8 +
        // 声道 2 + 位深 2 + 压缩/包大小 4，之后是 16.16 定点的采样率（相对 entry 起点偏移 32）
        let sr = UInt32(sampleRate) << 16
        let entry: [UInt8] = [0, 0, 0, 52] + Array("mp4a".utf8)
            + [UInt8](repeating: 0, count: 16) + [0, 2, 0, 16, 0, 0, 0, 0]
            + [UInt8(sr >> 24 & 0xff), UInt8(sr >> 16 & 0xff), UInt8(sr >> 8 & 0xff), UInt8(sr & 0xff)]
            + [0, 0, 0, 0]
        let stsd = box("stsd", [0, 0, 0, 0, 0, 0, 0, 1] + entry)
        let stbl = box("stbl", stsd)
        let minf = box("minf", stbl)
        let mdia = box("mdia", minf)
        let trak = box("trak", mdia)
        let moov = box("moov", trak)
        return box("ftyp", Array("isom".utf8) + [0, 0, 0, 0]) + moov
    }
}
