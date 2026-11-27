// 扫码登录与「自提供 Cookie」（Swift 版，对应 packages/core/src/sources/netease.ts 的
// qrKey / qrLoginUrl / qrCheck / parseUserCookie / loginStatus / userPlaylists）。
//
// 走网页端**现行**协议（2026-10 起）：明文 `/api/login/qrcode/*` + `type=1`，二维码内容为
// `https://music.163.com/st/platform/scanlogin?...`；旧链接（`login?codekey=`）已被 App 认不出，
// 轮询永远停在 801（见 docs/researches/netease-web-login-protocol.md）。这几条端点不用 eapi 加密。
import Foundation

/// 会话必需的 cookie 名单：下发、回传与登出清理**共用同一份**（漏清任一项会让「访客有会话」
/// 的判断成立，VIP 曲目被打回试听，见 ADR-062 / app.ts `credentialOf`）。
public let SESSION_COOKIE_NAMES = ["MUSIC_U", "__csrf", "MUSIC_A", "NMTID"]

/// 网易云网页端 UA：登录请求与取设备身份（headless）必须**完全一致**（ADR-052）。
public let NETEASE_WEB_UA =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36 Edg/156.0.0.0"

/// 网易云设备身份（`ydDeviceToken` + WM cookie）。怎么取是宿主的事（ADR-053 纯算法 / 隐藏 WebView 兜底）。
public struct NeteaseDeviceIdentity: Sendable {
    public let token: String
    public let cookieHeader: String
    public let sDeviceId: String?
    public init(token: String = "", cookieHeader: String = "", sDeviceId: String? = nil) {
        self.token = token
        self.cookieHeader = cookieHeader
        self.sDeviceId = sDeviceId
    }
    /// 空身份（降级）：不带 token 时 801 / 802 阶段上游不校验，只是手机确认后会命中 8821。
    public static let empty = NeteaseDeviceIdentity()
}

/// 设备身份提供者：宿主注入。内核只在扫码登录时消费。
public protocol NeteaseDevicePort: Sendable {
    /// 读缓存（不触发刷新）；未就绪返回 nil。
    func cached() -> NeteaseDeviceIdentity?
    /// 主动取一份身份；超时 / 失败降级为空身份，**绝不抛错**。
    func ensure(timeoutMs: Int) -> NeteaseDeviceIdentity
    /// 作废缓存（轮询命中 8821 时），下次重新取。
    func invalidate()
    /// 后台刷新。
    func refresh()
}

/// 默认：无设备身份（不预热、不刷新）。原生端接上 ADR-053 的纯算法后替换。
public struct NullNeteaseDevice: NeteaseDevicePort {
    public init() {}
    public func cached() -> NeteaseDeviceIdentity? { nil }
    public func ensure(timeoutMs: Int) -> NeteaseDeviceIdentity { .empty }
    public func invalidate() {}
    public func refresh() {}
}

/// 设备身份提供者（宿主启动后注入）。
nonisolated(unsafe) public var neteaseDevice: NeteaseDevicePort = NullNeteaseDevice()

/// 把登录接口下发的 Set-Cookie 收敛为可直接透传的 `Cookie` 头值（只取会话名单）。
public func cookieHeaderFromSetCookies(_ cookies: [String]?) -> String? {
    sessionCookieHeader(cookies, SESSION_COOKIE_NAMES)
}

/// 扫码轮询结果。`code`：800 过期 / 801 等待扫码 / 802 待确认 / 803 成功（带原始 Set-Cookie）。
public struct QrCheckResult: Sendable {
    public let code: Int
    public let cookies: [String]?
    public let message: String?
    public init(code: Int, cookies: [String]? = nil, message: String? = nil) {
        self.code = code
        self.cookies = cookies
        self.message = message
    }
}

/* ============================ 明文 POST ============================ */

private let NETEASE_ORIGIN = "https://music.163.com"

private func postNeteaseApi(
    _ path: String,
    body: [(String, String)],
    extraHeaders: [String: String] = [:],
    cred: String? = nil
) -> (data: [String: Any], cookies: [String]) {
    var headers: [String: String] = [
        "User-Agent": NETEASE_WEB_UA,
        "Referer": "\(NETEASE_ORIGIN)/",
        "Content-Type": "application/x-www-form-urlencoded",
    ]
    for (k, v) in extraHeaders { headers[k] = v }
    if let cred, !cred.isEmpty { headers["Cookie"] = cred }
    let res = fetcher.fetch(NETEASE_ORIGIN + path,
                            FetchRequest(method: "POST", headers: headers, body: encodeForm(body), timeoutMs: 15_000))
    let data = (try? JSONSerialization.jsonObject(with: Data(res.body.utf8))) as? [String: Any] ?? [:]
    return (data, res.setCookies)
}

/* ============================ chainId ============================ */

/// 每个二维码 key 对应的 `chainId`（`v1_<sDeviceId>_web_login_<ts>`）：官方把它既写进二维码链接、
/// 又作为轮询请求头 `x-login-chain-id` 回传。条目有界、2 分钟后清理，避免长驻进程积累。
private let qrChainIds = TtlCache<String>(max: 100, ttlMs: 2 * 60_000)

private func chainIdOf(_ key: String) -> String {
    if let hit = qrChainIds.get(key) { return hit }
    let sDeviceId = neteaseDevice.cached()?.sDeviceId ?? "unknown-\(Int(nextRandom() * 1_000_000))"
    let chainId = "v1_\(sDeviceId)_web_login_\(epochMs())"
    qrChainIds.set(key, chainId)
    return chainId
}

