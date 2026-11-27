// 艺人详情（档案 + 热门单曲 + 全部作品）与专辑详情（档案 + 曲目）。
import PterosaurCore
import SwiftUI

struct ArtistDetailView: View {
    let id: String
    @ObservedObject var state: AppState
    @State private var detail: ArtistDetail?

    var body: some View {
        Group {
            if let d = detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .bottom, spacing: 18) {
                            RemoteImage(url: d.artist.avatar, corner: 60).frame(width: 140, height: 140)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("艺人").font(.caption).foregroundStyle(.secondary)
                                Text(d.artist.name).font(.system(size: 28, weight: .bold))
                                if let alias = d.artist.alias, !alias.isEmpty {
                                    Text(alias.joined(separator: " / ")).font(.callout).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button { state.library.toggleSaved(d.artist) } label: {
                                Label("收藏艺人", systemImage: "plus.circle")
                            }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("热门单曲").font(.title2.bold())
                            List(Array(d.tracks.prefix(20).enumerated()), id: \.offset) { i, t in
                                SongRow(track: t, playing: state.player.currentId == keyOf(source: t.source, id: t.id),
                                        favorite: state.library.isFavorite(t),
                                        onToggleFavorite: { state.library.toggleFavorite(t) },
                                        onPlay: { state.playback.playAll(d.tracks, from: i) })
                            }
                            .frame(height: min(CGFloat(min(d.tracks.count, 20)) * 46, 560))
                            .scrollDisabled(true)
                        }
                        if !d.albums.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("专辑 \(d.albums.count)").font(.title2.bold())
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 6), alignment: .leading, spacing: 16) {
                                    ForEach(Array(d.albums.enumerated()), id: \.offset) { _, a in
                                        Button { state.open(.album(id: a.id)) } label: {
                                            CoverCard(title: a.name, subtitle: a.year.map(String.init), cover: a.cover)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(24)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(detail?.artist.name ?? "艺人")
        .task(id: id) { detail = await Loaders.artist(id: id, cookie: state.account.playbackCredential) }
    }
}

struct AlbumDetailView: View {
    let id: String
    @ObservedObject var state: AppState
    @State private var detail: AlbumWithTracks?

    var body: some View {
        Group {
            if let d = detail {
                VStack(spacing: 0) {
                    HStack(alignment: .bottom, spacing: 18) {
                        RemoteImage(url: d.album.cover, corner: 10).frame(width: 150, height: 150).shadow(radius: 8, y: 4)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("专辑").font(.caption).foregroundStyle(.secondary)
                            Text(d.album.name).font(.system(size: 26, weight: .bold)).lineLimit(2)
                            HStack(spacing: 10) {
                                if let aid = d.album.artistId {
                                    Button(d.album.artist) { state.open(.artist(id: aid)) }.buttonStyle(.link)
                                } else {
                                    Text(d.album.artist)
                                }
                                if let y = d.album.year { Text(String(y)) }
                                if let n = d.album.trackCount { Text("\(n) 首") }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                Button { state.playback.playAll(d.tracks) } label: {
                                    Label("播放", systemImage: "play.fill").padding(.horizontal, 10)
                                }
                                .buttonStyle(.borderedProminent)
                                Button { state.library.toggleSaved(d.album) } label: {
                                    Image(systemName: state.library.savedAlbums.contains { $0.id == d.album.id } ? "heart.fill" : "heart")
                                }
                            }
                            .padding(.top, 4)
                        }
                        Spacer()
                    }
                    .padding(24)
                    List(Array(d.tracks.enumerated()), id: \.offset) { i, t in
                        SongRow(track: t, playing: state.player.currentId == keyOf(source: t.source, id: t.id),
                                favorite: state.library.isFavorite(t),
                                onToggleFavorite: { state.library.toggleFavorite(t) },
                                onPlay: { state.playback.playAll(d.tracks, from: i) })
                    }
                    .listStyle(.plain)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(detail?.album.name ?? "专辑")
        .task(id: id) { detail = await Loaders.album(id: id, cookie: state.account.playbackCredential) }
    }
}
