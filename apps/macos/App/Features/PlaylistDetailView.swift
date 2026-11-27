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
                        EmptyState(text: "没有可播放的曲目", symbol: "music.note.list")
                    } else {
                        List(Array(result.tracks.enumerated()), id: \.offset) { i, t in
                            SongRow(track: t, playing: state.player.currentId == keyOf(source: t.source, id: t.id),
                                    favorite: state.library.isFavorite(t),
                                    onToggleFavorite: { state.library.toggleFavorite(t) },
                                    onPlay: { state.playback.playAll(result.tracks, from: i) })
                            .listRowBackground(Color.clear)
                            .tag(i)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
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
        HStack(alignment: .bottom, spacing: 22) {
            RemoteImage(url: p.cover, corner: 12)
                .frame(width: source == "bilibili" ? 240 : 160, height: source == "bilibili" ? 135 : 160)
                .shadow(color: .black.opacity(0.3), radius: 22, y: 12)
            VStack(alignment: .leading, spacing: 8) {
                Text(source == "bilibili" ? "磁带" : "歌单")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(p.name).font(.system(size: 30, weight: .bold)).lineLimit(2)
                HStack(spacing: 12) {
                    if let c = p.creator { Text(c) }
                    if let n = p.trackCount { Text("\(n) \(source == "bilibili" ? "个分P" : "首")") }
                    if let play = p.playCount { Text("\(play) 次播放") }
                }
                .font(.callout).foregroundStyle(.secondary)
                if let d = p.description, !d.isEmpty {
                    Text(d).font(.callout).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: 520, alignment: .leading)
                }
                HStack(spacing: 10) {
                    PrimaryActionButton(title: "播放") {
                        if let r = result, !r.tracks.isEmpty { state.playback.playAll(r.tracks) }
                    }
                    Button {
                        state.library.toggleSaved(p)
                    } label: {
                        Image(systemName: state.library.isSaved(p) ? "heart.fill" : "heart")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .help(state.library.isSaved(p) ? "取消收藏" : "收藏")
                }
                .padding(.top, 6)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(alignment: .topLeading) {
            // hero 后面铺一层极淡的代表色，把封面与服务区连起来
            RemoteImage(url: p.cover, corner: 0)
                .blur(radius: 60).opacity(0.25).allowsHitTesting(false)
        }
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