/// 设备 cookie（`WM_TID` 等）与用户会话 cookie（可空）合并为一个 Cookie 头值；键位几乎不相交。
private func withDeviceCookies(_ cred: String?) -> String? {
    guard let device = neteaseDevice.cached() else { return cred }
    if device.cookieHeader.isEmpty { return cred }
    guard let cred, !cred.isEmpty else { return device.cookieHeader }
    return "\(device.cookieHeader); \(cred)"
}

/* ============================ 扫码 ============================ */

/// 生成二维码 key（`unikey`）。取 key 前先等设备身份（首次最多 6s）——带上 WM cookie，
/// 且 chainId 能用真实 sDeviceId，否则手机确认后会命中 8821 设备风控。
public func qrKey(cookie: String? = nil) -> String {
    _ = neteaseDevice.ensure(timeoutMs: 6_000)
    let (data, _) = postNeteaseApi("/api/login/qrcode/unikey", body: [("type", "1")], cred: withDeviceCookies(cookie))
    let key = data["unikey"] as? String ?? ""
    if !key.isEmpty { _ = chainIdOf(key) }
    return key
}

/// 二维码**内容 URL**：`…/st/platform/scanlogin?codekey=…&chainId=…&hdw_device=web&hdw_appid=web&hitExp=1`。
public func qrLoginUrl(key: String) -> String {
    let query = encodeForm([
        ("codekey", key),
        ("chainId", chainIdOf(key)),
        ("hdw_device", "web"),
        ("hdw_appid", "web"),
        ("hitExp", "1"),
    ])
    return "\(NETEASE_ORIGIN)/st/platform/scanlogin?\(query)"
}

/// 检查扫码状态。8821 = 设备风控：作废并后台重取设备身份，用户重开弹窗再扫即用新身份。
public func qrCheck(key: String, cookie: String? = nil) -> QrCheckResult {
    let device = neteaseDevice.cached()
    let (data, cookies) = postNeteaseApi(
        "/api/login/qrcode/client/login",
        body: [
            ("key", key),
            ("type", "1"),
            ("noCheckToken", "true"),
            ("ydDeviceToken", device?.token ?? ""),
        ],
        extraHeaders: ["X-loginMethod": "QrCode", "x-login-chain-id": chainIdOf(key)],
        cred: withDeviceCookies(cookie))
    let code = (data["code"] as? NSNumber).map { $0.intValue } ?? 800
    if code == 8821 {
        neteaseDevice.invalidate()
        neteaseDevice.refresh()
    }
    if code == 803 || code == 800 { qrChainIds.remove(key) }
    return QrCheckResult(code: code, cookies: cookies, message: data["message"] as? String)
}


/* ============================ 自提供 Cookie ============================ */

/// 解析用户自带的 cookie 串：`k=v; k=v`、`MUSIC_U=xxx`，或**只粘 MUSIC_U 的值本身**。
/// 只保留会话必需项，其余（统计类）丢弃——它们对鉴权无意义，只会把 Cookie 头撑大。
public func parseUserCookie(_ raw: String) -> String {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return "" }
    let bare = !text.contains("=") && text.range(of: #"[;\n\r]"#, options: .regularExpression) == nil
    if bare { return "MUSIC_U=\(text)" }
    var picked: [String] = []
    for part in text.components(separatedBy: CharacterSet(charactersIn: ";\n\r")) {
        let item = part.trimmingCharacters(in: .whitespaces)
        guard let eq = item.firstIndex(of: "="), eq != item.startIndex else { continue }
        let name = String(item[..<eq]).trimmingCharacters(in: .whitespaces)
        let value = String(item[item.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        guard SESSION_COOKIE_NAMES.contains(name), !value.isEmpty else { continue }
        if picked.contains(where: { $0.hasPrefix("\(name)=") }) { continue }
        picked.append("\(name)=\(value)")
    }
    return picked.joined(separator: "; ")
}

/* ============================ 登录态 ============================ */

/// 登录状态（与 shared `LoginStatus` 同形；`loginable` 由路由按能力决定，端上恒为 true）。
public struct LoginStatus: Sendable, Equatable {
    public var logged: Bool
    public var nickname: String?
    public var avatarUrl: String?
    public var userId: String?
    public var vip: Bool
    public init(logged: Bool = false, nickname: String? = nil, avatarUrl: String? = nil,
                userId: String? = nil, vip: Bool = false) {
        self.logged = logged
        self.nickname = nickname
        self.avatarUrl = avatarUrl
        self.userId = userId
        self.vip = vip
    }
}

private func obj(_ v: Any?) -> [String: Any]? { v as? [String: Any] }

/// 查询登录状态；网络失败 / 未登录一律当作未登录。
public func loginStatus(cookie: String? = nil) -> LoginStatus {
    guard let cookie, !cookie.isEmpty else { return LoginStatus() }
    let body = obj(loginStatusRaw(cookie: cookie).body)
    guard let profile = obj(obj(body?["data"])?["profile"]) else { return LoginStatus() }
    let avatar = profile["avatarUrl"] as? String
    let userId = profile["userId"].flatMap { v -> String? in
        if let n = v as? NSNumber { return n.stringValue }
        return v as? String
    }
    let vipType = (profile["vipType"] as? NSNumber)?.intValue ?? 0
    return LoginStatus(
        logged: true,
        nickname: profile["nickname"] as? String,
        avatarUrl: avatar.flatMap { $0.isEmpty ? nil : coverUrl($0) },
        userId: userId,
        vip: vipType != 0)
}

/// 获取用户歌单。
public func userPlaylists(uid: String, cookie: String? = nil) -> [Playlist] {
    let body = obj(userPlaylist(uid: uid, cookie: cookie).body)
    let list = body?["playlist"] as? [Any] ?? []
    return list.compactMap(obj).map(normalizePlaylist)
}
