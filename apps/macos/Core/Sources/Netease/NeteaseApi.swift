// 网易云接口客户端（Swift 版，对应 packages/core/src/sources/neteaseApi.ts）。
//
// 与 TS 参考实现逐项一致：请求参数、加密方式（缺省 eapi / 显式 weapi）、域名、UA、
// Cookie 构造（库 `processCookieObject` 的口径——缺 `_ntes_nnid` / `NMTID` 时上游对部分接口
// 回空体、取流回 -460）。
//
// 网络通过可注入的 `HttpTransport`（生产用 URLSession，测试用假实现核对请求形态）。
// 与 TS 的唯一有意差异：业务码非 200 不抛异常，一律返回，由调用处按 `code` 判定。
import Foundation

public let DOMAIN = "https://music.163.com"
public let API_DOMAIN = "https://interface.music.163.com"

private let WEAPI_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0"
private let EAPI_UA = "NeteaseMusic 9.0.90/5038 (iPhone; iOS 16.2; zh_CN)"
private let ENCRYPT_RESPONSE = false

/// 接口返回：`body` 为解析后的上游 JSON，`cookie` 为原始 Set-Cookie 串。
/// `body` 是 JSONSerialization 产物（[String: Any] 等值类型）；标注 unchecked 以跨线程传递。
public struct NcmResult: @unchecked Sendable {
    public let body: Any
    public let cookie: [String]
}

/// 一次 HTTP 响应（只保留本层要用的部分）。
public struct HttpResponseText: Sendable {
    public let status: Int
    public let body: String
    public let setCookies: [String]
    public init(status: Int, body: String, setCookies: [String] = []) {
        self.status = status
        self.body = body
        self.setCookies = setCookies
    }
}

/// 可注入的 HTTP 发送器。
public protocol HttpTransport: Sendable {
    func send(url: String, headers: [String: String], body: String) -> HttpResponseText
}

/// 默认实现：URLSession（同步发送；调用方在后台线程使用）。
/// Swift 6 下闭包内不能写捕获的 var——用引用类型容器传递结果。
public struct URLSessionTransport: HttpTransport {
    public init() {}

    private final class ResultBox: @unchecked Sendable {
        var value = HttpResponseText(status: 0, body: "")
    }

    public func send(url: String, headers: [String: String], body: String) -> HttpResponseText {
        guard let u = URL(string: url) else { return HttpResponseText(status: 0, body: "") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = Data(body.utf8)
        let box = ResultBox()
        let sem = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: req) { data, resp, _ in
            let http = resp as? HTTPURLResponse
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            var cookies: [String] = []
            if let h = http, let all = h.allHeaderFields as? [String: String],
               let raw = all["Set-Cookie"] {
                cookies = raw.components(separatedBy: ", ").filter { $0.contains("=") }
            }
            box.value = HttpResponseText(status: http?.statusCode ?? 0, body: text, setCookies: cookies)
            sem.signal()
        }
        task.resume()
        sem.wait()
        return box.value
    }
}

/* ============================ 可替换的运行时依赖 ============================ */

/// 随机源（测试可替换）。
nonisolated(unsafe) public var nextRandom: @Sendable () -> Double = { Double.random(in: 0..<1) }
/// 匿名 token 提供者（宿主启动后注入）。
nonisolated(unsafe) public var anonymousTokenProvider: @Sendable () -> String = { "" }
/// 网络发送器（测试可替换）。
nonisolated(unsafe) public var httpTransport: HttpTransport = URLSessionTransport()

private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

/// 小写十六进制随机串（对应 TS 的 randomHex：每字节两位）。
func randomHex(_ bytes: Int) -> String {
    let hex = Array("0123456789abcdef")
    var s = ""
    for _ in 0..<(bytes * 2) {
        s.append(hex[min(15, max(0, Int(nextRandom() * 16)))])
    }
    return s
}

/// 模块级 `WNMCID`（6 个小写字母 + 时间戳）。
private let WNMCID: String = {
    let letters = Array("abcdefghijklmnopqrstuvwxyz")
    var s = ""
    for _ in 0..<6 { s.append(letters[min(25, max(0, Int(nextRandom() * 26)))]) }
    return "\(s).\(nowMs()).01.0"
}()

private func cookieToObject(_ cookie: String) -> [String: String] {
    var out: [String: String] = [:]
    for part in cookie.split(separator: ";") {
        let s = part.trimmingCharacters(in: .whitespaces)
        guard let eq = s.firstIndex(of: "="), eq != s.startIndex else { continue }
        let value = String(s[s.index(after: eq)...])
        if value.contains("=") { continue }
        out[String(s[..<eq]).trimmingCharacters(in: .whitespaces)] = value.trimmingCharacters(in: .whitespaces)
    }
    return out
}

