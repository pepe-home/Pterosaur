// 新发现：推荐歌单、新歌、本周新专辑、磁带（B 站），以及点击进入排行榜。
import PterosaurCore
import SwiftUI

struct DiscoverView: View {
    @ObservedObject var state: AppState
    @State private var data: DiscoverData?
    @State private var failed: String?

    var body: some View {
        Group {
            if let data {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        section("推荐歌单") {
                            grid(data.recommend.map { ($0.name, $0.creator, $0.cover, false, Route.playlist(source: $0.source, id: $0.id)) })
                        }
                        section("本周新专辑") {
                            grid(data.newAlbums.map { ($0.name, $0.artist, $0.cover, false, Route.album(id: $0.id)) })
                        }
                        section("磁带（B 站）") {
                            grid(data.cassettes.map { ($0.name, $0.creator, $0.cover, true, Route.playlist(source: $0.source, id: $0.id)) })
                        }
                        section("新歌精选") {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(data.newSongs.prefix(10).enumerated()), id: \.offset) { i, t in
                                    SongRow(track: t, playing: state.player.currentId == keyOf(source: t.source, id: t.id),
                                            favorite: state.library.isFavorite(t),
                                            onToggleFavorite: { state.library.toggleFavorite(t) },
                                            onPlay: { state.playback.playAll(data.newSongs, from: i) })
                                    Divider()
                                }
                                Button("播放全部 \(data.newSongs.count) 首") { state.playback.playAll(data.newSongs) }
                                    .padding(.top, 8)
                            }
                        }
                    }
                    .padding(24)
                }
            } else if let failed {
                ErrorState(message: failed) { load() }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("新发现")
        .toolbar {
            Button { state.open(.topLists) } label: { Label("排行榜", systemImage: "list.number") }
        }
        .task { if data == nil { load() } }
    }

    private func load() {
        failed = nil
        Task {
            data = await DiscoverLoader.load()
            if data == nil { failed = "加载失败" }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ body: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold())
            body()
        }
    }

    private typealias Card = (name: String, sub: String?, cover: String, wide: Bool, route: Route)

    private func grid(_ items: [Card]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 6), alignment: .leading, spacing: 18) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, c in
                Button { state.open(c.route) } label: {
                    CoverCard(title: c.name, subtitle: c.sub, cover: c.cover, wide: c.wide)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
