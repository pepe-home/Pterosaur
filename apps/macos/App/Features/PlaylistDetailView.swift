// 歌单 / 磁带详情：封面 hero + 操作区 + 曲目表。磁带（B 站）的曲目是分P（ADR-044）。
import PterosaurCore
import SwiftUI

struct PlaylistDetailView: View {
    let source: String
    let id: String
    @ObservedObject var state: AppState
    @State private var result: PlaylistWithTracks?
    @State private var failed: String?

    var body: some View {
        Group {
            if let result {
                VStack(spacing: 0) {
                    hero(result.playlist)
                    if result.tracks.isEmpty {
                        EmptyState(text: "没有可播放的曲目")
                    } else {
                        List(Array(result.tracks.enumerated()), id: \.offset) { i, t in
                            SongRow(track: t, playing: state.player.currentId == keyOf(source: t.source, id: t.id),
                                    favorite: state.library.isFavorite(t),
                                    onToggleFavorite: { state.library.toggleFavorite(t) },
                                    onPlay: { state.playback.playAll(result.tracks, from: i) })
                            .tag(i)
                        }
                        .listStyle(.plain)
                    }
                }
            } else if let failed {
                ErrorState(message: failed) { load() }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(result?.playlist.name ?? (source == "bilibili" ? "磁带" : "歌单"))
        .task(id: id) { load() }
    }

    private func hero(_ p: Playlist) -> some View {
        HStack(alignment: .bottom, spacing: 18) {
            RemoteImage(url: p.cover, corner: 10)
                .frame(width: source == "bilibili" ? 220 : 150, height: source == "bilibili" ? 124 : 150)
                .shadow(radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(source == "bilibili" ? "磁带" : "歌单").font(.caption).foregroundStyle(.secondary)
                Text(p.name).font(.system(size: 26, weight: .bold)).lineLimit(2)
                HStack(spacing: 12) {
                    if let c = p.creator { Text(c) }
                    if let n = p.trackCount { Text("\(n) \(source == "bilibili" ? "个分P" : "首")") }
                    if let play = p.playCount { Text("\(play) 次播放") }
                }
                .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button {
                        if let r = result, !r.tracks.isEmpty { state.playback.playAll(r.tracks) }
                    } label: {
                        Label("播放", systemImage: "play.fill").padding(.horizontal, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        state.library.toggleSaved(p)
                    } label: {
                        Image(systemName: state.library.isSaved(p) ? "heart.fill" : "heart")
                    }
                    .help(state.library.isSaved(p) ? "取消收藏" : "收藏")
                }
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(24)
    }

    private func load() {
        failed = nil
        result = nil
        let cookie = state.account.playbackCredential
        Task {
            do {
                result = try await Loaders.playlist(source: source, id: id, cookie: cookie)
            } catch {
                failed = "加载失败：\(error)"
            }
        }
    }
}
