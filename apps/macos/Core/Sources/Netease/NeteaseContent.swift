// 网易云的内容能力（Swift 版，对应 packages/core/src/sources/netease.ts 的搜索 / 发现 / 详情 /
// 分页收集等函数）。归一化在 `NeteaseNormalize.swift`，播放地址与歌词在 `Playback.swift`，
// 扫码登录在 `QrLogin.swift`。
import Foundation

/// 歌单分类分组（「语种」「风格」…）。
public struct PlaylistCategoryGroup: Sendable, Equatable {
    public let name: String
    public let tags: [String]
    public init(name: String, tags: [String]) {
        self.name = name
        self.tags = tags
    }
}

/// 一次「歌单详情」：档案 + 曲目。
public struct PlaylistWithTracks: Sendable {
    public let playlist: Playlist
    public let tracks: [Track]
    public init(playlist: Playlist, tracks: [Track]) {
        self.playlist = playlist
        self.tracks = tracks
    }
}

/// 一次「专辑详情」：档案 + 曲目。
public struct AlbumWithTracks: Sendable {
    public let album: Album
    public let tracks: [Track]
    public init(album: Album, tracks: [Track]) {
        self.album = album
        self.tracks = tracks
    }
}

/// 一次「艺术家详情」：档案 + 热门单曲 + 全部作品。
public struct ArtistDetail: Sendable {
    public let artist: Artist
    public let tracks: [Track]
    public let albums: [Album]
    public init(artist: Artist, tracks: [Track], albums: [Album]) {
        self.artist = artist
        self.tracks = tracks
        self.albums = albums
    }
}

private func bodyObject(_ r: NcmResult) -> [String: Any]? { r.body as? [String: Any] }
private func list<T>(_ r: NcmResult, _ path: String..., convert: (Any) -> T?) -> [T] {
    var cur: Any? = r.body
    for key in path { cur = (cur as? [String: Any])?[key] }
    return (cur as? [Any] ?? []).compactMap(convert)
}
private func asJSON(_ v: Any?) -> JSON? { v as? JSON }

/// 1 起的页码 → 0 起的 offset。
private func offsetOf(_ page: Int, _ limit: Int) -> Int { max(0, (max(1, page) - 1) * limit) }

/* ============================ 搜索 ============================ */

public func searchSongs(_ keywords: String, limit: Int = 30, cookie: String? = nil, page: Int = 1) -> [Track] {
    list(cloudsearch(keywords: keywords, limit: limit, offset: offsetOf(page, limit), cookie: cookie),
         "result", "songs", convert: { asJSON($0).map(normalizeTrack) })
}

public func searchArtists(_ keywords: String, limit: Int = 30, cookie: String? = nil, page: Int = 1) -> [Artist] {
    list(cloudsearch(keywords: keywords, type: 100, limit: limit, offset: offsetOf(page, limit), cookie: cookie),
         "result", "artists", convert: { asJSON($0).map(normalizeArtist) })
}

public func searchAlbums(_ keywords: String, limit: Int = 30, cookie: String? = nil, page: Int = 1) -> [Album] {
    list(cloudsearch(keywords: keywords, type: 10, limit: limit, offset: offsetOf(page, limit), cookie: cookie),
         "result", "albums", convert: { asJSON($0).map(normalizeAlbum) })
}

public func searchPlaylists(_ keywords: String, limit: Int = 30, cookie: String? = nil, page: Int = 1) -> [Playlist] {
    list(cloudsearch(keywords: keywords, type: 1000, limit: limit, offset: offsetOf(page, limit), cookie: cookie),
         "result", "playlists", convert: { asJSON($0).map(normalizePlaylist) })
}

/* ============================ 发现 ============================ */

/// 首页个性化推荐歌单。
public func recommendPlaylists(limit: Int = 12, cookie: String? = nil) -> [Playlist] {
    list(personalized(limit: limit, cookie: cookie), "result", convert: { asJSON($0).map(normalizePlaylist) })
}

