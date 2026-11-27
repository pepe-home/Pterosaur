// 播放队列（单活动队列，仿 Web 端 `playerQueue`）：顺序播放、循环、随机。
// 逻辑与 Web 端 `playerCommands` 对齐：随机是对队列的一次性洗牌，之后按次序游走（ADR-036）。
import Foundation
import PterosaurCore
import SwiftUI

enum RepeatMode: String, CaseIterable, Sendable {
    case off, all, one

    var symbol: String {
        switch self {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

@MainActor
final class Queue: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var index = 0
    @Published var repeatMode: RepeatMode = .all
    @Published var shuffle = false

    /// 洗牌前的原始顺序（关掉随机时还原）。
    private var unshuffled: [Track] = []

    var current: Track? { tracks.indices.contains(index) ? tracks[index] : nil }
    var isEmpty: Bool { tracks.isEmpty }

    func set(_ list: [Track], startAt i: Int = 0) {
        unshuffled = list
        tracks = shuffle ? Self.shuffled(list, keepingFirst: i) : list
        index = shuffle ? 0 : max(0, min(i, list.count - 1))
    }

    /// 追加到队列末尾（双击「播放全部」时用 `set` 替换）。
    func append(_ list: [Track]) {
        guard !list.isEmpty else { return }
        tracks += list
        unshuffled += list
    }

    func next() -> Track? {
        guard !tracks.isEmpty else { return nil }
        if repeatMode == .one { return current }
        if index + 1 < tracks.count {
            index += 1
        } else if repeatMode == .all {
            index = 0
        } else {
            return nil  // 顺序播放到末尾即停（不清空队列，播放条仍显示末曲）
        }
        return current
    }

    func previous() -> Track? {
        guard !tracks.isEmpty else { return nil }
        if index > 0 {
            index -= 1
        } else if repeatMode != .off {
            index = tracks.count - 1
        }
        return current
    }

    /// 随机开关：开 → 保持当前曲在首位后洗牌；关 → 还原原序并定位到当前曲。
    func toggleShuffle() {
        shuffle.toggle()
        let cur = current
        if shuffle {
            tracks = Self.shuffled(unshuffled, keepingFirst: cur.flatMap { c in unshuffled.firstIndex(of: c) })
            index = 0
        } else {
            tracks = unshuffled
            index = cur.flatMap { c in unshuffled.firstIndex(of: c) } ?? 0
        }
    }

    /// 保持当前曲在队首的洗牌（洗牌后第一首就是正在播的那首）。
    private static func shuffled(_ list: [Track], keepingFirst i: Int?) -> [Track] {
        guard let i, list.indices.contains(i) else { return list.shuffled() }
        let head = list[i]
        let rest = list.enumerated().filter { $0.offset != i }.map(\.element).shuffled()
        return [head] + rest
    }
}
