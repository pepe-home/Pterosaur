// 网易云接口客户端（Kotlin 版，对应 packages/core/src/sources/neteaseApi.ts）。
//
// 与 TS 参考实现逐项一致：请求参数、加密方式（缺省 eapi / 显式 weapi）、域名、UA、
// Cookie 构造（库 `processCookieObject` 的口径——缺 `_ntes_nnid` / `NMTID` 时上游对部分接口
// 回空体、取流回 -460）。
//
// 网络走 JDK 自带的 `java.net.http.HttpClient`（Android API 26+ 与 JVM 都有），不引入 OkHttp。
// 与 TS 的唯一有意差异：接口非 200 业务码不抛异常，一律返回，由调用处按 `code` 判定。
package im.xrl.pterosaur.core.netease

import im.xrl.pterosaur.core.crypto.encodeForm
import im.xrl.pterosaur.core.crypto.md5
import im.xrl.pterosaur.core.crypto.base64OfUtf8
import im.xrl.pterosaur.core.crypto.hexOf
import im.xrl.pterosaur.core.crypto.utf8
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.net.URI
import java.net.URLEncoder
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.Duration
import java.time.Instant

/** 接口域名（同 TS）：缺省 eapi 打 apiDomain，weapi 打 domain。 */
const val DOMAIN = "https://music.163.com"
const val API_DOMAIN = "https://interface.music.163.com"

private const val WEAPI_UA =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0"
private const val EAPI_UA = "NeteaseMusic 9.0.90/5038 (iPhone; iOS 16.2; zh_CN)"

private const val ENCRYPT_RESPONSE = false

/** 接口返回：`body` 为解析后的上游 JSON，`cookie` 为原始 Set-Cookie 串。 */
data class NcmResult(val body: JsonElement, val cookie: List<String>)

/** 加密方式。 */
enum class Crypto { WEAPI, EAPI }

private val json = Json { ignoreUnknownKeys = true }

/** 随机源（测试可替换）。 */
var nextRandom: () -> Double = { SecureRandom().nextDouble() }

/** 匿名 token（`MUSIC_A`）提供者（宿主启动后注入；取不到返回空串）。 */
var anonymousTokenProvider: () -> String = { "" }

/** 一次 HTTP 响应（只保留本层要用的部分：状态、正文、Set-Cookie）。 */
data class HttpResponseText(val status: Int, val body: String, val setCookies: List<String>)

/** 可注入的 HTTP 发送器：收到 URL、请求头与表单体，返回 {@link HttpResponseText}（测试用假实现）。 */
fun interface HttpSender {
    fun send(url: String, headers: Map<String, String>, body: String): HttpResponseText
}

private val defaultSender = HttpSender { url, headers, body ->
    val req = HttpRequest.newBuilder(URI.create(url))
        .timeout(Duration.ofSeconds(15))
        .apply { headers.forEach { (k, v) -> header(k, v) } }
        .POST(HttpRequest.BodyPublishers.ofString(body))
        .build()
    val res = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(15)).followRedirects(HttpClient.Redirect.NORMAL).build()
        .send(req, HttpResponse.BodyHandlers.ofString())
    HttpResponseText(res.statusCode(), res.body(), res.headers().allValues("Set-Cookie"))
}

var sender: HttpSender = defaultSender

private fun now(): Long = Instant.now().toEpochMilli()

/** 小写十六进制随机串（对应 TS 的 randomHex：每字节两位）。 */
internal fun randomHex(bytes: Int): String {
    val hex = "0123456789abcdef"
    return buildString { repeat(bytes * 2) { append(hex[(nextRandom() * 16).toInt().coerceIn(0, 15)]) } }
}

/** 模块级 `WNMCID`（与 TS 一致：6 个小写字母 + 时间戳）。 */
private val WNMCID: String = run {
    val letters = "abcdefghijklmnopqrstuvwxyz"
    val s = buildString { repeat(6) { append(letters[(nextRandom() * 26).toInt().coerceIn(0, 25)]) } }
    "$s.${now()}.01.0"
}

private fun cookieToObject(cookie: String): Map<String, String> =
    cookie.split(';').mapNotNull { part ->
        val eq = part.indexOf('=')
        if (eq <= 0) return@mapNotNull null
        val value = part.substring(eq + 1)
        if (value.contains('=')) return@mapNotNull null
        part.substring(0, eq).trim() to value.trim()
    }.toMap()