/// 排行榜列表（`trackCount` 缺失时取上游 `size`）。
public func toplists(cookie: String? = nil) -> [Playlist] {
    list(toplist(cookie: cookie), "list") { raw in
        guard let o = asJSON(raw) else { return nil }
        var p = normalizePlaylist(o)
        if p.trackCount == nil, let size = (o["size"] as? NSNumber)?.intValue { p.trackCount = size }
        return p
    }
}

/// 网易云官方「热歌榜」歌单 id（`/api/toplist` 中固定出现）。
private let HOT_PLAYLIST_ID = "3778678"

/// 「正在流行中」：热歌榜当天的曲目，按榜单顺序（即热度）取前 `limit` 首。
public func hotSongs(limit: Int = 24, cookie: String? = nil) -> [Track] {
    let tracks = list(playlistDetail(id: HOT_PLAYLIST_ID, s: 8, cookie: cookie), "playlist", "tracks") { raw -> Track? in
        guard let o = asJSON(raw), (o["id"] as? NSNumber) != nil || (o["id"] as? String) != nil else { return nil }
        return normalizeTrack(o)
    }
    return Array(tracks.prefix(limit))
}

/// 精品歌单（「歌单已更新」）：上游按歌单更新时间倒序；`page` 从 1 起。
public func topPlaylists(limit: Int = 12, cat: String = "全部", page: Int = 1, cookie: String? = nil) -> [Playlist] {
    list(topPlaylist(cat: cat, limit: limit, offset: offsetOf(page, limit), cookie: cookie),
         "playlists", convert: { asJSON($0).map(normalizePlaylist) })
}

/// 「新歌精选」：上游把每条包在 `{ id, name, picUrl, song }` 里，真正的曲目在 `song`；
/// 少数条目 `song` 缺失，直接跳过（没有 id 就无法播放）。
public func newSongs(limit: Int = 20, cookie: String? = nil) -> [Track] {
    list(personalizedNewsong(limit: limit, cookie: cookie), "result") { raw -> Track? in
        guard let o = asJSON(raw), let song = asJSON(o["song"]),
              (song["id"] as? NSNumber) != nil || (song["id"] as? String) != nil else { return nil }
        return normalizeTrack(song)
    }
}

/// 歌单分类标签：按 `categories` 的声明顺序分组，只保留真正能在本应用里取到歌单的标签。
public func playlistCategories(cookie: String? = nil) -> [PlaylistCategoryGroup] {
    guard let body = bodyObject(playlistCatlist(cookie: cookie)) else { return [] }
    let categories = body["categories"] as? [String: Any] ?? [:]
    let subs = body["sub"] as? [Any] ?? []
    // `categories` 是 `id → 分组名`；上游按声明顺序返回（数字键升序），Swift 字典无序，按数字键排序还原
    let ordered = categories.compactMap { key, value -> (Int, String, String)? in
        guard let name = value as? String, let n = Int(key) else { return nil }
        return (n, key, name)
    }.sorted { $0.0 < $1.0 }
    return ordered.map { (_, id, name) in
        let tags = subs.compactMap { raw -> String? in
            guard let t = asJSON(raw), let cat = (t["category"] as? NSNumber)?.intValue,
                  String(cat) == id, let tag = t["name"] as? String, !tag.isEmpty else { return nil }
            return tag
        }
        return PlaylistCategoryGroup(name: name, tags: tags)
    }
}

/// 「本周新发行」：最近发布的专辑（上游固定回 12 条）。
public func newAlbums(limit: Int = 12, cookie: String? = nil) -> [Album] {
    list(albumNewest(cookie: cookie), "albums", convert: { asJSON($0).map(normalizeAlbum) }).prefix(limit).map { $0 }
}

/* ============================ 详情 ============================ */

