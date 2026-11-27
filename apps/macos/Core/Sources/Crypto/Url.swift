// URL 拆分 / 接合与查询串处理（Swift 版，对应 shared/url.ts）。
// 不用 Foundation.URL：它对非绝对地址的处理、小写化与百分号编码口径都与 WHATWG 不同。
import Foundation

public struct UrlParts: Equatable, Sendable {
    public var protocolScheme: String
    public var userinfo: String
    public var hostname: String
    public var port: String
    public var rest: String

    public init(protocolScheme: String, userinfo: String, hostname: String, port: String, rest: String) {
        self.protocolScheme = protocolScheme
        self.userinfo = userinfo
        self.hostname = hostname
        self.port = port
        self.rest = rest
    }
}

private let SPLIT_RE = try! NSRegularExpression(
    pattern: #"^([a-z][a-z0-9+.-]*)://([^/?#]*)([^\s]*)$"#,
    options: [.caseInsensitive])

/// 按 `scheme://[userinfo@]hostname[:port]rest` 拆分；解析不了返回 `nil`。
public func splitUrl(_ url: String) -> UrlParts? {
    let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
    let ns = text as NSString
    guard let m = SPLIT_RE.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
        return nil
    }
    func group(_ i: Int) -> String {
        let r = m.range(at: i)
        return r.location == NSNotFound ? "" : ns.substring(with: r)
    }
    let authority = group(2)
    if authority.isEmpty { return nil }
    let at = authority.lastIndex(of: "@")
    let userinfo = at.map { String(authority[...$0]) } ?? ""
    let host = at.map { String(authority[$0...].dropFirst()) } ?? authority
    // 端口是最后一个冒号之后的段；IPv6 字面量里的冒号在 `]` 之前，不算
    let lastColon = host.lastIndex(of: ":")
    let lastBracket = host.lastIndex(of: "]")
    let hasPort: Bool = {
        guard let c = lastColon else { return false }
        guard let b = lastBracket else { return true }
        return c > b
    }()
    let hostname = (hasPort ? String(host[..<lastColon!]) : host).lowercased()
    let port = hasPort ? String(host[lastColon!...]) : ""
    let raw = group(3)
    let rest = (raw.isEmpty || raw.hasPrefix("/")) ? raw : "/\(raw)"
    return UrlParts(
        protocolScheme: group(1).lowercased() + ":",
        userinfo: userinfo,
        hostname: hostname,
        port: port,
        rest: rest.isEmpty ? "/" : rest)
}

/// 按原样拼回 URL（scheme / 主机 / 路径段可替换）。
public func joinUrl(
    _ parts: UrlParts,
    protocolScheme: String? = nil,
    hostname: String? = nil,
    rest: String? = nil
) -> String {
    "\(protocolScheme ?? parts.protocolScheme)//\(parts.userinfo)\(hostname ?? parts.hostname)\(parts.port)\(rest ?? parts.rest)"
}

/* ============================ 查询串 ============================ */

private func queryString(_ rest: String) -> String {
    guard let i = rest.firstIndex(of: "?") else { return "" }
    let tail = rest[rest.index(after: i)...]
    if let h = tail.firstIndex(of: "#") { return String(tail[..<h]) }
    return String(tail)
}

private func withoutQuery(_ rest: String) -> String {
    guard let i = rest.firstIndex(of: "?") else { return rest }
    let head = rest[..<i]
    let tail = rest[rest.index(after: i)...]
    if let h = tail.firstIndex(of: "#") { return String(head) + String(tail[h...]) }
    return String(head)
}

/// 把查询串整体换成 `query`（空串即去掉），路径与片段不动。
public func replaceQuery(_ rest: String, _ query: String) -> String {
    let base = withoutQuery(rest)
    if query.isEmpty { return base }
    guard let h = base.firstIndex(of: "#") else { return base + "?" + query }
    return String(base[..<h]) + "?" + query + String(base[h...])
}

/// 查询串里某个键的全部值（表单口径解码），按出现顺序。
public func queryValues(_ rest: String, _ key: String) -> [String] {
    var out = [String]()
    for pair in queryString(rest).split(separator: "&", omittingEmptySubsequences: true) {
        let s = String(pair)
        let i = s.firstIndex(of: "=")
        let k = formUrlDecode(i == nil ? s : String(s[..<i!]))
        if k != key { continue }
        out.append(formUrlDecode(i == nil ? "" : String(s[s.index(after: i!)...])))
    }
    return out
}

/// 表单值解码：`+` → 空格，百分号序列按 UTF-8 解码（非法序列原样保留）。
public func formUrlDecode(_ value: String) -> String {
    let spaced = value.replacingOccurrences(of: "+", with: " ")
    var out = [UInt8]()
    let bytes = Array(spaced.utf8)
    var i = 0
    while i < bytes.count {
        if bytes[i] == 0x25, i + 2 < bytes.count,
           let hi = hexVal(bytes[i + 1]), let lo = hexVal(bytes[i + 2]) {
            out.append(hi << 4 | lo)
            i += 3
        } else {
            out.append(bytes[i])
            i += 1
        }
    }
    return Encoding.decodeUTF8(out)
}

private func hexVal(_ b: UInt8) -> UInt8? {
    switch b {
    case 0x30...0x39: return b - 0x30
    case 0x41...0x46: return b - 0x41 + 10
    case 0x61...0x66: return b - 0x61 + 10
    default: return nil
    }
}