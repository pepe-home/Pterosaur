// 播放引擎：AVPlayer 单实例 + `streamHeaders`（B 站 CDN 要 Referer）。
// UI 不碰 URLSession；播放地址由 Core 解析（`playableUrl` / `bilibiliSongUrl`）。
import AVFoundation
import Foundation
import PterosaurCore

@MainActor
final class Player: ObservableObject {
    private let player = AVPlayer()
    /// 播完通知的观察者。块里 `[weak self]`、`Player` 又由 `AppState` 持有并与进程同寿命，
    /// 故不在 `deinit` 里摘除——Swift 6 不允许从 nonisolated deinit 访问它。
    private var endObserver: NSObjectProtocol?

    @Published private(set) var isPlaying = false
    @Published private(set) var currentId: String?
    /// 解析失败 / 不可播放的提示（播放条上以红色文字展示）。
    @Published private(set) var lastError: String?

    /// 播完一首时回调（队列据此前进）。
    var onFinish: (() -> Void)?

    init() {
        player.actionAtItemEnd = .pause
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onFinish?() }
        }
    }

    /// 解析并播放一首（`cookie` 为当前账号会话，VIP 曲目必需）。
    func play(_ track: Track, level: AudioLevel = .defaultLevel, cookie: String? = nil) {
        guard currentId != keyOf(source: track.source, id: track.id) else {
            resume()
            return
        }
        lastError = nil
        Task { [weak self] in
            let resolved = await Player.resolve(track, level: level, cookie: cookie)
            self?.load(track, urls: resolved.urls, headers: resolved.headers)
        }
    }

    /// 后台解析播放地址（nonisolated：不触碰主线程状态）。
    private nonisolated static func resolve(_ track: Track, level: AudioLevel, cookie: String?) async -> (urls: [String], headers: [String: String]) {
        await Task.detached(priority: .userInitiated) {
            switch track.source {
            case "bilibili":
                return (bilibiliSongUrl(track.id, cookie: cookie, level: level), bilibiliStreamHeaders())
            default:
                return (songUrl(track.id, level: level, cookie: cookie), [:])
            }
        }.value
    }

    private func load(_ track: Track, urls: [String], headers: [String: String]) {
        guard let raw = urls.first, let url = URL(string: raw) else {
            currentId = keyOf(source: track.source, id: track.id)
            lastError = "无法播放（版权受限或需要登录）"
            return
        }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        currentId = keyOf(source: track.source, id: track.id)
        player.play()
        isPlaying = true
    }

    func resume() { player.play(); isPlaying = true }

    func pause() { player.pause(); isPlaying = false }

    func toggle() { isPlaying ? pause() : resume() }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    var position: Double { player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0 }
    var duration: Double {
        let d = player.currentItem?.duration.seconds ?? 0
        return d.isFinite ? d : 0
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        currentId = nil
    }
}
