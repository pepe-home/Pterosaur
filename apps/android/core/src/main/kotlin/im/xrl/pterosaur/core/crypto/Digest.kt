// 摘要与密钥派生：MD5 / SHA-1 / SHA-256 / PBKDF2-HMAC-SHA256（契约见 packages/contract/vectors/digest.json）。
//
// 全部走 JVM 自带的 JCA（`MessageDigest` / `SecretKeyFactory`），不再手写——与 TS 参考实现「要
// 引擎可移植所以手写」的动机相反：JVM 自带算法实现，且跨平台一致。
package im.xrl.pterosaur.core.crypto

import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec
import java.security.MessageDigest

/** MD5 摘要（B 站 wbi 签名、网易云 eapi 报文摘要用）。 */
fun md5(data: ByteArray): ByteArray = MessageDigest.getInstance("MD5").digest(data)

/** SHA-1 摘要（凭证指纹用）。 */
fun sha1(data: ByteArray): ByteArray = MessageDigest.getInstance("SHA-1").digest(data)

/** SHA-256 摘要（HMAC / KDF 的基础）。 */
fun sha256(data: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(data)

/**
 * PBKDF2-HMAC-SHA256，输出 32 字节。网易云网页端 eapi 用 `PBKDF2('secret', salt, 1, 32, SHA-256)` 派生密钥。
 *
 * `SecretKeyFactory` 的 `PBKDF2WithHmacSHA256` 输出长度受 JDK 限制为 32 字节（符合本用例）。
 */
fun pbkdf2Sha256(password: String, salt: String, iterations: Int): ByteArray {
    val spec = PBEKeySpec(password.toCharArray(), salt.utf8(), iterations, 256)
    return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
}