/** 一次请求的 cookie 构造结果。 */
internal data class CookieContext(
    val header: Map<String, String>,
    val cookieObject: Map<String, String>,
    val cookieHeader: String,
)

/** 构造请求 cookie 与请求头（对齐库的 `processCookieObject` + `createHeaderCookie`）。 */
internal fun requestCookie(callerCookie: String?): CookieContext {
    val cookies = if (callerCookie.isNullOrEmpty()) emptyMap() else cookieToObject(callerCookie)
    val hasUser = cookies["MUSIC_U"].isNullOrEmpty().not()
    val header = linkedMapOf(
        "osver" to (cookies["osver"] ?: "Microsoft-Windows-10-Professional-build-19045-64bit"),
        "deviceId" to (cookies["deviceId"] ?: "undefined"),
        "os" to (cookies["os"] ?: "pc"),
        "appver" to (cookies["appver"] ?: "3.1.17.204416"),
        "versioncode" to (cookies["versioncode"] ?: "140"),
        "mobilename" to (cookies["mobilename"] ?: ""),
        "buildver" to (cookies["buildver"] ?: now().toString().take(10)),
        "resolution" to (cookies["resolution"] ?: "1920x1080"),
        "__csrf" to (cookies["__csrf"] ?: ""),
        "channel" to (cookies["channel"] ?: "netease"),
        "requestId" to "${now()}_${(nextRandom() * 1000).toInt().toString().padStart(4, '0')}",
    )
    if (hasUser) header["MUSIC_U"] = cookies["MUSIC_U"]!!
    if (!cookies["MUSIC_A"].isNullOrEmpty()) header["MUSIC_A"] = cookies["MUSIC_A"]!!
    else if (!hasUser) header["MUSIC_A"] = anonymousTokenProvider()
    if (header["MUSIC_A"].isNullOrEmpty()) header.remove("MUSIC_A")

    val nuid = cookies["_ntes_nuid"] ?: randomHex(32)
    val cookieObject = linkedMapOf<String, String>()
    cookieObject.putAll(cookies)
    cookieObject["__remember_me"] = "true"
    cookieObject["ntes_kaola_ad"] = "1"
    cookieObject["_ntes_nuid"] = nuid
    cookieObject["_ntes_nnid"] = cookies["_ntes_nnid"] ?: "$nuid,${now()}"
    cookieObject["WNMCID"] = cookies["WNMCID"] ?: WNMCID
    cookieObject["WEVNSM"] = cookies["WEVNSM"] ?: "1.0.0"
    cookieObject["osver"] = header["osver"]!!
    cookieObject["deviceId"] = header["deviceId"]!!
    cookieObject["os"] = header["os"]!!
    cookieObject["channel"] = header["channel"]!!
    cookieObject["appver"] = header["appver"]!!
    cookieObject.remove("MUSIC_U")
    cookieObject.remove("MUSIC_A")
    // NMTID：每次请求换一个新的 32 位十六进制
    cookieObject["NMTID"] = randomHex(16)
    if (hasUser) cookieObject["MUSIC_U"] = cookies["MUSIC_U"]!!
    if (!cookies["MUSIC_A"].isNullOrEmpty()) cookieObject["MUSIC_A"] = cookies["MUSIC_A"]!!
    else if (!hasUser) cookieObject["MUSIC_A"] = anonymousTokenProvider()
    if (!cookieObject.containsKey("MUSIC_A")) cookieObject["MUSIC_A"] = anonymousTokenProvider()

    return CookieContext(header, cookieObject, encodeCookieHeader(cookieObject))
}

/** 把键值对象编码为 Cookie 头（键与值都按 `encodeURIComponent` 编码，同库）。 */
fun encodeCookieHeader(obj: Map<String, String>): String =
    obj.entries.joinToString("; ") { (k, v) -> "${uriComponent(k)}=${uriComponent(v)}" }

/** 与 JS `encodeURIComponent` 同口径（JVM 的 `URLEncoder` 会把空格编成 `+`、并把 `*` 原样保留）。 */
private fun uriComponent(s: String): String =
    URLEncoder.encode(s, Charsets.UTF_8).replace("+", "%20").replace("%2A", "*").replace("%21", "!")
        .replace("%27", "'").replace("%28", "(").replace("%29", ")").replace("%7E", "~")

