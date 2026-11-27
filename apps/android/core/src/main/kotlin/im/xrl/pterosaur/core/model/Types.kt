// 跨端共享的数据模型（Kotlin 版，对应 shared/types.ts）。
// 实体一律带 `source`，判等用 `keyOf = "source:id"`。
package im.xrl.pterosaur.core.model

import kotlinx.serialization.Serializable

typealias MusicSource = String

const val ARTIST_SEPARATOR = "、"

fun keyOf(source: MusicSource, id: String): String = "$source:$id"

fun sourceOf(source: MusicSource?): MusicSource = source ?: "netease"

@Serializable
data class Track(
    val source: MusicSource = "netease",
    val id: String,
    val title: String,
    val artist: String,
    val album: String,
    val cover: String,
    val duration: Int = 0,
    val fee: String = "unknown",
    val artistRefs: List<ArtistRef>? = null,
    val albumId: String? = null,
)

@Serializable
data class ArtistRef(val id: String, val name: String)

@Serializable
data class Artist(
    val source: MusicSource = "netease",
    val id: String,
    val name: String,
    val avatar: String,
    val alias: List<String>? = null,
    val albumSize: Int? = null,
    val musicSize: Int? = null,
    val briefDesc: String? = null,
)

@Serializable
data class Album(
    val source: MusicSource = "netease",
    val id: String,
    val name: String,
    val cover: String,
    val artist: String,
    val artistId: String? = null,
    val artistRefs: List<ArtistRef>? = null,
    val year: Int? = null,
    val genre: String? = null,
    val type: String? = null,
    val trackCount: Int? = null,
)

@Serializable
data class Playlist(
    val source: MusicSource = "netease",
    val id: String,
    val name: String,
    val cover: String,
    val description: String? = null,
    val trackCount: Int? = null,
    val playCount: Long? = null,
    val creator: String? = null,
)

@Serializable
data class LyricLine(val time: Double, val text: String, val translation: String? = null)

@Serializable
data class Lyric(val lines: List<LyricLine> = emptyList(), val timed: Boolean = false)
