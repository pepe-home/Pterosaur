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
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHGrid(rows: [GridItem(.fixed(200))], spacing: 16) {
                                    ForEach(Array(data.cassettes.enumerated()), id: \.offset) { _, p in
                                        Button { state.open(.playlist(source: p.source, id: p.id)) } label: {
                                            CoverCard(title: p.name, subtitle: p.creator, cover: p.cover, wide: true) {
                                                playRoute(.playlist(source: p.source, id: p.id), state: state)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .frame(width: 300)
                                    }
                                }
                            }
                        }
                        section("新歌精选") {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(data.newSongs.prefix(10).enumerated()), id: \.offset) { i, t in
                                    SongRow(track: t, playing: state.player.currentId == keyOf(source: t.source, id: t.id),
                                            favorite: state.library.isFavorite(t),
                                            onToggleFavorite: { state.library.toggleFavorite(t) },
                                            onPlay: { state.playback.playAll(data.newSongs, from: i) })
                                    Divider().opacity(0.5)
                                }
                                PrimaryActionButton(title: "播放全部 \(data.newSongs.count) 首") {
                                    state.playback.playAll(data.newSongs)
                                }
                                .padding(.top, 10)
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

    /// 卡片悬停播放：歌单 / 专辑各自拉曲目后开播。
    private func playCard(_ route: Route) {
        switch route {
        case .album(let id): playAlbum(id, state: state)
        default: playRoute(route, state: state)
        }
    }

    private typealias Card = (name: String, sub: String?, cover: String, wide: Bool, route: Route)

    private func grid(_ items: [Card]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 6), alignment: .leading, spacing: 18) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, c in
                Button { state.open(c.route) } label: {
                    CoverCard(title: c.name, subtitle: c.sub, cover: c.cover, wide: c.wide) { playCard(c.route) }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