/**
 * 发起一次加密请求并解析响应。
 *
 * `path` 是上游的接口路径（含前导 `/api/...`）：weapi 去掉 `/api` 前缀拼到 `/weapi/`，
 * eapi 拼到 `/eapi/`。eapi 的签名里用的是**完整 path**。
 */
internal fun request(
    path: String,
    data: JsonObject,
    crypto: Crypto,
    cookie: String?,
): NcmResult {
    val ctx = requestCookie(cookie)
    val payload = buildJsonObject {
        data.entries.forEach { (k, v) -> put(k, v) }
        put("e_r", ENCRYPT_RESPONSE)
    }
    val url: String
    val form: String
    val userAgent: String
    when (crypto) {
        Crypto.WEAPI -> {
            val withCsrf = buildJsonObject {
                payload.entries.forEach { (k, v) -> put(k, v) }
                put("csrf_token", ctx.header["__csrf"] ?: "")
            }
            url = "$DOMAIN/weapi/${path.removePrefix("/api/")}"
            val enc = weapiEncrypt(withCsrf.toString(), nextRandom)
            form = encodeForm(listOf("params" to enc.params, "encSecKey" to enc.encSecKey))
            userAgent = WEAPI_UA
        }
        Crypto.EAPI -> {
            val withHeader = buildJsonObject {
                payload.entries.forEach { (k, v) -> put(k, v) }
                put("header", buildJsonObject { ctx.header.forEach { (k, v) -> put(k, v) } })
            }
            url = "$API_DOMAIN/eapi/${path.removePrefix("/api/")}"
            form = encodeForm(listOf("params" to eapiSign(path, withHeader.toString())))
            userAgent = EAPI_UA
        }
    }
    val reqHeaders = mapOf(
        "Content-Type" to "application/x-www-form-urlencoded",
        "User-Agent" to userAgent,
        "Referer" to DOMAIN,
        "Cookie" to ctx.cookieHeader,
    )
    val res = sender.send(url, reqHeaders, form)
    val text = res.body
    val body: JsonElement = runCatching { json.parseToJsonElement(text) }.getOrNull()
        ?: if (crypto == Crypto.EAPI) eapiDecrypt(text.trim())?.let { runCatching { json.parseToJsonElement(it) }.getOrNull() } ?: buildJsonObject {}
        else JsonObject(emptyMap())
    return NcmResult(body, res.setCookies)
}

/* ============================ 接口 ============================ */

private fun obj(vararg pairs: Pair<String, JsonElement>): JsonObject = buildJsonObject { pairs.forEach { (k, v) -> put(k, v) } }
private fun str(s: String): JsonPrimitive = JsonPrimitive(s)
private fun num(n: Number): JsonPrimitive = JsonPrimitive(n)
private fun bool(b: Boolean): JsonPrimitive = JsonPrimitive(b)

/** 搜索（`/api/cloudsearch/pc`，缺省 eapi）。`type`：1 单曲、10 专辑、100 歌手、1000 歌单。 */
fun cloudsearch(keywords: String, type: Int = 1, limit: Int = 30, offset: Int = 0, cookie: String? = null): NcmResult =
    request(
        "/api/cloudsearch/pc",
        obj("s" to str(keywords), "type" to num(type), "limit" to num(limit), "offset" to num(offset), "total" to bool(true)),
        Crypto.EAPI,
        cookie,
    )

/** 推荐歌单（weapi）。 */
fun personalized(limit: Int = 30, cookie: String? = null): NcmResult =
    request("/api/personalized/playlist", obj("limit" to num(limit), "total" to bool(true), "n" to num(1000)), Crypto.WEAPI, cookie)

/** 全部榜单（eapi）。 */
fun toplist(cookie: String? = null): NcmResult = request("/api/toplist", JsonObject(emptyMap()), Crypto.EAPI, cookie)

/** 歌单详情（eapi）。 */
fun playlistDetail(id: String, s: Int = 8, cookie: String? = null): NcmResult =
    request("/api/v6/playlist/detail", obj("id" to str(id), "n" to num(100000), "s" to num(s)), Crypto.EAPI, cookie)

/** 分类歌单（weapi）。 */
fun topPlaylist(cat: String = "全部", limit: Int = 50, offset: Int = 0, cookie: String? = null): NcmResult =
    request(
        "/api/playlist/list",
        obj("cat" to str(cat), "order" to str("hot"), "limit" to num(limit), "offset" to num(offset), "total" to bool(true)),
        Crypto.WEAPI,
        cookie,
    )

