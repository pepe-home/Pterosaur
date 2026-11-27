// 悬浮玻璃播放条（Liquid Glass，ADR-070）：封面 / 曲名 / 控制 / 进度 / 收藏 / 队列 / 歌词。
//
// 飘在窗口底部、与内容留出间距——它不是一条「栏」，而是一块悬浮在内容之上的玻璃。
// 控制键集中在一枚玻璃胶囊里（`GlassEffectContainer` 让相邻玻璃自然融合），左侧信息与右侧工具各成一簇。
import Combine
import PterosaurCore
import SwiftUI

struct PlayerBar: View {
    @ObservedObject var state: AppState
    @StateObject private var player: Player
    @StateObject private var queue: Queue
    @StateObject private var library: Library
    @State private var position: Double = 0
    @State private var duration: Double = 0
    @State private var showingQueue = false
    @State private var showingLyrics = false
    @Namespace private var glass

    init(state: AppState) {
        self.state = state
        _player = StateObject(wrappedValue: state.player)
        _queue = StateObject(wrappedValue: state.queue)
        _library = StateObject(wrappedValue: state.library)
    }

    var body: some View {
        HStack(spacing: 14) {
            nowPlaying
            Spacer(minLength: 0)
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    GlassIconButton(symbol: queue.repeatMode.symbol, size: 30, help: "循环") {
                        queue.repeatMode = nextRepeat(queue.repeatMode)
                    }
                    .foregroundStyle(queue.repeatMode == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    GlassIconButton(symbol: "backward.fill", size: 34, help: "上一首", action: state.playback.previous)
                    GlassIconButton(symbol: player.isPlaying ? "pause.fill" : "play.fill", size: 46, prominent: true,
                                    help: player.isPlaying ? "暂停" : "播放", action: state.playback.togglePlayPause)
                    GlassIconButton(symbol: "forward.fill", size: 34, help: "下一首", action: state.playback.next)
                    GlassIconButton(symbol: "shuffle", size: 30, help: "随机") { queue.toggleShuffle() }
                        .foregroundStyle(queue.shuffle ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                }
            }
            Spacer(minLength: 0)
            tools
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .onReceive(timer) { _ in
            guard player.isPlaying else { return }
            position = player.position
            duration = player.duration
        }
        .onChange(of: player.currentId) { _, _ in
            position = 0
            duration = 0
        }
    }

    // MARK: - 左：当前曲

    @ViewBuilder private var nowPlaying: some View {
        if let cur = queue.current {
            HStack(spacing: 10) {
                RemoteImage(url: cur.cover, corner: 8)
                    .frame(width: 44, height: 44)
                    .onTapGesture { showingLyrics.toggle() }
                    .help("歌词")
                VStack(alignment: .leading, spacing: 1) {
                    Text(cur.title).font(.callout.weight(.medium)).lineLimit(1)
                    Text(cur.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Button { library.toggleFavorite(cur) } label: {
                    Image(systemName: library.isFavorite(cur) ? "heart.fill" : "heart")
                        .foregroundStyle(library.isFavorite(cur) ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .help("我喜欢")
            }
            .frame(maxWidth: 260, alignment: .leading)
        } else {
            Label(player.lastError ?? "未在播放", systemImage: player.lastError == nil ? "music.note" : "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(player.lastError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                .lineLimit(1)
                .frame(maxWidth: 260, alignment: .leading)
        }
    }

    // MARK: - 右：进度与工具

    private var tools: some View {
        HStack(spacing: 10) {
            Text(position.formattedTime).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            Slider(value: $position, in: 0...max(duration, 0.01)) { editing in
                if !editing { player.seek(to: position) }
            }
            .controlSize(.small)
            .frame(width: 180)
            Text(duration.formattedTime).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            Button { showingQueue.toggle() } label: { Image(systemName: "list.bullet") }
                .buttonStyle(.borderless)
                .popover(isPresented: $showingQueue) {
                    QueuePanel(state: state).presentationBackground(.ultraThinMaterial)
                }
            Button { showingLyrics.toggle() } label: { Image(systemName: "quote.bubble") }
                .buttonStyle(.borderless)
                .popover(isPresented: $showingLyrics) {
                    if let cur = queue.current {
                        LyricView(track: cur, state: state).presentationBackground(.ultraThinMaterial)
                    }
                }
        }
        .frame(maxWidth: 420)
    }

    private var timer: Publishers.Autoconnect<Timer.TimerPublisher> { Timer.publish(every: 0.5, on: .main, in: .common).autoconnect() }

    private func nextRepeat(_ m: RepeatMode) -> RepeatMode {
        switch m { case .off: return .all; case .all: return .one; case .one: return .off }
    }
}

extension Double {
    var formattedTime: String { Int(max(0, isFinite ? self : 0)).formattedDuration }
}

struct QueuePanel: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("播放队列").font(.headline)
                Spacer()
                Text("\(state.queue.tracks.count) 首").font(.caption).foregroundStyle(.secondary)
                Button { state.player.stop() } label: { Image(systemName: "stop.fill").font(.caption) }
                    .buttonStyle(.borderless)
                    .help("停止")
            }
            .padding(14)
            if state.queue.isEmpty {
                EmptyState(text: "队列为空", symbol: "list.bullet").frame(height: 140)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(state.queue.tracks.enumerated()), id: \.offset) { i, t in
                            SongRow(track: t, playing: i == state.queue.index, favorite: state.library.isFavorite(t),
                                    onToggleFavorite: { state.library.toggleFavorite(t) },
                                    onPlay: { state.queue.set(state.queue.tracks, startAt: i); state.playback.play(t) })
                            .padding(.horizontal, 14)
                        }
                    }
                }
                .frame(width: 400, height: 340)
            }
        }
    }
}
