// 请求形态对拍：拦截发送器，核对「发出的请求」的 URL / 头 / 表单与 TS 参考实现一致。
// 不联网；响应为假数据。对应 packages/contract/recordings/netease.ndjson 的 request 部分。
package im.xrl.pterosaur.core.netease

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class NeteaseApiShapeTest {

    private data class Sent(val url: String, val headers: Map<String, String>, val body: String)

    private val sent = mutableListOf<Sent>()
    private val originalSender = sender
    private val originalRandom = nextRandom

    @BeforeTest
    fun setUp() {
        sent.clear()
        nextRandom = { 0.5 }
        sender = HttpSender { url, headers, body ->
            sent += Sent(url, headers, body)
            HttpResponseText(200, """{"code":200}""", emptyList())
       }
    }

    @AfterTest
    fun tearDown() {
        sender = originalSender
        nextRandom = originalRandom
    }

    private fun form(s: Sent): Map<String, String> =
        s.body.split("&").filter { it.isNotEmpty() }.associate {
            val i = it.indexOf('=')
            java.net.URLDecoder.decode(it.substring(0, i), Charsets.UTF_8) to
                java.net.URLDecoder.decode(it.substring(i + 1), Charsets.UTF_8)
        }

    @Test
    fun eapiRequestShape() {
        cloudsearch(keywords = "稻香", limit = 3)
        val s = sent.single()
        assertEquals("https://interface.music.163.com/eapi/cloudsearch/pc", s.url)
        assertEquals("NeteaseMusic 9.0.90/5038 (iPhone; iOS 16.2; zh_CN)", s.headers["User-Agent"])
        assertEquals("https://music.163.com", s.headers["Referer"])
        assertEquals("application/x-www-form-urlencoded", s.headers["Content-Type"])

        val params = form(s).getValue("params")
        assertTrue(params.all { it in "0123456789ABCDEF" }, "eapi params 是大写十六进制：$params")
        val plain = Json.parseToJsonElement(eapiDecrypt(params)!!).jsonObject
        assertEquals("稻香", plain["s"]!!.jsonPrimitive.content)
        assertEquals(3, plain["limit"]!!.jsonPrimitive.content.toInt())
        assertEquals("false", plain["e_r"]!!.jsonPrimitive.content)
        assertTrue(plain.containsKey("header"), "eapi 载荷带 header")
        assertEquals("pc", plain["header"]!!.jsonObject["os"]!!.jsonPrimitive.content)

        val cookie = s.headers.getValue("Cookie")
        for (needle in listOf("_ntes_nnid=", "NMTID=", "__remember_me=true", "MUSIC_A=", "WNMCID=")) {
            assertTrue(needle in cookie, "Cookie 缺 $needle：$cookie")
        }
    }

    @Test
    fun weapiRequestShape() {
        album(id = "32311")
        val s = sent.single()
        assertEquals("https://music.163.com/weapi/v1/album/32311", s.url)
        val f = form(s)
        assertTrue("params" in f && "encSecKey" in f, "weapi 表单含 params + encSecKey")
        assertEquals(256, f.getValue("encSecKey").length, "encSecKey 是 1024 位模长的裸 RSA（128 字节 → 256 个十六进制字符）")
    }

    @Test
    fun cookiePassthrough() {
        album(id = "1", cookie = "MUSIC_U=abc; __csrf=deadbeef")
        val s = sent.single()
        val cookie = s.headers.getValue("Cookie")
        assertTrue("MUSIC_U=abc" in cookie, "登录会话应透传 MUSIC_U：$cookie")
        assertTrue("__csrf=deadbeef" in cookie, "透传 __csrf：$cookie")
    }
}