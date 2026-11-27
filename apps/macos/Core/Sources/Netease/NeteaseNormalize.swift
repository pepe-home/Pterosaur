// 上游原始 JSON → 共享模型（Swift 版，对应 packages/core/src/sources/netease.ts 的 normalize*）。
//
// 直接读 `[String: Any]`（JSONSerialization）而不是 Codable typed 解码：上游字段缺失时要落到
// 「缺省」而非类型默认，与 TS 的可选链语义逐项对齐（golden/normalize.json 逐条校验）。
import Foundation

// MARK: - 轻量 JSON 读取

/// 上游原始 JSON 对象的统一定义（公开：`public func normalize*` 的签名用到它）。
public typealias JSON = [String: Any]

func jsonString(_ v: Any?) -> String? {
    if let s = v as? String { return s }
    if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.stringValue }
    return nil
}

func jsonInt(_ v: Any?) -> Int? {
    if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.intValue }
    if let s = v as? String { return Int(s) }
    return nil
}

func jsonLong(_ v: Any?) -> Int64? {
    if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.int64Value }
    if let s = v as? String { return Int64(s) }
    return nil
}

func jsonArray(_ v: Any?) -> [Any]? { v as? [Any] }
func jsonObject(_ v: Any?) -> JSON? { v as? JSON }

private func str(_ o: JSON?, _ key: String) -> String? { jsonString(o?[key]) }
private func int(_ o: JSON?, _ key: String) -> Int? { jsonInt(o?[key]) }
private func long(_ o: JSON?, _ key: String) -> Int64? { jsonLong(o?[key]) }
private func arr(_ o: JSON?, _ key: String) -> [Any]? { jsonArray(o?[key]) }
private func obj(_ o: JSON?, _ key: String) -> JSON? { jsonObject(o?[key]) }

// MARK: - 网易云

let BASE_COVER_SIZE = "\(COVER_LARGE)y\(COVER_LARGE)"

/// 规范化后重设尺寸参数；解析不了返回空串（同 TS 的 coverUrl）。
func coverUrl(_ raw: String?, size: String = BASE_COVER_SIZE) -> String {
    guard let raw, !raw.isEmpty else { return "" }
    guard let u = splitUrl(canonicalNeteaseImage(raw)) else { return "" }
    return joinUrl(u, rest: replaceQuery(u.rest, "param=\(Encoding.formUrlEncode(size))"))
}

private func feeOf(_ fee: Int?) -> String {
    switch fee {
    case nil: return "unknown"
    case 0: return "free"
    case 8, 4, 1: return "vip"
    default: return "unknown"
    }
}

private func albumTypeOf(_ raw: String?) -> String? {
    guard let t = raw?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
    if t.isEmpty { return nil }
    switch t {
    case "专辑", "album": return "album"
    case "single", "单曲": return "single"
    case "ep": return "ep"
    default: return "other"
    }
}

private func artistRefsOf(_ list: [JSON]) -> [ArtistRef] {
    list.compactMap { a in
        guard let id = long(a, "id"), let name = str(a, "name"), !name.isEmpty else { return nil }
        return ArtistRef(id: String(id), name: name)
    }
}

/// 曲目归一化。
public func normalizeTrack(_ raw: JSON) -> Track {
    let list = (arr(raw, "ar") ?? arr(raw, "artists") ?? []).compactMap(jsonObject)
    let names = list.compactMap { s in str(s, "name").flatMap { $0.isEmpty ? nil : $0 } }
    let refs = artistRefsOf(list)
    let album = obj(raw, "al") ?? obj(raw, "album")
    let coverRaw = str(album, "picUrl") ?? str(album, "blurPicUrl") ?? ""
    let durationMs = long(raw, "dt") ?? long(raw, "duration") ?? 0
    return Track(
        id: jsonString(raw["id"]) ?? long(raw, "id").map(String.init) ?? "",
        title: str(raw, "name") ?? "未知曲目",
        artist: names.isEmpty ? "未知艺术家" : names.joined(separator: ARTIST_SEPARATOR),
        album: str(album, "name") ?? "",
        cover: coverUrl(coverRaw),
        duration: Int((Double(durationMs) / 1000.0).rounded()),
        fee: feeOf(int(raw, "fee")),
        artistRefs: refs.isEmpty ? nil : refs,
        albumId: long(album, "id").map(String.init))
}

/// 艺术家归一化。
public func normalizeArtist(_ raw: JSON) -> Artist {
    let alias = arr(raw, "alias")?.compactMap { $0 as? String }.filter { !$0.isEmpty }
    return Artist(
        id: jsonString(raw["id"]) ?? long(raw, "id").map(String.init) ?? "",
        name: str(raw, "name") ?? "未知艺术家",
        avatar: coverUrl(str(raw, "picUrl")),
        alias: (alias?.isEmpty ?? true) ? nil : alias,
        albumSize: int(raw, "albumSize"),
        musicSize: int(raw, "musicSize"),
        briefDesc: str(raw, "briefDesc").flatMap { $0.isEmpty ? nil : $0 })
}

/// 专辑归一化。
public func normalizeAlbum(_ raw: JSON) -> Album {
    let list: [JSON]
    if let a = arr(raw, "artists") {
        list = a.compactMap(jsonObject)
    } else if let single = obj(raw, "artist") {
        list = [single]
    } else {
        list = []
    }
    let names = list.compactMap { s in str(s, "name").flatMap { $0.isEmpty ? nil : $0 } }
    let refs = artistRefsOf(list)
    let tags = str(raw, "tags")?.trimmingCharacters(in: .whitespaces)
    let year = long(raw, "publishTime").map { ms -> Int in
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.component(.year, from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }
    return Album(
        id: jsonString(raw["id"]) ?? long(raw, "id").map(String.init) ?? "",
        name: str(raw, "name") ?? "未命名专辑",
        cover: coverUrl(str(raw, "picUrl")),
        artist: names.isEmpty ? "未知艺术家" : names.joined(separator: ARTIST_SEPARATOR),
        artistId: refs.first?.id,
        artistRefs: refs.isEmpty ? nil : refs,
        year: year,
        genre: (tags?.isEmpty ?? true) ? nil : tags,
        type: albumTypeOf(str(raw, "type")),
        trackCount: int(raw, "size") ?? int(raw, "trackCount"))
}

/// 歌单归一化。
public func normalizePlaylist(_ raw: JSON) -> Playlist {
    Playlist(
        id: jsonString(raw["id"]) ?? long(raw, "id").map(String.init) ?? "",
        name: str(raw, "name") ?? "未命名歌单",
        cover: coverUrl(str(raw, "coverImgUrl") ?? str(raw, "picUrl") ?? ""),
        description: str(raw, "description"),
        trackCount: int(raw, "trackCount"),
        playCount: long(raw, "playCount").map(Int.init),
        creator: str(obj(raw, "creator"), "nickname"))
}