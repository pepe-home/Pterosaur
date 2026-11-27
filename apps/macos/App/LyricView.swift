// 歌词（全屏播放的歌词面板）：当前行高亮并自动滚动；带翻译时双行显示。
import PterosaurCore
import SwiftUI

struct LyricView: View {
    let track: Track
    @ObservedObject var state: AppState
    @State private var lyric = Lyric()
    @State private var currentIndex = -1

    private func isCurrent(_ i: Int) -> Bool { i == currentIndex }

    var body: some View {
        Group {
            if lyric.lines.isEmpty {
                EmptyState(text: "暂无歌词", symbol: "quote.bubble")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(lyric.lines.enumerated()), id: \.offset) { i, line in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(line.text.isEmpty ? " " : line.text)
                                        .font(.title3.weight(isCurrent(i) ? .bold : .semibold))
                                        .foregroundStyle(isCurrent(i) ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                                    if let t = line.translation {
                                        Text(t).font(.callout).foregroundStyle(.tertiary)
                                    }
                                }
                                .id(i)
                                .onTapGesture { state.player.seek(to: line.time) }
                                .animation(.smooth(duration: 0.2), value: currentIndex)
                            }
                        }
                        .padding(20)
                    }
                    .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                        let pos = state.player.position
                        if let i = lyric.lines.lastIndex(where: { $0.time <= pos }), i != currentIndex {
                            currentIndex = i
                            withAnimation(.smooth(duration: 0.3)) { proxy.scrollTo(i, anchor: .center) }
                        }
                    }
                }
            }
        }
        .frame(width: 420, height: 520)
        .task(id: track.id) {
            lyric = await Loaders.lyric(track, cookie: state.account.playbackCredential)
        }
    }
}
