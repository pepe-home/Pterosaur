// 底部播放条：封面 / 曲名 / 控制 / 进度 / 收藏 / 队列（实色底，层级同侧栏）。
import PterosaurCore
import SwiftUI

struct PlayerBar: View {
    @ObservedObject var state: AppState
    @ObservedObject private var player: Player
    @ObservedObject private var queue: Queue
    @ObservedObject private var library: Library
    @State private var position: Double = 0
    @State private var duration: Double = 0
    @State private var showingQueue = false
    @State private var showingLyrics = false

    init(state: AppState) {
        self.state = state
        self.player = state.player
        self.queue = state.queue
        self.library = state.library
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 10) {
                    if let cur = queue.current {
                        RemoteImage(url: cur.cover, corner: 6).frame(width: 44, height: 44)
                            .onTapGesture { showingLyrics = true }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(cur.title).lineLimit(1)
                            Text(cur.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    } else if player.currentId == nil {
                        Text(player.lastError ?? "未在播放").font(.caption).foregroundStyle(player.lastError == nil ? .secondary : .red)
                    }
                    if let cur = queue.current {
                        Button { library.toggleFavorite(cur) } label: {
                            Image(systemName: library.isFavorite(cur) ? "heart.fill" : "heart")
                                .foregroundStyle(library.isFavorite(cur) ? .red : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("我喜欢")
                    }
                }
                .frame(maxWidth: 240, alignment: .leading)

                Spacer(minLength: 8)
                HStack(spacing: 16) {
                    Button { queue.repeatMode = nextRepeat(queue.repeatMode) } label: {
                        Image(systemName: queue.repeatMode.symbol)
                            .foregroundStyle(queue.repeatMode == .off ? .secondary : .tint)
                    }
                    Button(action: state.playback.previous) { Image(systemName: "backward.fill") }
                    Button(action: state.playback.togglePlayPause) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title2)
                    }
                    Button(action: state.playback.next) { Image(systemName: "forward.fill") }
                    Button { queue.toggleShuffle() } label: {
                        Image(systemName: "shuffle").foregroundStyle(queue.shuffle ? .tint : .secondary)
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Text(position.formattedTime).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    Slider(value: $position, in: 0...max(duration, 0.01)) { editing in
                        if !editing { player.seek(to: position) }
                    }
                    .frame(minWidth: 120, maxWidth: 320)
                    Text(duration.formattedTime).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    Button { showingQueue.toggle() } label: {
                        Image(systemName: "list.bullet")
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingQueue) { QueuePanel(state: state) }
                    Button {
                        showingLyrics.toggle()
                    } label: {
                        Image(systemName: "quote.bubble")
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingLyrics) {
                        if let cur = queue.current { LyricView(track: cur, state: state) }
                    }
                }
                .frame(maxWidth: 420)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
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
            HStack {
                Text("播放队列").font(.headline)
                Spacer()
                Text("\(state.queue.tracks.count) 首").font(.caption).foregroundStyle(.secondary)
                Button {
                    state.player.stop()
                } label: { Image(systemName: "square.fill").font(.caption) }
                    .buttonStyle(.plain).help("停止")
            }
            .padding(12)
            Divider()
            if state.queue.isEmpty {
                EmptyState(text: "队列为空").frame(height: 120)
            } else {
                List(Array(state.queue.tracks.enumerated()), id: \.offset) { i, t in
                    SongRow(track: t, playing: i == state.queue.index, favorite: state.library.isFavorite(t),
                            onToggleFavorite: { state.library.toggleFavorite(t) },
                            onPlay: { state.queue.set(state.queue.tracks, startAt: i); state.playback.play(t) })
                }
                .frame(width: 380, height: 320)
            }
        }
    }
}
