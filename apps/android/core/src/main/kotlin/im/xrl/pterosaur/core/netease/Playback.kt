// 播放地址与歌词的解析（Kotlin 版，对应 packages/core/src/sources/netease.ts 的
// songUrl / audioQuality / getLyric 与 sources/http.ts 的 codecName / makeQuality / toHttps）。
package im.xrl.pterosaur.core.netease

import im.xrl.pterosaur.core.model.Lyric
import im.xrl.pterosaur.core.model.parseLrc
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

/** 统一抽象音质档（与 shared/types.ts 的 `AUDIO_LEVELS` 一致）。 */
enum class AudioLevel(val wire: String) {
    STANDARD("standard"),
    HIGHER("higher"),
    EXHIGH("exhigh"),
    LOSSLESS("lossless"),
    HIRES("hires");

    companion object {
        val DEFAULT = EXHIGH
        fun of(v: String?): AudioLevel = entries.firstOrNull { it.wire == v } ?: DEFAULT
    }
}

/** 上游如实回报的流参数（供沉浸页音质 chip）。 */
data class AudioQuality(val codec: String? = null, val br: Int? = null, val sr: Int? = null)

/** 把地址统一改写为 https（上游常回 `http://`）。 */
fun toHttps(url: String): String = url.replaceFirst(Regex("^http://"), "https://")

/** 由上游回报的类型字段推导编解码名；缺失时回退直链后缀。 */
fun codecName(raw: String?, url: String): String? {
    val s = (raw ?: "").lowercase().replace(Regex("[^a-z0-9]"), "")
    if (s.isNotEmpty()) return s.uppercase()
    val ext = url.substringBefore('?').substringAfterLast('.', "").lowercase()
    return if (Regex("^[a-z0-9]{2,4}$").matches(ext)) ext.uppercase() else null
}

private fun JsonObject?.str(k: String): String? = (this?.get(k) as? JsonPrimitive)?.content
private fun JsonObject?.int(k: String): Int? = (this?.get(k) as? JsonPrimitive)?.longOrNull?.toInt()

private data class Resolved(val url: String?, val quality: AudioQuality?)

private fun resolveAudio(id: String, level: AudioLevel, cookie: String?): Resolved = try {
    val body = songUrlV1(id = id, level = level.wire, cookie = cookie).body as? JsonObject
    val d = (body?.get("data") as? JsonArray)?.firstOrNull() as? JsonObject
    val rawUrl = d.str("url")
    if (rawUrl.isNullOrEmpty()) Resolved(null, null)
    else Resolved(
        toHttps(rawUrl),
        AudioQuality(
            codec = codecName(d.str("type") ?: d.str("encodeType"), rawUrl),
            br = d.int("br")?.takeIf { it > 0 },
            sr = d.int("sr")?.takeIf { it > 0 },
        ),
    )
} catch (e: Exception) {
    Resolved(null, null)
}

/** 解析播放地址；不可播放（版权受限 / 未登录）返回空列表。 */
fun songUrl(id: String, level: AudioLevel = AudioLevel.DEFAULT, cookie: String? = null): List<String> =
    resolveAudio(id, level, cookie).url?.let { listOf(it) } ?: emptyList()

/** 解析该档位**实际**得到的流参数（上游会降级并如实回报）。 */
fun audioQuality(id: String, level: AudioLevel = AudioLevel.DEFAULT, cookie: String? = null): AudioQuality? =
    resolveAudio(id, level, cookie).quality

/** 歌词（含翻译）；失败返回空歌词而不是抛错。 */
fun getLyric(id: String, cookie: String? = null): Lyric = try {
    val body = lyricNew(id = id, cookie = cookie).body as? JsonObject
    val lrc = body?.get("lrc")?.let { it as? JsonObject }?.str("lyric") ?: ""
    val tlyric = body?.get("tlyric")?.let { it as? JsonObject }?.str("lyric")
    parseLrc(lrc, tlyric)
} catch (e: Exception) {
    Lyric()
}

/** 把解析结果转成可直接交给播放器的 https 地址（`streamUrl` 的端上等价物）。 */
fun playableUrl(trackId: String, level: AudioLevel = AudioLevel.DEFAULT, cookie: String? = null): String? =
    songUrl(trackId, level, cookie).firstOrNull()

/** 从 JSON 数组取对象（供 UI 层处理搜索结果）。 */
fun JsonArray.objects(): List<JsonObject> = this.mapNotNull { it as? JsonObject }

/** 从 JSON 对象取键对应的字符串。 */
fun JsonObject?.stringValue(key: String): String? = (this?.get(key) as? JsonPrimitive)?.content