/// 一次请求的 cookie 构造结果。
struct CookieContext {
    let header: [(String, String)]
    let cookieObject: [(String, String)]
    let cookieHeader: String
}

/// 构造请求 cookie 与请求头（对齐库的 `processCookieObject` + `createHeaderCookie`）。
func requestCookie(_ callerCookie: String?) -> CookieContext {
    var cookies = callerCookie.flatMap { $0.isEmpty ? nil : cookieToObject($0) } ?? [:]
    let hasUser = !(cookies["MUSIC_U"] ?? "").isEmpty
    var header: [(String, String)] = [
        ("osver", cookies["osver"] ?? "Microsoft-Windows-10-Professional-build-19045-64bit"),
        ("deviceId", cookies["deviceId"] ?? "undefined"),
        ("os", cookies["os"] ?? "pc"),
        ("appver", cookies["appver"] ?? "3.1.17.204416"),
        ("versioncode", cookies["versioncode"] ?? "140"),
        ("mobilename", cookies["mobilename"] ?? ""),
        ("buildver", cookies["buildver"] ?? String(nowMs()).prefix(10).description),
        ("resolution", cookies["resolution"] ?? "1920x1080"),
        ("__csrf", cookies["__csrf"] ?? ""),
        ("channel", cookies["channel"] ?? "netease"),
        ("requestId", "\(nowMs())_\(String(format: "%04d", Int(nextRandom() * 1000)))"),
    ]
    if hasUser { header.append(("MUSIC_U", cookies["MUSIC_U"]!)) }
    if let ma = cookies["MUSIC_A"], !ma.isEmpty { header.append(("MUSIC_A", ma)) }
    else if !hasUser {
        let anon = anonymousTokenProvider()
        if !anon.isEmpty { header.append(("MUSIC_A", anon)) }
    }

    let nuid = cookies["_ntes_nuid"] ?? randomHex(32)
    var co: [String: String] = cookies
    co["__remember_me"] = "true"
    co["ntes_kaola_ad"] = "1"
    co["_ntes_nuid"] = nuid
    co["_ntes_nnid"] = cookies["_ntes_nnid"] ?? "\(nuid),\(nowMs())"
    co["WNMCID"] = cookies["WNMCID"] ?? WNMCID
    co["WEVNSM"] = cookies["WEVNSM"] ?? "1.0.0"
    co["osver"] = header.first { $0.0 == "osver" }!.1
    co["deviceId"] = header.first { $0.0 == "deviceId" }!.1
    co["os"] = header.first { $0.0 == "os" }!.1
    co["channel"] = header.first { $0.0 == "channel" }!.1
    co["appver"] = header.first { $0.0 == "appver" }!.1
    co.removeValue(forKey: "MUSIC_U")
    co.removeValue(forKey: "MUSIC_A")
    co["NMTID"] = randomHex(16)
    if hasUser { co["MUSIC_U"] = cookies["MUSIC_U"]! }
    if let ma = cookies["MUSIC_A"], !ma.isEmpty { co["MUSIC_A"] = ma }
    else if !hasUser { co["MUSIC_A"] = anonymousTokenProvider() }
    if co["MUSIC_A"] == nil { co["MUSIC_A"] = anonymousTokenProvider() }

    // Cookie 头的键序：保持插入顺序（Swift 字典无序，故用数组）
    var ordered: [(String, String)] = []
    var seen = Set<String>()
    for (k, v) in cookies where k != "MUSIC_U" && k != "MUSIC_A" {
        if !seen.contains(k) { ordered.append((k, v)); seen.insert(k) }
    }
    for k in ["__remember_me", "ntes_kaola_ad", "_ntes_nuid", "_ntes_nnid", "WNMCID", "WEVNSM",
              "osver", "deviceId", "os", "channel", "appver", "NMTID"] {
        if seen.contains(k) { ordered.removeAll { $0.0 == k } }
        if let v = co[k] { ordered.append((k, v)); seen.insert(k) }
    }
    if let u = co["MUSIC_U"] { ordered.append(("MUSIC_U", u)) }
    if let a = co["MUSIC_A"] { ordered.append(("MUSIC_A", a)) }
    return CookieContext(header: header, cookieObject: ordered, cookieHeader: encodeCookieHeader(ordered))
}

