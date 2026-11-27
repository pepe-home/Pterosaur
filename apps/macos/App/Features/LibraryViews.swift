// 资料库的集合视图：收藏的歌单与磁带、艺人、专辑；本地歌单与其详情；排行榜列表。
import PterosaurCore
import SwiftUI

struct SavedPlaylistsView: View {
    @ObservedObject var state: AppState
    @State private var newName = ""
    @State private var creating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !state.library.playlists.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("我的歌单").font(.title2.bold())
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 6), alignment: .leading, spacing: 16) {
                            ForEach(state.library.playlists) { p in
                                Button { state.open(.localPlaylist(id: p.id)) } label: {
                                    CoverCard(title: p.name, subtitle: "\(p.tracks.count) 首",
                                              cover: p.tracks.first?.cover ?? "")
                                }
                                .buttonStyle(.plain)
                                .contextMenu { Button("删除歌单", role: .destructive) { state.library.deletePlaylist(p.id) } }
                            }
                        }
                    }
                }
                if !state.library.savedPlaylists.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("收藏的歌单与磁带").font(.title2.bold())
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 6), alignment: .leading, spacing: 16) {
                            ForEach(Array(state.library.savedPlaylists.enumerated()), id: \.offset) { _, p in
                                Button { state.open(.playlist(source: p.source, id: p.id)) } label: {
                                    CoverCard(title: p.name, subtitle: p.creator, cover: p.cover, wide: p.source == "bilibili")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if state.library.playlists.isEmpty && state.library.savedPlaylists.isEmpty {
                    EmptyState(text: "还没有收藏的歌单，绑定账号或从搜索里收藏")
                }
            }
            .padding(24)
        }
        .navigationTitle("歌单")
        .toolbar {
            Button { creating = true } label: { Label("新建歌单", systemImage: "plus") }
        }
        .alert("新建歌单", isPresented: $creating) {
            TextField("名称", text: $newName)
            Button("创建") {
                let n = newName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { state.library.createPlaylist(name: n) }
                newName = ""
            }
            Button("取消", role: .cancel) { newName = "" }
        }
    }
}

struct LocalPlaylistView: View {
    let id: String
    @ObservedObject var state: AppState

    var body: some View {
        if let p = state.library.playlists.first(where: { $0.id == id }) {
            TrackCollectionView(title: p.name, tracks: p.tracks, state: state) { t in
                state.library.remove(t, fromPlaylist: id)
            }
        } else {
            EmptyState(text: "歌单已删除")
        }
    }
}

struct SavedArtistsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            if state.library.savedArtists.isEmpty {
                EmptyState(text: "还没有收藏的艺人")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 7), alignment: .leading, spacing: 20) {
                    ForEach(Array(state.library.savedArtists.enumerated()), id: \.offset) { _, a in
                        Button { state.open(.artist(id: a.id)) } label: {
                            VStack(spacing: 6) {
                                RemoteImage(url: a.avatar, corner: 50).frame(width: 100, height: 100)
                                Text(a.name).font(.callout).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle("艺人")
    }
}

struct SavedAlbumsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            if state.library.savedAlbums.isEmpty {
                EmptyState(text: "还没有收藏的专辑")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 6), alignment: .leading, spacing: 16) {
                    ForEach(Array(state.library.savedAlbums.enumerated()), id: \.offset) { _, a in
                        Button { state.open(.album(id: a.id)) } label: {
                            CoverCard(title: a.name, subtitle: a.artist, cover: a.cover)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle("专辑")
    }
}

struct TopListsView: View {
    @ObservedObject var state: AppState
    @State private var lists: [Playlist] = []

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 5), alignment: .leading, spacing: 16) {
                ForEach(Array(lists.enumerated()), id: \.offset) { _, p in
                    Button { state.open(.playlist(source: p.source, id: p.id)) } label: {
                        CoverCard(title: p.name, subtitle: p.trackCount.map { "\($0) 首" }, cover: p.cover)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .navigationTitle("排行榜")
        .task { if lists.isEmpty { lists = await Loaders.toplists(cookie: state.account.playbackCredential) } }
    }
}
