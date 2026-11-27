// 歌词（全屏播放的歌词面板）：当前行高亮并自动滚动；带翻译时双行显示。
import PterosaurCore
import SwiftUI

struct LyricView: View {
    let track: Track
    @ObservedObject var state: AppState
    @State private var lyric = Lyric()

    var body: some View {
        Group {
            if lyric.lines.isEmpty {
                EmptyState(text: "暂无歌词")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(lyric.lines.enumerated()), id: \.offset) { i, line in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.text.isEmpty ? " " : line.text)
                                        .font(.title3.weight(.semibold))
                                    if let t = line.translation {
                                        Text(t).font(.callout).foregroundStyle(.secondary)
                                    }
                                }
                                .id(i)
                                .onTapGesture { state.player.seek(to: line.time) }
                            }
                        }
                        .padding(20)
                    }
                    .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                        let pos = state.player.position
                        if let i = lyric.lines.lastIndex(where: { $0.time <= pos }) {
                            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(i, anchor: .center) }
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
