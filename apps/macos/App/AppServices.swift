// App 层的网络入口：UI 只经这里调 Core（「只有 Core 可以请求上游」的具体落点）。
//
// 所有调用都是同步阻塞的（Core 用 URLSession 同步发送），一律在 `Task.detached` 里跑，
// 回到主线程再交给 `@MainActor` 的模型。
import Foundation
import PterosaurCore

enum AppServices {
    /// 搜索：单曲 + 歌单 / 磁带；任一失败向调用方抛错（界面出错误态 + 重试）。
    struct SearchResult: Sendable {
        var songs: [Track] = []
        var playlists: [Playlist] = []
        var artists: [Artist] = []
        var albums: [Album] = []
    }

    static func search(_ keyword: String, cookie: String?) throws -> SearchResult {
        var r = SearchResult()
        r.songs = searchSongs(keyword, limit: 30, cookie: cookie)
        r.playlists = searchPlaylists(keyword, limit: 20, cookie: cookie)
        r.artists = searchArtists(keyword, limit: 10, cookie: cookie)
        r.albums = searchAlbums(keyword, limit: 10, cookie: cookie)
        // 磁带（B 站）单独列，失败不拖垮整页
        r.playlists += (try? searchCassettes(keyword, limit: 10, cookie: nil)) ?? []
        return r
    }
}
