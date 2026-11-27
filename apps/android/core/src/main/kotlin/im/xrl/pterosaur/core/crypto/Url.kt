// URL 拆分 / 接合与查询串处理（Kotlin 版，对应 shared/url.ts）。
// 不用 java.net.URI：它对非绝对地址会抛异常，且小写化 / 百分号编码的口径与 WHATWG 不同。
package im.xrl.pterosaur.core.crypto

/** URL 拆分结果。`rest` 从路径开始（含查询串与片段）。 */
data class UrlParts(
    val protocol: String,
    val userinfo: String,
    val hostname: String,
    val port: String,
    val rest: String,
)

private val SPLIT_RE = Regex("""^([a-z][a-z0-9+.-]*)://([^/?#]*)([^\s]*)$""", RegexOption.IGNORE_CASE)

/** 按 `scheme://[userinfo@]hostname[:port]rest` 拆分；解析不了返回 `null`。 */
fun splitUrl(url: String): UrlParts? {
    val text = url.trim()
    val m = SPLIT_RE.matchEntire(text) ?: return null
    val authority = m.groupValues[2]
    if (authority.isEmpty()) return null
    val at = authority.lastIndexOf('@')
    val userinfo = if (at < 0) "" else authority.substring(0, at + 1)
    val host = if (at < 0) authority else authority.substring(at + 1)
    val hasPort = host.lastIndexOf(':') > host.lastIndexOf(']')
    val hostname = (if (hasPort) host.substring(0, host.lastIndexOf(':')) else host).lowercase()
    val port = if (hasPort) host.substring(host.lastIndexOf(':')) else ""
    val raw = m.groupValues[3]
    val rest = if (raw.isEmpty() || raw.startsWith("/")) raw else "/$raw"
    return UrlParts(
        protocol = m.groupValues[1].lowercase() + ":",
        userinfo = userinfo,
        hostname = hostname,
        port = port,
        rest = if (rest.isEmpty()) "/" else rest,
    )
}

/** 按原样拼回 URL（scheme / 主机 / 路径段可替换）。 */
fun joinUrl(
    parts: UrlParts,
    protocol: String = parts.protocol,
    hostname: String = parts.hostname,
    rest: String = parts.rest,
): String = "${protocol}//${parts.userinfo}${hostname}${parts.port}${rest}"

/* ============================ 查询串 ============================ */

private fun queryString(rest: String): String {
    val i = rest.indexOf('?')
    if (i < 0) return ""
    val h = rest.indexOf('#', i)
    return if (h < 0) rest.substring(i + 1) else rest.substring(i + 1, h)
}

private fun withoutQuery(rest: String): String {
    val i = rest.indexOf('?')
    if (i < 0) return rest
    val h = rest.indexOf('#', i)
    return if (h < 0) rest.substring(0, i) else rest.substring(0, i) + rest.substring(h)
}

/** 把查询串整体换成 `query`（空串即去掉），路径与片段不动。 */
fun replaceQuery(rest: String, query: String): String {
    val base = withoutQuery(rest)
    if (query.isEmpty()) return base
    val h = base.indexOf('#')
    return if (h < 0) "$base?$query" else "${base.substring(0, h)}?$query${base.substring(h)}"
}

/** 查询串里某个键的全部值（表单口径解码），按出现顺序。 */
fun queryValues(rest: String, key: String): List<String> {
    val out = mutableListOf<String>()
    for (pair in queryString(rest).split('&')) {
        if (pair.isEmpty()) continue
        val eq = pair.indexOf('=')
        val k = formUrlDecode(if (eq < 0) pair else pair.substring(0, eq))
        if (k != key) continue
        out += formUrlDecode(if (eq < 0) "" else pair.substring(eq + 1))
    }
    return out
}

/** 表单值解码：`+` → 空格，百分号序列按 UTF-8 解码（非法序列原样保留）。 */
fun formUrlDecode(value: String): String =
    value.replace('+', ' ').replace(Regex("(?:%[0-9a-fA-F]{2})+")) { m ->
        val bytes = ByteArray(m.value.length / 3) { i ->
            m.value.substring(i * 3 + 1, i * 3 + 3).toInt(16).toByte()
        }
        bytes.decodeUtf8()
    }