/// 歌单详情曲目（`netease` 前缀避免与 B 站磁带同名的 `playlistTracks` 混淆）。上游缺 `playlist` 时回空壳档案（`id` 保留、封面为空），与参考实现一致。
public func neteasePlaylistTracks(id: String, cookie: String? = nil) -> PlaylistWithTracks {
    let r = playlistDetail(id: id, s: 8, cookie: cookie)
    let body = bodyObject(r)
    let pl = asJSON(body?["playlist"])
    let playlist: Playlist
    if let pl {
        var p = normalizePlaylist(pl)
        p.cover = coverUrl(pl["coverImgUrl"] as? String)
        playlist = p
    } else {
        playlist = Playlist(id: id, name: "歌单", cover: "")
    }
    let tracks = (pl?["tracks"] as? [Any] ?? []).compactMap(asJSON).map(normalizeTrack)
    return PlaylistWithTracks(playlist: playlist, tracks: tracks)
}

/// 艺术家作品分页拉取的三个上限：单页 200、最多 10 页（合计 ≤2000 张）。
public let ARTIST_ALBUM_PAGE = 200
public let ARTIST_ALBUM_MAX_PAGES = 10

/// 分页收集作品：`fetchPage` 返回该页列表与「是否还有更多」。
///
/// 停止条件三者取先：本页不足一页（已到末尾）、显式 `more == false`、或已达页数上限。
/// 单页抛错时保留已取到的部分——作品区短一点好过整页打不开。抽成纯函数便于单测。
public func collectAlbumPages(
    pageSize: Int = ARTIST_ALBUM_PAGE,
    maxPages: Int = ARTIST_ALBUM_MAX_PAGES,
    _ fetchPage: (Int) throws -> (list: [Any], more: Bool?)?
) -> [Any] {
    let limit = pageSize * maxPages
    var all: [Any] = []
    for page in 0..<maxPages {
        guard let res = try? fetchPage(page * pageSize) else { break }
        all.append(contentsOf: res.list)
        if res.list.count < pageSize { break }
        if res.more == false { break }
        if all.count >= limit { break }
    }
    return Array(all.prefix(limit))
}

/// 拉取艺术家的全部作品（分页循环，见 `collectAlbumPages`）。
func fetchArtistAlbums(id: String, cookie: String?) -> [JSON] {
    collectAlbumPages { offset in
        let body = bodyObject(artistAlbum(id: id, limit: ARTIST_ALBUM_PAGE, offset: offset, cookie: cookie))
        return ((body?["hotAlbums"] ?? body?["albums"]) as? [Any] ?? [], (body?["more"] as? NSNumber)?.boolValue)
    }.compactMap(asJSON)
}

/// 艺术家详情：档案 + 热门单曲（上游固定约 50 首）+ 全部作品（上限 2000 张）。
public func neteaseArtistDetail(id: String, cookie: String? = nil) -> ArtistDetail {
    let info = bodyObject(artists(id: id, cookie: cookie))
    let raw = asJSON(info?["artist"]) ?? ["id": id, "name": "未知艺术家"]
    let artist = normalizeArtist(raw)
    let tracks = (info?["hotSongs"] as? [Any] ?? []).compactMap(asJSON).map(normalizeTrack)
    let albums = fetchArtistAlbums(id: id, cookie: cookie).map(normalizeAlbum)
    return ArtistDetail(artist: artist, tracks: tracks, albums: albums)
}

/// 专辑详情：档案 + 曲目。`size` 缺失时取曲目条数（`netease` 前缀同 `neteasePlaylistTracks`）。
public func neteaseAlbumDetail(id: String, cookie: String? = nil) -> AlbumWithTracks {
    let r = album(id: id, cookie: cookie)
    let body = bodyObject(r)
    var raw = asJSON(body?["album"]) ?? ["id": id, "name": "未知专辑"]
    if raw["size"] == nil {
        let count = (body?["songs"] as? [Any])?.count
        if let count { raw["size"] = count }
    }
    let tracks = (body?["songs"] as? [Any] ?? []).compactMap(asJSON).map(normalizeTrack)
    return AlbumWithTracks(album: normalizeAlbum(raw), tracks: tracks)
}

/// 曲目详情（用于补全搜索未覆盖的元数据；`songDetailRaw` 是同名上游接口）。
public func songDetail(ids: [String], cookie: String? = nil) -> [Track] {
    list(songDetailRaw(ids: ids, cookie: cookie), "songs", convert: { asJSON($0).map(normalizeTrack) })
}
