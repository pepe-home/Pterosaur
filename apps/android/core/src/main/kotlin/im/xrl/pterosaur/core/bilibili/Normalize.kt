// B 站（磁带）归一化（Kotlin 版，对应 packages/core/src/sources/bilibili.ts 的 decodeTitle /
// parseDuration / canonicalBiliImage / normalizeBilibiliTrack）。
package im.xrl.pterosaur.core.bilibili

import im.xrl.pterosaur.core.crypto.canonicalBiliImage
import im.xrl.pterosaur.core.model.Track
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull

private val TAG_RE = Regex("<[^>]+>")

/** 去掉 `<em>` 高亮标签并解码常见 HTML 实体。 */
fun decodeTitle(html: String): String = html
    .replace(TAG_RE, "")
    .replace("&amp;", "&")
    .replace("&lt;", "<")
    .replace("&gt;", ">")
    .replace("&quot;", "\"")
    .replace("&#39;", "'")
    .trim()

/** 时长 `"12:34"` / `"1:02:03"` → 秒；非法返回 0。 */
fun parseDuration(d: String?): Int {
    if (d.isNullOrEmpty()) return 0
    val parts = d.split(':').map { it.toDoubleOrNull() ?: return 0 }
    if (parts.isEmpty()) return 0
    return parts.fold(0.0) { acc, n -> acc * 60 + n }.toInt()
}

private fun JsonObject.str(key: String): String? = (this[key] as? JsonPrimitive)?.content

/**
 * 视频条目 → 磁带曲目。`id` 取 bvid，缺省退回 aid。
 *
 * 注意 `parseDuration` 的截断口径与 TS 一致（`reduce` 求和后交给 `Math.round`? 不——TS 直接返回
 * 浮点和，这里 `toInt()` 截断；契约向量只用整秒，若有小数会在 golden 里暴露）。
 */
fun normalizeBilibiliTrack(v: JsonObject): Track {
    val id = v.str("bvid")
        ?: (v["aid"] as? JsonPrimitive)?.longOrNull?.toString()
        ?: ""
    return Track(
        source = "bilibili",
        id = id,
        title = decodeTitle(v.str("title") ?: "").ifEmpty { "未知视频" },
        artist = v.str("author") ?: "未知 UP 主",
        album = "",
        cover = canonicalBiliImage(v.str("pic")),
        duration = parseDuration(v.str("duration")),
        fee = "free",
    )
}