// 真实上游体检（手动运行，不进 CI）：`gradle :core:liveCheck`
//
// 用 :core 自实现的网易云接口打真实上游，逐项检查原始响应。只读、匿名、不带凭证——
// 验证的是「签名与请求形态被上游接受」，与账号权限无关。对应 TS 的 `check:live`。
package im.xrl.pterosaur.core.cli

import im.xrl.pterosaur.core.netease.*

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

private data class Step(val name: String, val run: () -> NcmResult, val peek: (JsonObject) -> String)

private fun JsonObject?.str(k: String): String? = ((this?.get(k)) as? kotlinx.serialization.json.JsonPrimitive)?.content
private fun JsonObject?.obj(k: String): JsonObject? = this?.get(k) as? JsonObject
private fun JsonObject?.arrSize(k: String): Int = (this?.get(k) as? kotlinx.serialization.json.JsonArray)?.size ?: 0

fun main() {
    val steps = listOf(
        Step("搜索歌曲（cloudsearch）", { cloudsearch(keywords = "稻香", limit = 3) }) { "songs=${it.obj("result").arrSize("songs")} code=${it.str("code")}" },
        Step("推荐歌单（personalized）", { personalized(limit = 3) }) { "result=${it.arrSize("result")}" },
        Step("全部榜单（toplist）", { toplist() }) { "list=${it.arrSize("list")}" },
        Step("热歌榜详情（playlist_detail）", { playlistDetail(id = "3778678", s = 8) }) { "tracks=${it.obj("playlist").obj("tracks")?.size ?: 0}" },
        Step("最新专辑（album_newest）", { albumNewest() }) { "albums=${it.arrSize("albums")}" },
        Step("歌手详情（artists）", { artists(id = "6452") }) { "name=${it.obj("artist").str("name")} hot=${it.arrSize("hotSongs")}" },
        Step("专辑详情（album）", { album(id = "32311") }) { "name=${it.obj("album").str("name")}" },
        Step("歌词（lyric_new）", { lyricNew(id = "185809") }) { "lrc=${it.obj("lrc").str("lyric")?.take(12)}" },
        Step("播放地址（song_url_v1，匿名）", { songUrlV1(id = "185809", level = "exhigh") }) {
            val d = (it["data"] as? kotlinx.serialization.json.JsonArray)?.firstOrNull() as? JsonObject
            "url=${if (d?.str("url") != null) "yes" else "no"} br=${d?.str("br")} code=${it.str("code")}"
        },
    )
    var failed = 0
    for (s in steps) {
        val t0 = System.currentTimeMillis()
        try {
            val res = s.run()
            val obj = res.body as? JsonObject ?: JsonObject(emptyMap())
            val ms = System.currentTimeMillis() - t0
            val code = obj.str("code")?.toIntOrNull()
            val ok = code == null || code == 200
            if (!ok) failed++
            println("${if (ok) "✓" else "✗"} ${s.name}  ${ms}ms  ${s.peek(obj)}")
        } catch (e: Exception) {
            failed++
            println("✗ ${s.name}  ${System.currentTimeMillis() - t0}ms  ${e.message}")
        }
    }
    println(if (failed == 0) "\n全部通过" else "\n$failed 项失败")
    if (failed != 0) kotlin.system.exitProcess(1)
}

private fun JsonElement?.size(): Int = (this as? kotlinx.serialization.json.JsonArray)?.size ?: 0