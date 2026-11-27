// 队列 ↔ 播放器的粘合层：模型里的动作都走这里（与 Web 端 `playerCommands` 同职责）。
import Foundation
import PterosaurCore

@MainActor
final class PlaybackController: ObservableObject {
    let queue: Queue
    let player: Player
    let library: Library
    let account: Account

    init(queue: Queue, player: Player, library: Library, account: Account) {
        self.queue = queue
        self.player = player
        self.library = library
        self.account = account
        player.onFinish = { [weak self] in self?.advance() }
    }

    /// 「播放全部」：替换队列并从头播。
    func playAll(_ tracks: [Track], from i: Int = 0) {
        guard !tracks.isEmpty else { return }
        queue.set(tracks, startAt: i)
        if let cur = queue.current { play(cur) }
    }

    func play(_ track: Track) {
        player.play(track, cookie: account.playbackCredential)
        library.markPlayed(track)
    }

    func next() {
        if let t = queue.next() { play(t) }
    }

    /// 一首播完：单曲循环原地重播，其余前进。
    private func advance() {
        if queue.repeatMode == .one {
            player.seek(to: 0)
            player.resume()
            return
        }
        next()
    }

    func previous() {
        if let t = queue.previous() { play(t) }
    }

    func togglePlayPause() {
        if let cur = queue.current, player.currentId != keyOf(source: cur.source, id: cur.id), !player.isPlaying {
            play(cur)
        } else {
            player.toggle()
        }
    }
}
