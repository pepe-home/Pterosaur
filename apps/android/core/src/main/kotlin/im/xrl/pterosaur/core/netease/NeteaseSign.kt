// 网易云网页端 / 客户端接口的签名与加密（ADR-065：协议在内核自实现，不依赖第三方库）。
//
// 常量与构造方式与 TS 参考实现（packages/core/src/sources/neteaseSign.ts）逐项一致——
// 它们是与上游协商的一部分，不是实现细节。契约：packages/contract/vectors/netease-sign.json。
package im.xrl.pterosaur.core.netease

import im.xrl.pterosaur.core.crypto.RsaPublicKey
import im.xrl.pterosaur.core.crypto.aesCbcEncrypt
import im.xrl.pterosaur.core.crypto.aesEcbDecrypt
import im.xrl.pterosaur.core.crypto.aesEcbEncrypt
import im.xrl.pterosaur.core.crypto.decodeUtf8
import im.xrl.pterosaur.core.crypto.fromBase64
import im.xrl.pterosaur.core.crypto.fromHex
import im.xrl.pterosaur.core.crypto.md5
import im.xrl.pterosaur.core.crypto.rsaRaw
import im.xrl.pterosaur.core.crypto.toBase64
import im.xrl.pterosaur.core.crypto.toHex
import im.xrl.pterosaur.core.crypto.utf8

/** weapi 的固定预设密钥与 IV（网页端写死）。 */
private const val PRESET_KEY = "0CoJUm6Qyw8W8jud"
private const val IV = "0102030405060708"

/** eapi 的固定密钥（客户端包内常量）。 */
private const val EAPI_KEY = "e82ckenh8dichen8"

/** eapi 报文拼接用的分隔串。 */
private const val EAPI_SEPARATOR = "-36cd479b6b5-"

/** 会话密钥字母表：小写 + 大写字母 + 数字（与 TS 的 BASE62 同序）。 */
private const val BASE62 = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

/** weapi 用的 RSA 公钥（SPKI，base64）。 */
private const val WEAPI_PUBLIC_KEY_B64 =
    "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDgtQn2JZ34ZC28NWYpAUd98iZ37BUrX/aKzmFbt7clFSs6sXqHauqKWqdtLkF2KexO40H1YTX8z2lSgBBOAxLsvaklV8k4cBFK9snQXE9/DDaFt6Rr7iVZMldczhC0JNgTz+SHXT6CBHuX3e9SdB1Ua44oncaTWz7OBGLbCiK45wIDAQAB"

private val WEAPI_PUBLIC_KEY: RsaPublicKey by lazy { RsaPublicKey.fromSpki(WEAPI_PUBLIC_KEY_B64.fromBase64()) }

/** eapi 加密的 `params`（大写十六进制）。 */
fun eapiSign(path: String, payload: String): String {
    val digest = md5("nobody${path}use${payload}md5forencrypt".utf8()).toHex()
    val data = "$path$EAPI_SEPARATOR$payload$EAPI_SEPARATOR$digest"
    return aesEcbEncrypt(EAPI_KEY.utf8(), data.utf8()).toHex().uppercase()
}

/** eapi 响应解密（`params` 是十六进制）：取报文里的 JSON 段；解析失败返回 `null`。 */
fun eapiDecrypt(hex: String): String? = try {
    val plain = aesEcbDecrypt(EAPI_KEY.utf8(), hex.fromHex()).decodeUtf8()
    val start = plain.indexOf(EAPI_SEPARATOR)
    val end = plain.lastIndexOf(EAPI_SEPARATOR)
    if (start < 0 || end <= start) null else plain.substring(start + EAPI_SEPARATOR.length, end)
} catch (e: Exception) {
    null
}

/**
 * 生成会话密钥（库的 `weapi()` 原样做法）：`Math.round(random() * 61)` 取字符。
 * 与 TS 实现一致，随机源由调用方提供。
 */
fun randomSecretKey(random: () -> Double): String = buildString {
    repeat(16) {
        val idx = Math.round(random() * 61).toInt()
        if (idx < BASE62.length) append(BASE62[idx])
    }
}

/** weapi 加密的结果。 */
data class WeapiForm(val params: String, val encSecKey: String)

/**
 * weapi 加密：明文 → AES-CBC（预设密钥）→ AES-CBC（会话密钥）得 `params`；
 * 会话密钥反转后经**裸 RSA** 得 `encSecKey`。
 */
fun weapiEncrypt(payload: String, random: () -> Double): WeapiForm {
    val secret = randomSecretKey(random)
    val inner = aesCbcEncrypt(PRESET_KEY.utf8(), IV.utf8(), payload.utf8()).toBase64()
    val params = aesCbcEncrypt(secret.utf8(), IV.utf8(), inner.utf8()).toBase64()
    val encSecKey = rsaRaw(WEAPI_PUBLIC_KEY, secret.reversed().utf8()).toHex()
    return WeapiForm(params, encSecKey)
}