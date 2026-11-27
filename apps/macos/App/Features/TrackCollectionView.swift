// 通用曲目集合（我喜欢 / 最近播放 / 本地歌单）：无网络请求，直接展示资料库里的完整 Track。
import PterosaurCore
import SwiftUI

struct TrackCollectionView: View {
    let title: String
    let tracks: [Track]
    @ObservedObject var state: AppState
    var removable: ((Track) -> Void)?

    var body: some View {
        Group {
            if tracks.isEmpty {
                EmptyState(text: "还没有内容")
            } else {
                List(Array(tracks.enumerated()), id: \.offset) { i, t in
                    SongRow(track: t, playing: state.player.currentId == keyOf(source: t.source, id: t.id),
                            favorite: state.library.isFavorite(t),
                            onToggleFavorite: { state.library.toggleFavorite(t) },
                            onPlay: { state.playback.playAll(tracks, from: i) })
                    .listRowBackground(Color.clear)
                    .contextMenu {
                        if let removable { Button("从歌单移除", role: .destructive) { removable(t) } }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(title)
        .toolbar {
            Button {
                state.playback.playAll(tracks)
            } label: { Label("播放全部", systemImage: "play.fill") }
                .disabled(tracks.isEmpty)
        }
    }
}