/// 把键值对编码为 Cookie 头（键与值都按 `encodeURIComponent` 编码，同库）。
public func encodeCookieHeader(_ pairs: [(String, String)]) -> String {
    pairs.map { "\(uriComponent($0.0))=\(uriComponent($0.1))" }.joined(separator: "; ")
}

/// 与 JS `encodeURIComponent` 同口径（`addingPercentEncoding` 的 `urlQueryAllowed` 会保留 `& = ?`）。
private func uriComponent(_ s: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-_.!~*'()")
    return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
}

/* ============================ 请求 ============================ */

public enum Crypto: Sendable { case weapi, eapi }

private func jsonString(_ v: Any) -> String {
    guard JSONSerialization.isValidJSONObject(v),
          let d = try? JSONSerialization.data(withJSONObject: v),
          let s = String(data: d, encoding: .utf8) else { return "{}" }
    return s
}

/// 发起一次加密请求并解析响应。
func request(_ path: String, data: [String: Any], crypto: Crypto, cookie: String?) -> NcmResult {
    let ctx = requestCookie(cookie)
    var payload = data
    payload["e_r"] = ENCRYPT_RESPONSE

    let url: String
    let form: String
    let userAgent: String
    let stripped = path.hasPrefix("/api/") ? String(path.dropFirst(5)) : path
    switch crypto {
    case .weapi:
        payload["csrf_token"] = ctx.header.first { $0.0 == "__csrf" }?.1 ?? ""
        url = "\(DOMAIN)/weapi/\(stripped)"
        let enc = weapiEncrypt(payload: jsonString(payload), nextRandom)
        form = encodeForm([("params", enc.params), ("encSecKey", enc.encSecKey)])
        userAgent = WEAPI_UA
    case .eapi:
        var headerObj: [String: String] = [:]
        for (k, v) in ctx.header { headerObj[k] = v }
        payload["header"] = headerObj
        url = "\(API_DOMAIN)/eapi/\(stripped)"
        form = encodeForm([("params", eapiSign(path: path, payload: jsonString(payload)))])
        userAgent = EAPI_UA
    }

    let res = httpTransport.send(
        url: url,
        headers: [
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": userAgent,
            "Referer": DOMAIN,
            "Cookie": ctx.cookieHeader,
        ],
        body: form)

    var body: Any = [String: Any]()
    if let parsed = try? JSONSerialization.jsonObject(with: Data(res.body.utf8)) {
        body = parsed
    } else if crypto == .eapi, let decrypted = eapiDecrypt(res.body.trimmingCharacters(in: .whitespaces)),
              let parsed = try? JSONSerialization.jsonObject(with: Data(decrypted.utf8)) {
        body = parsed
    }
    return NcmResult(body: body, cookie: res.setCookies)
}

/* ============================ 接口 ============================ */

/// 搜索（`/api/cloudsearch/pc`，缺省 eapi）。`type`：1 单曲、10 专辑、100 歌手、1000 歌单。
public func cloudsearch(keywords: String, type: Int = 1, limit: Int = 30, offset: Int = 0, cookie: String? = nil) -> NcmResult {
    request("/api/cloudsearch/pc",
            data: ["s": keywords, "type": type, "limit": limit, "offset": offset, "total": true],
            crypto: .eapi, cookie: cookie)
}

/// 推荐歌单（weapi）。
public func personalized(limit: Int = 30, cookie: String? = nil) -> NcmResult {
    request("/api/personalized/playlist",
            data: ["limit": limit, "total": true, "n": 1000], crypto: .weapi, cookie: cookie)
}

/// 全部榜单（eapi）。
public func toplist(cookie: String? = nil) -> NcmResult {
    request("/api/toplist", data: [:], crypto: .eapi, cookie: cookie)
}

/// 歌单详情（eapi）。
public func playlistDetail(id: String, s: Int = 8, cookie: String? = nil) -> NcmResult {
    request("/api/v6/playlist/detail", data: ["id": id, "n": 100000, "s": s], crypto: .eapi, cookie: cookie)
}

/// 分类歌单（weapi）。
public func topPlaylist(cat: String = "全部", limit: Int = 50, offset: Int = 0, cookie: String? = nil) -> NcmResult {
    request("/api/playlist/list",
            data: ["cat": cat, "order": "hot", "limit": limit, "offset": offset, "total": true],
            crypto: .weapi, cookie: cookie)
}

/// 推荐新歌（weapi）。
public func personalizedNewsong(limit: Int = 10, cookie: String? = nil) -> NcmResult {
    request("/api/personalized/newsong",
            data: ["type": "recommend", "limit": limit, "areaId": 0], crypto: .weapi, cookie: cookie)
}

