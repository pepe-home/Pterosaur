// 搜索结果：曲目 / 歌单·磁带 / 艺人 / 专辑四个分区。
import PterosaurCore
import SwiftUI

struct SearchView: View {
    let query: String
    @ObservedObject var state: AppState
    @State private var result: AppServices.SearchResult?
    @State private var failed: String?

    var body: some View {
        Group {
            if let r = result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !r.songs.isEmpty {
                            block("曲目") {
                                List(Array(r.songs.enumerated()), id: \.offset) { i, t in
                                    SongRow(track: t, playing: state.player.currentId == keyOf(source: t.source, id: t.id),
                                            favorite: state.library.isFavorite(t),
                                            onToggleFavorite: { state.library.toggleFavorite(t) },
                                            onPlay: { state.playback.playAll(r.songs, from: i) })
                                }
                                .frame(height: min(CGFloat(r.songs.count) * 46, 480))
                                .scrollDisabled(true)
                            }
                        }
                        if !r.playlists.isEmpty {
                            block("歌单与磁带") {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 5), alignment: .leading, spacing: 16) {
                                    ForEach(Array(r.playlists.enumerated()), id: \.offset) { _, p in
                                        Button { state.open(.playlist(source: p.source, id: p.id)) } label: {
                                            CoverCard(title: p.name, subtitle: p.creator, cover: p.cover, wide: p.source == "bilibili")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        if !r.artists.isEmpty {
                            block("艺人") {
                                HStack(spacing: 18) {
                                    ForEach(Array(r.artists.prefix(8).enumerated()), id: \.offset) { _, a in
                                        Button { state.open(.artist(id: a.id)) } label: {
                                            VStack(spacing: 6) {
                                                RemoteImage(url: a.avatar, corner: 40).frame(width: 80, height: 80)
                                                Text(a.name).font(.callout).lineLimit(1)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        if !r.albums.isEmpty {
                            block("专辑") {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 5), alignment: .leading, spacing: 16) {
                                    ForEach(Array(r.albums.enumerated()), id: \.offset) { _, a in
                                        Button { state.open(.album(id: a.id)) } label: {
                                            CoverCard(title: a.name, subtitle: a.artist, cover: a.cover)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
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
        .navigationTitle("“\(query)”")
        .task(id: query) { load() }
    }

    private func block<C: View>(_ title: String, @ViewBuilder _ body: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold())
            body()
        }
    }

    private func load() {
        failed = nil
        let cookie = state.account.playbackCredential
        Task {
            do {
                result = try await Task.detached(priority: .userInitiated) {
                    try AppServices.search(query, cookie: cookie)
                }.value
            } catch {
                failed = "搜索失败：\(error)"
            }
        }
    }
}