/** 推荐新歌（weapi）。 */
fun personalizedNewsong(limit: Int = 10, cookie: String? = null): NcmResult =
    request("/api/personalized/newsong", obj("type" to str("recommend"), "limit" to num(limit), "areaId" to num(0)), Crypto.WEAPI, cookie)

/** 歌单分类目录（eapi）。 */
fun playlistCatlist(cookie: String? = null): NcmResult = request("/api/playlist/catalogue", JsonObject(emptyMap()), Crypto.EAPI, cookie)

/** 最新专辑（weapi）。 */
fun albumNewest(cookie: String? = null): NcmResult = request("/api/discovery/newAlbum", JsonObject(emptyMap()), Crypto.WEAPI, cookie)

/** 歌手专辑分页（weapi）。 */
fun artistAlbum(id: String, limit: Int = 30, offset: Int = 0, cookie: String? = null): NcmResult =
    request("/api/artist/albums/$id", obj("limit" to num(limit), "offset" to num(offset), "total" to bool(true)), Crypto.WEAPI, cookie)

/** 歌手详情（含热门 50 首，weapi）。 */
fun artists(id: String, cookie: String? = null): NcmResult = request("/api/v1/artist/$id", JsonObject(emptyMap()), Crypto.WEAPI, cookie)

/** 专辑详情（weapi）。 */
fun album(id: String, cookie: String? = null): NcmResult = request("/api/v1/album/$id", JsonObject(emptyMap()), Crypto.WEAPI, cookie)

/** 播放地址 v1（eapi）。 */
fun songUrlV1(id: String, level: String, cookie: String? = null): NcmResult {
    val data = mutableMapOf<String, JsonElement>(
        "ids" to str("[$id]"),
        "level" to str(level),
        "encodeType" to str("flac"),
    )
    if (level == "sky") data["immerseType"] = str("c51")
    return request("/api/song/enhance/player/url/v1", JsonObject(data), Crypto.EAPI, cookie)
}

/** 曲目详情（weapi）。 */
fun songDetail(ids: List<String>, cookie: String? = null): NcmResult =
    request("/api/v3/song/detail", obj("c" to str(ids.joinToString(",") { "{\"id\":$it}" }.let { "[$it]" })), Crypto.WEAPI, cookie)

/** 歌词（eapi）。 */
fun lyricNew(id: String, cookie: String? = null): NcmResult =
    request(
        "/api/song/lyric/v1",
        obj(
            "id" to str(id), "cp" to bool(false), "tv" to num(0), "lv" to num(0), "rv" to num(0),
            "kv" to num(0), "yv" to num(0), "ytv" to num(0), "yrv" to num(0),
        ),
        Crypto.EAPI,
        cookie,
    )

/** 登录账号信息（weapi）；与 TS 一致把 `body` 包成 `{ data: body }`。 */
fun loginStatus(cookie: String? = null): NcmResult {
    val r = request("/api/w/nuser/account/get", JsonObject(emptyMap()), Crypto.WEAPI, cookie)
    return NcmResult(obj("data" to r.body), r.cookie)
}

/** 用户歌单（weapi）。 */
fun userPlaylist(uid: String, cookie: String? = null): NcmResult =
    request("/api/user/playlist", obj("uid" to str(uid), "limit" to num(30), "offset" to num(0), "includeVideo" to bool(true)), Crypto.WEAPI, cookie)

/** 匿名注册（weapi）：取 `MUSIC_A`。 */
fun registerAnonymous(): String {
    val deviceId = buildString { val h = "0123456789ABCDEF"; repeat(52) { append(h[(nextRandom() * 16).toInt().coerceIn(0, 15)]) } }
    val username = base64OfUtf8("$deviceId ${anonymousHash(deviceId)}")
    val r = request("/api/register/anonimous", obj("username" to str(username)), Crypto.WEAPI, null)
    val cookies = r.cookie
    for (c in cookies) {
        val m = Regex("""(?:^|;\s*)MUSIC_A=([^;]+)""").find(c) ?: continue
        return m.groupValues[1]
    }
    return ""
}

private const val ANON_XOR_KEY = "3go8&$8*3*3h0k(2)2"

private fun anonymousHash(deviceId: String): String {
    val xored = buildString {
        for (i in deviceId.indices) {
            append((deviceId[i].code xor ANON_XOR_KEY[i % ANON_XOR_KEY.length].code).toChar())
        }
    }
    return base64OfUtf8(hexOf(md5(xored.utf8())))
}