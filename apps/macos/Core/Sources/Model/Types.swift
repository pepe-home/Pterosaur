// 跨端共享的数据模型（Swift 版，对应 shared/types.ts）。
// 实体一律带 `source`，判等用 `keyOf = "source:id"`。
import Foundation

public typealias MusicSource = String

public let ARTIST_SEPARATOR = "、"

public func keyOf(source: MusicSource, id: String) -> String { "\(source):\(id)" }

public func sourceOf(_ source: MusicSource?) -> MusicSource { source ?? "netease" }

public struct ArtistRef: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Track: Codable, Equatable, Sendable {
    public var source: MusicSource = "netease"
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var cover: String
    public var duration: Int = 0
    public var fee: String = "unknown"
    public var artistRefs: [ArtistRef]?
    public var albumId: String?

    public init(
        source: MusicSource = "netease", id: String, title: String, artist: String,
        album: String, cover: String, duration: Int = 0, fee: String = "unknown",
        artistRefs: [ArtistRef]? = nil, albumId: String? = nil
    ) {
        self.source = source
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.cover = cover
        self.duration = duration
        self.fee = fee
        self.artistRefs = artistRefs
        self.albumId = albumId
    }
}

public struct Artist: Codable, Equatable, Sendable {
    public var source: MusicSource = "netease"
    public var id: String
    public var name: String
    public var avatar: String
    public var alias: [String]?
    public var albumSize: Int?
    public var musicSize: Int?
    public var briefDesc: String?

    public init(
        source: MusicSource = "netease", id: String, name: String, avatar: String,
        alias: [String]? = nil, albumSize: Int? = nil, musicSize: Int? = nil, briefDesc: String? = nil
    ) {
        self.source = source
        self.id = id
        self.name = name
        self.avatar = avatar
        self.alias = alias
        self.albumSize = albumSize
        self.musicSize = musicSize
        self.briefDesc = briefDesc
    }
}

public struct Album: Codable, Equatable, Sendable {
    public var source: MusicSource = "netease"
    public var id: String
    public var name: String
    public var cover: String
    public var artist: String
    public var artistId: String?
    public var artistRefs: [ArtistRef]?
    public var year: Int?
    public var genre: String?
    public var type: String?
    public var trackCount: Int?

    public init(
        source: MusicSource = "netease", id: String, name: String, cover: String, artist: String,
        artistId: String? = nil, artistRefs: [ArtistRef]? = nil, year: Int? = nil,
        genre: String? = nil, type: String? = nil, trackCount: Int? = nil
    ) {
        self.source = source
        self.id = id
        self.name = name
        self.cover = cover
        self.artist = artist
        self.artistId = artistId
        self.artistRefs = artistRefs
        self.year = year
        self.genre = genre
        self.type = type
        self.trackCount = trackCount
    }
}

public struct Playlist: Codable, Equatable, Sendable {
    public var source: MusicSource = "netease"
    public var id: String
    public var name: String
    public var cover: String
    public var description: String?
    public var trackCount: Int?
    public var playCount: Int?
    public var creator: String?

    public init(
        source: MusicSource = "netease", id: String, name: String, cover: String,
        description: String? = nil, trackCount: Int? = nil, playCount: Int? = nil, creator: String? = nil
    ) {
        self.source = source
        self.id = id
        self.name = name
        self.cover = cover
        self.description = description
        self.trackCount = trackCount
        self.playCount = playCount
        self.creator = creator
    }
}

public struct LyricLine: Codable, Equatable, Sendable {
    public var time: Double
    public var text: String
    public var translation: String?
    public init(time: Double, text: String, translation: String? = nil) {
        self.time = time
        self.text = text
        self.translation = translation
    }
}

public struct Lyric: Codable, Equatable, Sendable {
    public var lines: [LyricLine]
    public var timed: Bool
    public init(lines: [LyricLine] = [], timed: Bool = false) {
        self.lines = lines
        self.timed = timed
    }
}