/// 歌单分类目录（eapi）。
public func playlistCatlist(cookie: String? = nil) -> NcmResult {
    request("/api/playlist/catalogue", data: [:], crypto: .eapi, cookie: cookie)
}

/// 最新专辑（weapi）。
public func albumNewest(cookie: String? = nil) -> NcmResult {
    request("/api/discovery/newAlbum", data: [:], crypto: .weapi, cookie: cookie)
}

/// 歌手专辑分页（weapi）。
public func artistAlbum(id: String, limit: Int = 30, offset: Int = 0, cookie: String? = nil) -> NcmResult {
    request("/api/artist/albums/\(id)", data: ["limit": limit, "offset": offset, "total": true],
            crypto: .weapi, cookie: cookie)
}

/// 歌手详情（含热门 50 首，weapi）。
public func artists(id: String, cookie: String? = nil) -> NcmResult {
    request("/api/v1/artist/\(id)", data: [:], crypto: .weapi, cookie: cookie)
}

/// 专辑详情（weapi）。
public func album(id: String, cookie: String? = nil) -> NcmResult {
    request("/api/v1/album/\(id)", data: [:], crypto: .weapi, cookie: cookie)
}

/// 播放地址 v1（eapi）。
public func songUrlV1(id: String, level: String, cookie: String? = nil) -> NcmResult {
    var data: [String: Any] = ["ids": "[\(id)]", "level": level, "encodeType": "flac"]
    if level == "sky" { data["immerseType"] = "c51" }
    return request("/api/song/enhance/player/url/v1", data: data, crypto: .eapi, cookie: cookie)
}

/// 曲目详情（weapi）。
public func songDetail(ids: [String], cookie: String? = nil) -> NcmResult {
    let c = "[" + ids.map { "{\"id\":\($0)}" }.joined(separator: ",") + "]"
    return request("/api/v3/song/detail", data: ["c": c], crypto: .weapi, cookie: cookie)
}

/// 歌词（eapi）。
public func lyricNew(id: String, cookie: String? = nil) -> NcmResult {
    request("/api/song/lyric/v1",
            data: ["id": id, "cp": false, "tv": 0, "lv": 0, "rv": 0, "kv": 0, "yv": 0, "ytv": 0, "yrv": 0],
            crypto: .eapi, cookie: cookie)
}

/// 登录账号信息（weapi）；与 TS 一致把 `body` 包成 `{ data: body }`。
public func loginStatus(cookie: String? = nil) -> NcmResult {
    let r = request("/api/w/nuser/account/get", data: [:], crypto: .weapi, cookie: cookie)
    return NcmResult(body: ["data": r.body], cookie: r.cookie)
}

/// 用户歌单（weapi）。
public func userPlaylist(uid: String, cookie: String? = nil) -> NcmResult {
    request("/api/user/playlist",
            data: ["uid": uid, "limit": 30, "offset": 0, "includeVideo": true], crypto: .weapi, cookie: cookie)
}

/// 匿名注册（weapi）：取 `MUSIC_A`。
public func registerAnonymous() -> String {
    let chars = Array("0123456789ABCDEF")
    var deviceId = ""
    for _ in 0..<52 { deviceId.append(chars[min(15, max(0, Int(nextRandom() * 16)))]) }
    let username = Encoding.base64(Encoding.utf8("\(deviceId) \(anonymousHash(deviceId))"))
    let r = request("/api/register/anonimous", data: ["username": username], crypto: .weapi, cookie: nil)
    for c in r.cookie {
        if let range = c.range(of: #"(?:^|;\s*)MUSIC_A=([^;]+)"#, options: .regularExpression) {
            let m = String(c[range])
            if let eq = m.firstIndex(of: "=") { return String(m[m.index(after: eq)...]) }
        }
    }
    return ""
}

private let ANON_XOR_KEY = Array("3go8&$8*3*3h0k(2)2")

private func anonymousHash(_ deviceId: String) -> String {
    let chars = Array(deviceId)
    var xored = ""
    for (i, ch) in chars.enumerated() {
        let key = ANON_XOR_KEY[i % ANON_XOR_KEY.count]
        if let scalar = UnicodeScalar(ch.unicodeScalars.first!.value ^ key.unicodeScalars.first!.value) {
            xored.append(Character(scalar))
        }
    }
    return Encoding.base64(Digest.md5(Encoding.utf8(xored)))
}