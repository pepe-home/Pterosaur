// 各类详情页的数据加载（统一在后台线程同步调 Core，结果回主线程）。
import Foundation
import PterosaurCore

enum Loaders {
    static func playlist(source: String, id: String, cookie: String?) async throws -> PlaylistWithTracks {
        try await Task.detached(priority: .userInitiated) {
            source == "bilibili"
                ? try bilibiliPlaylistTracks(id, cookie: nil)
                : neteasePlaylistTracks(id: id, cookie: cookie)
        }.value
    }

    static func artist(id: String, cookie: String?) async -> ArtistDetail? {
        await Task.detached(priority: .userInitiated) { neteaseArtistDetail(id: id, cookie: cookie) }.value
    }

    static func album(id: String, cookie: String?) async -> AlbumWithTracks? {
        await Task.detached(priority: .userInitiated) { neteaseAlbumDetail(id: id, cookie: cookie) }.value
    }

    static func toplists(cookie: String?) async -> [Playlist] {
        await Task.detached(priority: .userInitiated) { PterosaurCore.toplists(cookie: cookie) }.value
    }

    static func lyric(_ t: Track, cookie: String?) async -> Lyric {
        await Task.detached(priority: .userInitiated) {
            t.source == "bilibili" ? bilibiliLyric(t.id, cookie: nil) : getLyric(t.id, cookie: cookie)
        }.value
    }
}
