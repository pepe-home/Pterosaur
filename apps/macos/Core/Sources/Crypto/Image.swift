// 封面 URL 规范化（Swift 版，对应 shared/image.ts 与 bilibili.ts 的 canonicalBiliImage）。
import Foundation

public let NETEASE_IMAGE_HOST = "p3.music.126.net"
public let BILI_IMAGE_HOST = "i0.hdslb.com"

public let COVER_SMALL = 300
public let COVER_LARGE = 1200
public let COVER_RIP = 3000

private let neteaseHostRe = try! NSRegularExpression(pattern: #"^p\d+\.music\.126\.net$"#)
private let biliHostRe = try! NSRegularExpression(pattern: #"^i\d+\.hdslb\.com$"#)

/// 规范化网易云图片地址：https、固定镜像主机、查询串只留最后一个 `param`。
public func canonicalNeteaseImage(_ url: String) -> String {
    if url.isEmpty { return url }
    guard let u = splitUrl(url) else { return url }
    let r = NSRange(location: 0, length: u.hostname.utf16.count)
    guard neteaseHostRe.firstMatch(in: u.hostname, range: r) != nil else { return url }
    let last = queryValues(u.rest, "param").last
    let query = last.map { "param=\(Encoding.formUrlEncode($0))" } ?? ""
    return joinUrl(u, protocolScheme: "https:", hostname: NETEASE_IMAGE_HOST, rest: replaceQuery(u.rest, query))
}

/// 把网易云封面改写为指定边长（`param={px}x{px}`）；非网易云地址原样返回。
public func coverAt(_ url: String?, _ px: Int) -> String? {
    guard let url, !url.isEmpty else { return url }
    guard let u = splitUrl(url) else { return url }
    let r = NSRange(location: 0, length: u.hostname.utf16.count)
    guard neteaseHostRe.firstMatch(in: u.hostname, range: r) != nil else { return url }
    let size = "\(px)x\(px)"
    return joinUrl(u, protocolScheme: "https:", hostname: NETEASE_IMAGE_HOST,
                   rest: replaceQuery(u.rest, "param=\(Encoding.formUrlEncode(size))"))
}

/// B 站封面/头像：补 `https:`，i0–iN 镜像主机归一；解析不了返回空串。
public func canonicalBiliImage(_ url: String?) -> String {
    guard let url, !url.isEmpty else { return "" }
    let abs = url.hasPrefix("//") ? "https:" + url : url
    guard let u = splitUrl(abs) else { return "" }
    let r = NSRange(location: 0, length: u.hostname.utf16.count)
    let host = biliHostRe.firstMatch(in: u.hostname, range: r) != nil ? BILI_IMAGE_HOST : u.hostname
    return joinUrl(u, protocolScheme: "https:", hostname: host)
}