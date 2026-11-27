// 封面 URL 规范化（Kotlin 版，对应 shared/image.ts 与 bilibili.ts 的 canonicalBiliImage）。
package im.xrl.pterosaur.core.crypto

/** 规范化后固定使用的网易云镜像主机（p1–pN 互为镜像）。 */
const val NETEASE_IMAGE_HOST = "p3.music.126.net"

/** B 站图片固定镜像主机（i0–iN 互为镜像）。 */
const val BILI_IMAGE_HOST = "i0.hdslb.com"

const val COVER_SMALL = 300
const val COVER_LARGE = 1200
const val COVER_RIP = 3000

private val NETEASE_HOST_RE = Regex("""^p\d+\.music\.126\.net$""")
private val BILI_HOST_RE = Regex("""^i\d+\.hdslb\.com$""")

/** 规范化网易云图片地址：https、固定镜像主机、查询串只留最后一个 `param`。 */
fun canonicalNeteaseImage(url: String): String {
    if (url.isEmpty()) return url
    val u = splitUrl(url) ?: return url
    if (!NETEASE_HOST_RE.matches(u.hostname)) return url
    val last = queryValues(u.rest, "param").lastOrNull()
    val query = if (last == null) "" else "param=${formUrlEncode(last)}"
    return joinUrl(u, protocol = "https:", hostname = NETEASE_IMAGE_HOST, rest = replaceQuery(u.rest, query))
}

/** 把网易云封面改写为指定边长（`param={px}x{px}`）；非网易云地址原样返回。 */
fun coverAt(url: String?, px: Int): String? {
    if (url.isNullOrEmpty()) return url
    val u = splitUrl(url) ?: return url
    if (!NETEASE_HOST_RE.matches(u.hostname)) return url
    return joinUrl(
        u,
        protocol = "https:",
        hostname = NETEASE_IMAGE_HOST,
        rest = replaceQuery(u.rest, "param=${formUrlEncode("${px}x$px")}"),
    )
}

/** B 站封面/头像：补 `https:`，i0–iN 镜像主机归一；解析不了返回空串。 */
fun canonicalBiliImage(url: String?): String {
    if (url.isNullOrEmpty()) return ""
    val abs = if (url.startsWith("//")) "https:$url" else url
    val u = splitUrl(abs) ?: return ""
    val host = if (BILI_HOST_RE.matches(u.hostname)) BILI_IMAGE_HOST else u.hostname
    return joinUrl(u, protocol = "https:", hostname = host)
}