// 上游原始 JSON → 共享模型（Kotlin 版，对应 packages/core/src/sources/netease.ts 的 normalize*）。
//
// 直接读 JsonObject 而不是 typed 反序列化：上游字段缺失时要落到「缺省」而非类型默认，
// 与 TS 的可选链语义逐项对齐（golden/normalize.json 会逐条校验）。
package im.xrl.pterosaur.core.netease

import im.xrl.pterosaur.core.crypto.COVER_LARGE
import im.xrl.pterosaur.core.crypto.COVER_SMALL
import im.xrl.pterosaur.core.crypto.NETEASE_IMAGE_HOST
import im.xrl.pterosaur.core.crypto.canonicalNeteaseImage
import im.xrl.pterosaur.core.crypto.formUrlEncode
import im.xrl.pterosaur.core.crypto.joinUrl
import im.xrl.pterosaur.core.crypto.replaceQuery
import im.xrl.pterosaur.core.crypto.splitUrl
import im.xrl.pterosaur.core.model.ARTIST_SEPARATOR
import im.xrl.pterosaur.core.model.Album
import im.xrl.pterosaur.core.model.Artist
import im.xrl.pterosaur.core.model.ArtistRef
import im.xrl.pterosaur.core.model.Playlist
import im.xrl.pterosaur.core.model.Track
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull

private val BASE_COVER_SIZE = "${COVER_LARGE}y$COVER_LARGE"

/** 规范化后重设尺寸参数；解析不了返回空串（同 TS 的 coverUrl）。 */
internal fun coverUrl(raw: String?, size: String = BASE_COVER_SIZE): String {
    if (raw.isNullOrEmpty()) return ""
    val u = splitUrl(canonicalNeteaseImage(raw)) ?: return ""
    return joinUrl(u, rest = replaceQuery(u.rest, "param=${formUrlEncode(size)}"))
}

private fun JsonElement?.asObjectOrNull(): JsonObject? = this as? JsonObject

private fun JsonObject?.str(key: String): String? {
    val v = this?.get(key) ?: return null
    return (v as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content
}

private fun JsonObject?.long(key: String): Long? {
    val v = this?.get(key) ?: return null
    return (v as? JsonPrimitive)?.takeIf { it !is JsonNull }?.longOrNull
}

private fun JsonObject?.int(key: String): Int? = long(key)?.toInt()

private fun JsonObject?.arr(key: String): JsonArray? = this?.get(key) as? JsonArray

private fun JsonObject?.obj(key: String): JsonObject? = (this?.get(key)) as? JsonObject

private fun feeOf(fee: Int?): String = when (fee) {
    null -> "unknown"
    0 -> "free"
    8, 4, 1 -> "vip"
    else -> "unknown"
}

private fun albumTypeOf(raw: String?): String? {
    val t = raw?.trim()?.lowercase() ?: return null
    return when (t) {
        "" -> null
        "专辑", "album" -> "album"
        "single", "单曲" -> "single"
        "ep" -> "ep"
        else -> "other"
    }
}

private fun artistRefsOf(list: List<JsonObject>): List<ArtistRef> =
    list.mapNotNull { a ->
        val id = a.long("id") ?: return@mapNotNull null
        val name = a.str("name")?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
        ArtistRef(id.toString(), name)
    }

/** 曲目归一化。 */
fun normalizeTrack(raw: JsonObject): Track {
    val list = (raw.arr("ar") ?: raw.arr("artists") ?: JsonArray(emptyList()))
        .mapNotNull { it.asObjectOrNull() }
    val names = list.mapNotNull { it.str("name")?.takeIf { n -> n.isNotEmpty() } }
    val refs = artistRefsOf(list)
    val album = raw.obj("al") ?: raw.obj("album")
    val coverRaw = album.str("picUrl") ?: album.str("blurPicUrl") ?: ""
    val durationMs = raw.long("dt") ?: raw.long("duration") ?: 0L
    return Track(
        source = "netease",
        id = (raw.str("id") ?: raw.long("id")?.toString() ?: ""),
        title = raw.str("name") ?: "未知曲目",
        artist = names.joinToString(ARTIST_SEPARATOR).ifEmpty { "未知艺术家" },
        album = album.str("name") ?: "",
        cover = coverUrl(coverRaw),
        duration = Math.round(durationMs / 1000.0).toInt(),
        fee = feeOf(raw.int("fee")),
        artistRefs = refs.ifEmpty { null },
        albumId = album.long("id")?.toString(),
    )
}

/** 艺术家归一化。 */
fun normalizeArtist(raw: JsonObject): Artist {
    val alias = raw.arr("alias")?.mapNotNull { (it as? JsonPrimitive)?.content }?.takeIf { it.isNotEmpty() }
    return Artist(
        source = "netease",
        id = raw.str("id") ?: raw.long("id")?.toString() ?: "",
        name = raw.str("name") ?: "未知艺术家",
        avatar = coverUrl(raw.str("picUrl")),
        alias = alias,
        albumSize = raw.int("albumSize"),
        musicSize = raw.int("musicSize"),
        briefDesc = raw.str("briefDesc")?.takeIf { it.isNotEmpty() },
    )
}

/** 专辑归一化。 */
fun normalizeAlbum(raw: JsonObject): Album {
    val list = raw.arr("artists")?.mapNotNull { it.asObjectOrNull() }
        ?: raw.obj("artist")?.let { listOf(it) }
        ?: emptyList()
    val names = list.mapNotNull { it.str("name")?.takeIf { n -> n.isNotEmpty() } }
    val refs = artistRefsOf(list)
    val tags = raw.str("tags")?.trim()
    return Album(
        source = "netease",
        id = raw.str("id") ?: raw.long("id")?.toString() ?: "",
        name = raw.str("name") ?: "未命名专辑",
        cover = coverUrl(raw.str("picUrl")),
        artist = names.joinToString(ARTIST_SEPARATOR).ifEmpty { "未知艺术家" },
        artistId = refs.firstOrNull()?.id,
        artistRefs = refs.ifEmpty { null },
        year = raw.long("publishTime")?.let { epochYear(it) },
        genre = tags?.takeIf { it.isNotEmpty() },
        type = albumTypeOf(raw.str("type")),
        trackCount = raw.int("size") ?: raw.int("trackCount"),
    )
}

/** 歌单归一化。 */
fun normalizePlaylist(raw: JsonObject): Playlist {
    return Playlist(
        source = "netease",
        id = raw.str("id") ?: raw.long("id")?.toString() ?: "",
        name = raw.str("name") ?: "未命名歌单",
        cover = coverUrl(raw.str("coverImgUrl") ?: raw.str("picUrl") ?: ""),
        description = raw.str("description"),
        trackCount = raw.int("trackCount"),
        playCount = raw.long("playCount"),
        creator = raw.obj("creator").str("nickname"),
    )
}

/** 毫秒时间戳的年份（UTC，与 JS `new Date(ms).getFullYear()` 同——服务器时区无关）。 */
internal fun epochYear(ms: Long): Int = java.time.Instant.ofEpochMilli(ms).atZone(java.time.ZoneOffset.UTC).year
