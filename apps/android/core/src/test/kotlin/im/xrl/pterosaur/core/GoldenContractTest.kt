// 契约对拍：黄金样例（packages/contract/golden/normalize.json）与其余向量
// （normalize / entity / url / lyric）。比对方式：把模型序列化成 JSON，与期望深比较。
package im.xrl.pterosaur.core

import im.xrl.pterosaur.core.bilibili.decodeTitle
import im.xrl.pterosaur.core.bilibili.normalizeBilibiliTrack
import im.xrl.pterosaur.core.bilibili.parseDuration
import im.xrl.pterosaur.core.crypto.canonicalBiliImage
import im.xrl.pterosaur.core.crypto.canonicalNeteaseImage
import im.xrl.pterosaur.core.crypto.coverAt
import im.xrl.pterosaur.core.crypto.joinUrl
import im.xrl.pterosaur.core.crypto.queryValues
import im.xrl.pterosaur.core.crypto.replaceQuery
import im.xrl.pterosaur.core.crypto.splitUrl
import im.xrl.pterosaur.core.model.Lyric
import im.xrl.pterosaur.core.model.LyricLine
import im.xrl.pterosaur.core.model.keyOf
import im.xrl.pterosaur.core.model.parseLrc
import im.xrl.pterosaur.core.model.sourceOf
import im.xrl.pterosaur.core.netease.normalizeAlbum
import im.xrl.pterosaur.core.netease.normalizeArtist
import im.xrl.pterosaur.core.netease.normalizePlaylist
import im.xrl.pterosaur.core.netease.normalizeTrack
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import java.io.File
import kotlin.test.Test

/** 把模型编码成语义等价的 JSON（缺省值在契约里是「不存在」而不是 null / 默认值）。 */
// 契约里 `source` 恒出现（它是实体身份的一部分），其余可选字段缺省时**不出现**而不是 null。
// 故 encodeDefaults = true 让 source 落盘，explicitNulls = false 保证 null 不输出。
private val enc = Json { encodeDefaults = true; explicitNulls = false }

private fun modelJson(e: Any?): JsonElement = when (e) {
    null -> JsonNull
    is String -> JsonPrimitive(e)
    is Int -> JsonPrimitive(e)
    is Long -> JsonPrimitive(e)
    is Boolean -> JsonPrimitive(e)
    is Double -> JsonPrimitive(e)
    is im.xrl.pterosaur.core.model.Track -> enc.encodeToJsonElement(im.xrl.pterosaur.core.model.Track.serializer(), e)
    is im.xrl.pterosaur.core.model.Artist -> enc.encodeToJsonElement(im.xrl.pterosaur.core.model.Artist.serializer(), e)
    is im.xrl.pterosaur.core.model.Album -> enc.encodeToJsonElement(im.xrl.pterosaur.core.model.Album.serializer(), e)
    is im.xrl.pterosaur.core.model.Playlist -> enc.encodeToJsonElement(im.xrl.pterosaur.core.model.Playlist.serializer(), e)
    else -> error("modelJson：未知类型 ${e.javaClass.name}")
}

class GoldenContractTest {

    private fun runGolden(fn: String, input: JsonElement, expected: JsonElement): Boolean {
        val obj = input as? JsonObject
        val got: JsonElement = when (fn) {
            "netease.normalizeTrack" -> modelJson(normalizeTrack(require(obj, fn)))
            "netease.normalizeArtist" -> modelJson(normalizeArtist(require(obj, fn)))
            "netease.normalizeAlbum" -> modelJson(normalizeAlbum(require(obj, fn)))
            "netease.normalizePlaylist" -> modelJson(normalizePlaylist(require(obj, fn)))
            "bilibili.normalizeTrack" -> modelJson(normalizeBilibiliTrack(require(obj, fn)))
            "bilibili.decodeTitle" -> JsonPrimitive(decodeTitle((input as? JsonPrimitive)?.content ?: ""))
            "bilibili.parseDuration" -> JsonPrimitive(parseDuration((input as? JsonPrimitive)?.content))
            "bilibili.canonicalImage" -> JsonPrimitive(canonicalBiliImage((input as? JsonPrimitive)?.content))
            else -> error("测试没有 $fn 的入口")
        }
        return got == expected
    }

    private fun require(obj: JsonObject?, fn: String): JsonObject =
        obj ?: error("$fn 的输入必须是对象")

    /** 复算一次并返回 JSON（用于失败明细）。 */
    private fun describe(fn: String, input: JsonElement): JsonElement {
        val obj = input as? JsonObject
        return when (fn) {
            "netease.normalizeTrack" -> modelJson(normalizeTrack(require(obj, fn)))
            "netease.normalizeArtist" -> modelJson(normalizeArtist(require(obj, fn)))
            "netease.normalizeAlbum" -> modelJson(normalizeAlbum(require(obj, fn)))
            "netease.normalizePlaylist" -> modelJson(normalizePlaylist(require(obj, fn)))
            "bilibili.normalizeTrack" -> modelJson(normalizeBilibiliTrack(require(obj, fn)))
            "bilibili.decodeTitle" -> JsonPrimitive(decodeTitle((input as? JsonPrimitive)?.content ?: ""))
            "bilibili.parseDuration" -> JsonPrimitive(parseDuration((input as? JsonPrimitive)?.content))
            "bilibili.canonicalImage" -> JsonPrimitive(canonicalBiliImage((input as? JsonPrimitive)?.content))
            else -> JsonNull
        }
    }

