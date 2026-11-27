// 编解码：UTF-8 / base64 / hex / 表单编码（Kotlin 版，契约见 packages/contract/vectors/encoding.json）。
//
// 与 TS 参考实现（packages/shared/src/url.ts + services/crypto.ts）语义一致：
// 表单编码遵循 WHATWG（空格 → `+`，字符集 `A-Za-z0-9*-._` 之外一律百分号编码）。
package im.xrl.pterosaur.core.crypto

private val HEX = "0123456789abcdef".toCharArray()

/** 字节 → 小写十六进制。 */
fun ByteArray.toHex(): String {
    val out = CharArray(size * 2)
    for (i in indices) {
        val v = this[i].toInt() and 0xff
        out[i * 2] = HEX[v ushr 4]
        out[i * 2 + 1] = HEX[v and 0x0f]
    }
    return String(out)
}

/** 十六进制 → 字节（大小写均可，忽略非十六进制字符）。 */
fun String.fromHex(): ByteArray {
    val clean = filter { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }
    require(clean.length % 2 == 0) { "fromHex: 十六进制长度必须是偶数" }
    return ByteArray(clean.length / 2) { i ->
        clean.substring(i * 2, i * 2 + 2).toInt(16).toByte()
    }
}

/** 字符串 → UTF-8 字节。 */
fun String.utf8(): ByteArray = toByteArray(Charsets.UTF_8)

/** UTF-8 字节 → 字符串（非法序列替换为 U+FFFD，与 TextDecoder 缺省一致）。 */
fun ByteArray.decodeUtf8(): String =
    String(this, Charsets.UTF_8)

/** 标准 base64 编码（补 `=`）。 */
fun ByteArray.toBase64(): String = java.util.Base64.getEncoder().encodeToString(this)

/** base64 解码（容忍 URL-safe 字母表与缺失的 `=`）。 */
fun String.fromBase64(): ByteArray = java.util.Base64.getMimeDecoder().decode(this)

/**
 * 表单值编码（`application/x-www-form-urlencoded`，WHATWG）：与
 * `URLSearchParams.toString()` 逐字节一致——空格写 `+`，`*` `.` `-` `_` 与字母数字之外一律
 * 百分号编码（大写十六进制）。
 */
fun formUrlEncode(value: String): String = buildString {
    for (b in value.utf8()) {
        val c = b.toInt() and 0xff
        val ch = c.toChar()
        when {
            ch in 'A'..'Z' || ch in 'a'..'z' || ch in '0'..'9' -> append(ch)
            ch == ' ' -> append('+')
            ch == '*' || ch == '-' || ch == '.' || ch == '_' -> append(ch)
            else -> append('%').append(HEX[c ushr 4].uppercaseChar()).append(HEX[c and 0x0f].uppercaseChar())
        }
    }
}

/** 把键值对序列化为表单串，等价于 `new URLSearchParams(fields).toString()`（保持传入顺序）。 */
fun encodeForm(fields: List<Pair<String, String>>): String =
    fields.joinToString("&") { (k, v) -> "${formUrlEncode(k)}=${formUrlEncode(v)}" }
/** 字符串的 UTF-8 字节的 base64（便捷）。 */
fun base64OfUtf8(s: String): String = s.utf8().toBase64()

/** 字符串的 UTF-8 字节的小写十六进制（便捷）。 */
fun hexOf(bytes: ByteArray): String = bytes.toHex()
