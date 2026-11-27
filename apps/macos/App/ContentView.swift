// 主界面：侧栏（资料库 / 发现 / 排行榜）+ 详情区 + 底部播放条（仿 Apple Music 的层级）。
import PterosaurCore
import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState()
    @Environment(\.openURL) private var openURL
    @State private var showingAccount: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                Sidebar(state: state, showingAccount: $showingAccount)
                    .navigationSplitViewColumnWidth(min: 210, ideal: 230)
            } detail: {
                NavigationStack(path: $state.path) {
                    root
                        .navigationDestination(for: Route.self) { r in
                            RouteView(route: r, state: state)
                        }
                }
            }
            Divider()
            PlayerBar(state: state)
        }
        .frame(minWidth: 860, minHeight: 560)
        .sheet(isPresented: $showingAccount) { AccountSheet(account: state.account) }
    }

    @ViewBuilder private var root: some View {
        switch state.route {
        case .discover: DiscoverView(state: state)
        case .favorites: TrackCollectionView(title: "我喜欢的音乐", tracks: state.library.favorites, state: state)
        case .recent: TrackCollectionView(title: "最近播放", tracks: state.library.recent, state: state)
        case .savedPlaylists: SavedPlaylistsView(state: state)
        case .savedArtists: SavedArtistsView(state: state)
        case .savedAlbums: SavedAlbumsView(state: state)
        case .topLists: TopListsView(state: state)
        case .localPlaylist(let id): LocalPlaylistView(id: id, state: state)
        default: DiscoverView(state: state)
        }
    }
}

private struct RouteView: View {
    let route: Route
    let state: AppState

    var body: some View {
        switch route {
        case .playlist(let source, let id): PlaylistDetailView(source: source, id: id, state: state)
        case .artist(let id): ArtistDetailView(id: id, state: state)
        case .album(let id): AlbumDetailView(id: id, state: state)
        case .search(let q): SearchView(query: q, state: state)
        case .topLists: TopListsView(state: state)
        case .localPlaylist(let id): LocalPlaylistView(id: id, state: state)
        default: DiscoverView(state: state)
        }
    }
}