    @Test
    fun golden() {
        val root = Json.parseToJsonElement(File(contractDir, "golden/normalize.json").readText()).jsonObject
        val cases = root.getValue("cases") as JsonArray
        val failures = mutableListOf<String>()
        for (c in cases) {
            val o = c.jsonObject
            val id = (o.getValue("id") as JsonPrimitive).content
            val fn = (o.getValue("fn") as JsonPrimitive).content
            val input = o.getValue("input")
            val expected = o.getValue("expected")
            val ok = runGolden(fn, input, expected)
            if (!ok) {
                val got = describe(fn, input)
                failures += "$id ($fn)\n    expected=$expected\n    actual  =$got"
            }
        }
        if (failures.isNotEmpty()) throw AssertionError("golden：${failures.size}/${cases.size} 条不符\n" + failures.joinToString("\n"))
    }

    /* ============================ 其余向量 ============================ */

    @Test
    fun normalizeVectors() {
        assertVectors("normalize.json", setOf("netease.image.canonical", "netease.image.coverAt", "bilibili.image.canonical")) { v ->
            when (v.kind) {
                "netease.image.canonical" -> JsonPrimitive(canonicalNeteaseImage((v.input as JsonPrimitive).content))
                "netease.image.coverAt" -> {
                    val o = v.input.jsonObject
                    JsonPrimitive(coverAt((o["url"] as JsonPrimitive).content, (o["px"] as JsonPrimitive).content.toInt()))
                }
                "bilibili.image.canonical" -> JsonPrimitive(canonicalBiliImage((v.input as JsonPrimitive).content))
                else -> error("unreachable")
            }
        }
    }

    @Test
    fun entityVectors() {
        assertVectors("entity.json", setOf("entity.keyOf", "entity.sourceOf", "stream.url")) { v ->
            when (v.kind) {
                "entity.keyOf" -> {
                    val o = v.input.jsonObject
                    val src = (o["source"] as? JsonPrimitive)?.content
                    JsonPrimitive(keyOf(sourceOf(src), (o["id"] as JsonPrimitive).content))
                }
                "entity.sourceOf" -> {
                    val o = v.input.jsonObject
                    JsonPrimitive(sourceOf((o["source"] as? JsonPrimitive)?.content))
                }
                "stream.url" -> {
                    val o = v.input.jsonObject
                    val id = (o["id"] as JsonPrimitive).content
                    val q = mutableListOf<String>()
                    (o["level"] as? JsonPrimitive)?.content?.let { q += "level=$it" }
                    (o["token"] as? JsonPrimitive)?.content?.let { q += "t=$it" }
                    JsonPrimitive("/stream/netease/$id" + if (q.isEmpty()) "" else "?" + q.joinToString("&"))
                }
                else -> error("unreachable")
            }
        }
    }

    @Test
    fun urlVectors() {
        assertVectors("url.json", setOf("url.split", "url.join", "url.queryValues", "url.replaceQuery")) { v ->
            when (v.kind) {
                "url.split" -> {
                    val p = splitUrl((v.input as JsonPrimitive).content)
                    if (p == null) JsonNull
                    else buildJsonObject {
                        put("protocol", p.protocol); put("userinfo", p.userinfo)
                        put("hostname", p.hostname); put("port", p.port); put("rest", p.rest)
                    }
                }
                "url.join" -> {
                    val o = v.input.jsonObject
                    JsonPrimitive(
                        joinUrl(
                            im.xrl.pterosaur.core.crypto.UrlParts(
                                (o["protocol"] as JsonPrimitive).content,
                                (o["userinfo"] as JsonPrimitive).content,
                                (o["hostname"] as JsonPrimitive).content,
                                (o["port"] as JsonPrimitive).content,
                                (o["rest"] as JsonPrimitive).content,
                            ),
                        ),
                    )
                }
                "url.queryValues" -> {
                    val o = v.input.jsonObject
                    buildJsonArray { queryValues((o["rest"] as JsonPrimitive).content, (o["key"] as JsonPrimitive).content).forEach { add(JsonPrimitive(it)) } }
                }
                "url.replaceQuery" -> {
                    val o = v.input.jsonObject
                    JsonPrimitive(replaceQuery((o["rest"] as JsonPrimitive).content, (o["query"] as JsonPrimitive).content))
                }
                else -> error("unreachable")
            }
        }
    }

    @Test
    fun lyricVectors() {
        assertVectors("lyric.json", setOf("lyric.parseLrc")) { v ->
            val o = v.input.jsonObject
            val lyric = parseLrc((o["lrc"] as JsonPrimitive).content, (o["translation"] as? JsonPrimitive)?.content)
            buildJsonObject {
                put(
                    "lines",
                    buildJsonArray {
                        lyric.lines.forEach { l ->
                            add(
                                buildJsonObject {
                                    put("time", timeNumber(l.time))
                                    put("text", l.text)
                                    l.translation?.let { put("translation", it) }
                                },
                            )
                        }
                    },
                )
                put("timed", lyric.timed)
            }
        }
    }

    /** 时间数值：整秒以整数写出（与 JS 的 `1` 而非 `1.0` 一致），否则保留小数。 */
    private fun timeNumber(t: Double): JsonElement =
        if (t == Math.floor(t) && !t.isInfinite()) JsonPrimitive(t.toInt()) else JsonPrimitive(t)
}