// 上游请求的底层设施（Swift 版，对应 packages/core/src/sources/http.ts 的通用部分与
// packages/core/src/sources/cache.ts）：同步 HTTP、瞬时故障重试、Set-Cookie 收敛、源内 TTL 缓存。
//
// 原生端没有浏览器那套 fetch / AbortSignal；Core 只用 Foundation 的 URLSession（同步发送，
// 调用方保证在网络线程），UI 仍不得自行发请求（见 AGENTS.md 铁律）。
import Foundation

/// 浏览器 UA（部分上游对非浏览器 UA 较敏感；与参考实现逐字一致）。
public let BROWSER_UA =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

/* ============================ 同步 HTTP ============================ */

/// 一次上游响应的最小面（正文文本 + 状态 + Set-Cookie）。
public struct FetchResult: Sendable {
    public let status: Int
    public let body: String
    public let setCookies: [String]
    public init(status: Int, body: String, setCookies: [String] = []) {
        self.status = status
        self.body = body
        self.setCookies = setCookies
    }
    public var ok: Bool { (200..<300).contains(status) }
}

/// 一次 GET / POST 的请求形态。
public struct FetchRequest: Sendable {
    public var method: String
    public var headers: [String: String]
    public var body: String?
    public var timeoutMs: Int
    public init(method: String = "GET", headers: [String: String] = [:], body: String? = nil, timeoutMs: Int = 15_000) {
        self.method = method
        self.headers = headers
        self.body = body
        self.timeoutMs = timeoutMs
    }
}

/// 网络发送器（测试可替换）。
public protocol Fetcher: Sendable {
    func fetch(_ url: String, _ req: FetchRequest) -> FetchResult
}

/// 能取**字节**的发送器：音质采样率探测要读 fMP4 文件头（二进制，按文本解码会损坏）。
/// 实现方提供它；未实现时探测退回按文本取——采样率只作展示，缺失不影响播放。
public protocol BinaryFetcher: Fetcher {
    func fetchBytes(_ url: String, _ req: FetchRequest) -> [UInt8]?
}

/// 默认实现：URLSession（同步阻塞到响应）；`timeoutInterval` 覆盖整个请求。
public struct URLSessionFetcher: BinaryFetcher {
    public init() {}

    private final class Box: @unchecked Sendable {
        var value: (Int, Data?, [String]) = (0, nil, [])
    }

    public func fetch(_ url: String, _ req: FetchRequest) -> FetchResult {
        let (status, data, cookies) = Self.perform(url, req)
        return FetchResult(status: status, body: data.flatMap { String(data: $0, encoding: .utf8) } ?? "", setCookies: cookies)
    }

    public func fetchBytes(_ url: String, _ req: FetchRequest) -> [UInt8]? {
        Self.perform(url, req).1.map { Array($0) }
    }

    private static func perform(_ url: String, _ req: FetchRequest) -> (Int, Data?, [String]) {
        guard let u = URL(string: url) else { return (0, nil, []) }
        var r = URLRequest(url: u)
        r.httpMethod = req.method
        r.timeoutInterval = Double(req.timeoutMs) / 1000
        for (k, v) in req.headers { r.setValue(v, forHTTPHeaderField: k) }
        if let b = req.body { r.httpBody = Data(b.utf8) }
        let box = Box()
        let sem = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: r) { data, resp, _ in
            let http = resp as? HTTPURLResponse
            box.value = (http?.statusCode ?? 0, data, setCookiesOf(http))
            sem.signal()
        }
        task.resume()
        sem.wait()
        return box.value
    }
}

/// 网络发送器（模块级，宿主启动后注入）。
nonisolated(unsafe) public var fetcher: Fetcher = URLSessionFetcher()

