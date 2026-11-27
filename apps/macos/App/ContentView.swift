// 主界面：侧栏（资料库 / 发现 / 排行榜）+ 详情区 + 悬浮玻璃播放条（ADR-070）。
//
// 背景铺满全窗口（含标题栏），侧栏与播放条都是浮在这层背景上的玻璃——Liquid Glass 下
// 这比「不透明分栏」更像原生；内容本身不套玻璃，只在需要与背景分离的地方（播放条、主按钮）用。
import PterosaurCore
import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState()
    @Environment(\.openURL) private var openURL
    @State private var showingAccount: Bool = false
    @StateObject private var art = ArtColorLoader()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            AppBackground(artColor: art.color)
            NavigationSplitView {
                Sidebar(state: state, showingAccount: $showingAccount)
                    .navigationSplitViewColumnWidth(min: 210, ideal: 236)
            } detail: {
                NavigationStack(path: $state.path) {
                    root
                        .navigationDestination(for: Route.self) { r in
                            RouteView(route: r, state: state)
                        }
                }
                // 详情区内容铺到标题栏下，玻璃工具栏才有可透的内容
                .backgroundExtensionEffect()
            }
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 14) {
                PlayerBar(state: state)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
            }
        }
        .frame(minWidth: 900, minHeight: 580)
        .onChange(of: state.queue.current?.cover, initial: true) { _, cover in art.load(cover: cover) }
        .sheet(isPresented: $showingAccount) {
            AccountSheet(account: state.account)
                .presentationBackground(.ultraThinMaterial)
        }
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
