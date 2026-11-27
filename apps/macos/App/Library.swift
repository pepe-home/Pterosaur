// 资料库（本地优先，仿 Web 端 `library`）：我喜欢 / 最近播放 / 收藏的歌单·磁带·艺人·专辑 / 本地歌单。
// 持久化到 `~/Library/Application Support/Pterosaur/library.json`。
//
// 铁律（ADR-038 / AGENTS.md）：`LibraryData` 是跨端持久契约，**未知字段必须原样回写**——云同步整份覆盖，
// 丢字段再回写会抹掉其它端写入的内容。故这里保留原始 JSON 对象，只读写自己的字段。
import Foundation
import PterosaurCore

struct LocalPlaylist: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var createdAt: Int64
    var tracks: [Track]
}

@MainActor
final class Library: ObservableObject {
    @Published private(set) var favorites: [Track] = []
    @Published private(set) var recent: [Track] = []
    @Published private(set) var playlists: [LocalPlaylist] = []
    @Published private(set) var savedPlaylists: [Playlist] = []
    @Published private(set) var savedArtists: [Artist] = []
    @Published private(set) var savedAlbums: [Album] = []

    /// 最近播放上限（与 Web 端一致：去重、最多 100 条）。
    static let recentLimit = 100

    private var store: [String: Any] = [:]
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pterosaur", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("library.json")
        load()
    }

    // MARK: - 写入

    func isFavorite(_ t: Track) -> Bool {
        favorites.contains { keyOf(source: $0.source, id: $0.id) == keyOf(source: t.source, id: t.id) }
    }

    func toggleFavorite(_ t: Track) {
        if isFavorite(t) {
            favorites.removeAll { keyOf(source: $0.source, id: $0.id) == keyOf(source: t.source, id: t.id) }
        } else {
            favorites.insert(t, at: 0)
        }
        save()
    }

    /// 记录一次播放：去重后置顶。
    func markPlayed(_ t: Track) {
        let k = keyOf(source: t.source, id: t.id)
        recent.removeAll { keyOf(source: $0.source, id: $0.id) == k }
        recent.insert(t, at: 0)
        if recent.count > Self.recentLimit { recent = Array(recent.prefix(Self.recentLimit)) }
        save()
    }

    func toggleSaved(_ p: Playlist) {
        let k = keyOf(source: p.source, id: p.id)
        if savedPlaylists.contains(where: { keyOf(source: $0.source, id: $0.id) == k }) {
            savedPlaylists.removeAll { keyOf(source: $0.source, id: $0.id) == k }
        } else {
            savedPlaylists.insert(p, at: 0)
        }
        save()
    }

    func isSaved(_ p: Playlist) -> Bool {
        let k = keyOf(source: p.source, id: p.id)
        return savedPlaylists.contains { keyOf(source: $0.source, id: $0.id) == k }
    }

    func toggleSaved(_ a: Artist) {
        let k = keyOf(source: a.source, id: a.id)
        if savedArtists.contains(where: { keyOf(source: $0.source, id: $0.id) == k }) {
            savedArtists.removeAll { keyOf(source: $0.source, id: $0.id) == k }
        } else {
            savedArtists.insert(a, at: 0)
        }
        save()
    }

    func toggleSaved(_ a: Album) {
        let k = keyOf(source: a.source, id: a.id)
        if savedAlbums.contains(where: { keyOf(source: $0.source, id: $0.id) == k }) {
            savedAlbums.removeAll { keyOf(source: $0.source, id: $0.id) == k }
        } else {
            savedAlbums.insert(a, at: 0)
        }
        save()
    }

    @discardableResult
    func createPlaylist(name: String) -> LocalPlaylist {
        let id = "pl-\(UUID().uuidString.lowercased())"
        let p = LocalPlaylist(id: id, name: name, createdAt: Int64(Date().timeIntervalSince1970 * 1000), tracks: [])
        playlists.insert(p, at: 0)
        save()
        return p
    }

    func add(_ t: Track, toPlaylist id: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        let k = keyOf(source: t.source, id: t.id)
        guard !playlists[i].tracks.contains(where: { keyOf(source: $0.source, id: $0.id) == k }) else { return }
        playlists[i].tracks.append(t)
        save()
    }

    func remove(_ t: Track, fromPlaylist id: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        let k = keyOf(source: t.source, id: t.id)
        playlists[i].tracks.removeAll { keyOf(source: $0.source, id: $0.id) == k }
        save()
    }

    func deletePlaylist(_ id: String) {
        playlists.removeAll { $0.id == id }
        save()
    }

    // MARK: - 持久化（未知字段原样回写）

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        store = o
        favorites = decode(o["favorites"], as: [Track].self) ?? []
        recent = decode(o["recent"], as: [Track].self) ?? []
        playlists = decode(o["playlists"], as: [LocalPlaylist].self) ?? []
        savedPlaylists = decode(o["savedPlaylists"], as: [Playlist].self) ?? []
        savedArtists = decode(o["savedArtists"], as: [Artist].self) ?? []
        savedAlbums = decode(o["savedAlbums"], as: [Album].self) ?? []
    }

    private func save() {
        store["favorites"] = encode(favorites)
        store["recent"] = encode(recent)
        store["playlists"] = encode(playlists)
        store["savedPlaylists"] = encode(savedPlaylists)
        store["savedArtists"] = encode(savedArtists)
        store["savedAlbums"] = encode(savedAlbums)
        guard let data = try? JSONSerialization.data(withJSONObject: store, options: [.sortedKeys]) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func decode<T: Decodable>(_ v: Any?, as: T.Type) -> T? {
        guard let v, let d = try? JSONSerialization.data(withJSONObject: v) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    private func encode<T: Encodable>(_ v: T) -> Any {
        guard let d = try? JSONEncoder().encode(v),
              let o = try? JSONSerialization.jsonObject(with: d) else { return [Any]() }
        return o
    }
}