/// 从 `allHeaderFields` 取全部 `Set-Cookie` 原始串。
/// `HTTPURLResponse` 的 `allHeaderFields` 会把同名头合并成一个以 `, ` 连接的串；按 cookie 形态拆回。
func setCookiesOf(_ http: HTTPURLResponse?) -> [String] {
    guard let http else { return [] }
    var out: [String] = []
    for (k, v) in http.allHeaderFields {
        guard let name = k as? String, name.lowercased() == "set-cookie", let raw = v as? String else { continue }
        // 过期时间里的逗号（`Expires=Wed, 21 Oct …`）不是分隔符：只在不处于日期形态时拆
        var current = ""
        for part in raw.components(separatedBy: ", ") {
            if current.isEmpty { current = part; continue }
            let looksLikeDate = part.range(of: #"^\d{1,2} [A-Za-z]{3} \d{4}"#, options: .regularExpression) != nil
            if looksLikeDate { current += ", " + part } else { out.append(current); current = part }
        }
        if !current.isEmpty { out.append(current) }
    }
    return out.filter { $0.contains("=") }
}

/* ============================ 上游请求与重试 ============================ */

/// 上游失败：`code` 复用 HTTP 状态；网络错误 / 超时记为 0（瞬时）。
public struct UpstreamError: Error, Sendable {
    public let code: Int
    public let message: String
    public init(_ code: Int, _ message: String) {
        self.code = code
        self.message = message
    }
    /// 瞬时故障：网络错误、超时、5xx、429——值得重试。
    public var isTransient: Bool { code == 0 || code >= 500 || code == 429 }
}

/// 上游请求的可调项。
public struct UpstreamOptions: Sendable {
    public var userAgent: String
    public var referer: String?
    public var cookie: String?
    public var headers: [String: String]
    public var timeoutMs: Int
    /// 总尝试次数（含首次），默认 1 即不重试。
    public var attempts: Int
    public var retryDelayMs: Int
    public init(userAgent: String = BROWSER_UA, referer: String? = nil, cookie: String? = nil,
                headers: [String: String] = [:], timeoutMs: Int = 15_000, attempts: Int = 1,
                retryDelayMs: Int = 333) {
        self.userAgent = userAgent
        self.referer = referer
        self.cookie = cookie
        self.headers = headers
        self.timeoutMs = timeoutMs
        self.attempts = attempts
        self.retryDelayMs = retryDelayMs
    }
}

/// 统一 UA / Referer / Cookie / 超时，只对瞬时故障按类别重试，失败抛 `UpstreamError`。
@discardableResult
public func upstreamFetch(
    _ url: String,
    method: String = "GET",
    body: String? = nil,
    options: UpstreamOptions = UpstreamOptions()
) throws -> FetchResult {
    var last = UpstreamError(0, "上游请求失败")
    for attempt in 0..<max(1, options.attempts) {
        if attempt > 0 { Thread.sleep(forTimeInterval: Double(options.retryDelayMs) / 1000) }
        var headers = ["User-Agent": options.userAgent]
        if let r = options.referer { headers["Referer"] = r }
        if let c = options.cookie { headers["Cookie"] = c }
        for (k, v) in options.headers { headers[k] = v }
        let res = fetcher.fetch(url, FetchRequest(method: method, headers: headers, body: body, timeoutMs: options.timeoutMs))
        if res.ok { return res }
        last = res.status == 0 ? UpstreamError(0, "上游请求失败") : UpstreamError(res.status, "HTTP \(res.status)")
        if !last.isTransient { break }
    }
    throw last
}

/// 同上，直接解析 JSON 对象（解析失败视为网络层异常，瞬时）。
public func upstreamJSON(_ url: String, options: UpstreamOptions = UpstreamOptions()) throws -> [String: Any] {
    let res = try upstreamFetch(url, options: options)
    guard let o = (try? JSONSerialization.jsonObject(with: Data(res.body.utf8))) as? [String: Any] else {
        throw UpstreamError(0, "响应不是 JSON 对象")
    }
    return o
}

/* ============================ 通用工具 ============================ */

/// 凭证指纹（`sha1` 前 12 位）：缓存键里区分匿名 / 不同账号，避免串用解析结果。
public func credentialFingerprint(_ cred: String?) -> String {
    guard let cred, !cred.isEmpty else { return "anon" }
    return String(Encoding.toHex(Digest.sha1(Encoding.utf8(cred))).prefix(12))
}

/// 从 Set-Cookie 数组中挑出指定名称的 cookie，收敛为可直接透传的 `Cookie` 头值。
public func sessionCookieHeader(_ cookies: [String]?, _ names: [String]) -> String? {
    guard let cookies, !cookies.isEmpty else { return nil }
    var parts: [String] = []
    for c in cookies {
        let kv = c.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard let eq = kv.firstIndex(of: "="), eq != kv.startIndex else { continue }
        let name = String(kv[..<eq])
        if names.contains(name) { parts.append(kv) }
    }
    return parts.isEmpty ? nil : parts.joined(separator: "; ")
}

/// 组装 `AudioQuality`：只保留合法正值，缺失字段不臆造。
public func makeQuality(_ codec: String?, _ br: Any?, _ sr: Any?) -> AudioQuality {
    func positive(_ v: Any?) -> Int? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.intValue > 0 else { return nil }
        return n.intValue
    }
    return AudioQuality(codec: codec, br: positive(br), sr: positive(sr))
}

/* ============================ TTL + LRU 缓存 ============================ */

/// 带寿命与容量上限的进程内缓存（语义对齐参考实现的 `createTtlCache`：
/// 寿命自写入起算、命中不续命；超过 `max` 条淘汰最久未使用的一条；`ttlMs <= 0` 不过期）。
public final class TtlCache<Value>: @unchecked Sendable {
    private let max: Int
    private let ttlMs: Int64
    private var map: [String: (value: Value, expiresAt: Int64)] = [:]
    private var order: [String] = []
    private let lock = NSLock()

    public init(max: Int, ttlMs: Int64) {
        self.max = max
        self.ttlMs = ttlMs
    }

    public func get(_ key: String) -> Value? {
        lock.lock(); defer { lock.unlock() }
        guard let hit = map[key] else { return nil }
        if hit.expiresAt > 0 && hit.expiresAt <= epochMs() {
            map.removeValue(forKey: key)
            order.removeAll { $0 == key }
            return nil
        }
        order.removeAll { $0 == key }
        order.append(key)
        return hit.value
    }

    public func set(_ key: String, _ value: Value) {
        lock.lock(); defer { lock.unlock() }
        map[key] = (value, ttlMs > 0 ? epochMs() + ttlMs : 0)
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > max, let oldest = order.first {
            order.removeFirst()
            map.removeValue(forKey: oldest)
        }
    }

    public func remove(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        map.removeValue(forKey: key)
        order.removeAll { $0 == key }
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        map.removeAll()
        order.removeAll()
    }
}


/// 源内结构化数据缓存的寿命：对齐 server 路由层的 `CACHE_TTL.data`（ADR-042）。
public let DATA_CACHE_TTL_MS: Int64 = 120 * 60_000

/// 当前毫秒时间戳（缓存寿命计算用）。
func epochMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
