// 账号（单活动账号，ADR-027 / ADR-062）：网易云与 B 站各一个会话，存 Keychain。
// 退出登录清掉该源的会话 cookie（名单以 Core 为准，漏清任一项会让「访客有会话」被误判）。
import Foundation
import PterosaurCore

@MainActor
final class Account: ObservableObject {
    /// 当前网易云会话（`k=v; k=v`）；未登录为 nil。
    @Published private(set) var neteaseCookie: String?
    /// 当前 B 站会话；未登录为 nil（B 站无登录入口，只消费自提供 Cookie）。
    @Published private(set) var bilibiliCookie: String?
    @Published private(set) var status = LoginStatus()

    private static let neteaseKey = "netease"
    private static let bilibiliKey = "bilibili"

    init() {
        neteaseCookie = KeychainStore.get(Self.neteaseKey)
        bilibiliCookie = KeychainStore.get(Self.bilibiliKey)
        refreshStatus()
    }

    /// 当前播放用的凭证：有网易云会话就带上（VIP 曲目必需）。
    var playbackCredential: String? { neteaseCookie }

    /// 扫码成功：`setCookies` 是上游原始 Set-Cookie 串。
    func signInNetease(setCookies: [String]) {
        guard let h = cookieHeaderFromSetCookies(setCookies) else { return }
        neteaseCookie = h
        KeychainStore.set(Self.neteaseKey, h)
        refreshStatus()
    }

    /// 自提供 Cookie（从浏览器 DevTools 复制）。
    @discardableResult
    func signInNetease(rawCookie: String) -> Bool {
        let parsed = parseUserCookie(rawCookie)
        guard !parsed.isEmpty else { return false }
        neteaseCookie = parsed
        KeychainStore.set(Self.neteaseKey, parsed)
        refreshStatus()
        return true
    }

    func signInBilibili(rawCookie: String) {
        let parsed = rawCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !parsed.isEmpty else { return }
        bilibiliCookie = parsed
        KeychainStore.set(Self.bilibiliKey, parsed)
    }

    func signOut() {
        neteaseCookie = nil
        bilibiliCookie = nil
        KeychainStore.delete(Self.neteaseKey)
        KeychainStore.delete(Self.bilibiliKey)
        status = LoginStatus()
    }

    /// 后台查一次登录态（昵称 / 头像 / VIP）。
    func refreshStatus() {
        guard let cookie = neteaseCookie else {
            status = LoginStatus()
            return
        }
        Task { [weak self] in
            let s = await Task.detached(priority: .utility) { loginStatus(cookie: cookie) }.value
            self?.status = s
        }
    }
}
