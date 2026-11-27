// 发现：推荐歌单 / 新歌 / 新专辑 / 排行榜入口 / 磁带（B 站）——一次并发拉取。
import Foundation
import PterosaurCore

struct DiscoverData: Sendable {
    var recommend: [Playlist] = []
    var newSongs: [Track] = []
    var newAlbums: [Album] = []
    var cassettes: [Playlist] = []
}

enum DiscoverLoader {
    static func load() async -> DiscoverData {
        await Task.detached(priority: .userInitiated) {
            var d = DiscoverData()
            d.recommend = recommendPlaylists(limit: 12)
            d.newSongs = newSongs(limit: 20)
            d.newAlbums = newAlbums(limit: 12)
            d.cassettes = (try? searchCassettes("音乐 合集", limit: 8)) ?? []
            return d
        }.value
    }
}
