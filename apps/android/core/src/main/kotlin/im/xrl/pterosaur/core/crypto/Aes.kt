// 分组加密：AES-128/192/256 的 ECB / CBC，PKCS#7 填充（契约见 packages/contract/vectors/aes.json）。
//
// 走 JVM 自带 JCA：`AES/ECB/PKCS5Padding` 与 `AES/CBC/PKCS5Padding`——JCA 的 PKCS5Padding 在
// 分组长度为 16 字节的 AES 上即 PKCS#7（RFC 8018 §6.3 把 PKCS5 扩展到任意块长）。
package im.xrl.pterosaur.core.crypto

import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

private fun cipher(mode: String, encrypted: Boolean, key: ByteArray, iv: ByteArray?): Cipher {
    require(key.size == 16 || key.size == 24 || key.size == 32) {
        "AES 密钥长度必须是 16 / 24 / 32 字节，实际 ${key.size}"
    }
    val c = Cipher.getInstance("AES/$mode/PKCS5Padding")
    val spec = SecretKeySpec(key, "AES")
    when {
        !encrypted -> c.init(Cipher.DECRYPT_MODE, spec, iv?.let { IvParameterSpec(it) })
        iv == null -> c.init(Cipher.ENCRYPT_MODE, spec)
        else -> c.init(Cipher.ENCRYPT_MODE, spec, IvParameterSpec(iv))
    }
    return c
}

/** AES-ECB 加密（PKCS#7 填充）。 */
fun aesEcbEncrypt(key: ByteArray, plain: ByteArray): ByteArray =
    cipher("ECB", true, key, null).doFinal(plain)

/** AES-ECB 解密（去 PKCS#7 填充）。 */
fun aesEcbDecrypt(key: ByteArray, cipherText: ByteArray): ByteArray {
    require(cipherText.isNotEmpty() && cipherText.size % 16 == 0) { "aesEcbDecrypt: 密文长度必须是 16 的正整数倍" }
    return cipher("ECB", false, key, null).doFinal(cipherText)
}

/** AES-CBC 加密（PKCS#7 填充）。 */
fun aesCbcEncrypt(key: ByteArray, iv: ByteArray, plain: ByteArray): ByteArray {
    require(iv.size == 16) { "AES-CBC: IV 必须是 16 字节" }
    return cipher("CBC", true, key, iv).doFinal(plain)
}

/** AES-CBC 解密（去 PKCS#7 填充）。 */
fun aesCbcDecrypt(key: ByteArray, iv: ByteArray, cipherText: ByteArray): ByteArray {
    require(iv.size == 16) { "AES-CBC: IV 必须是 16 字节" }
    require(cipherText.isNotEmpty() && cipherText.size % 16 == 0) { "aesCbcDecrypt: 密文长度必须是 16 的正整数倍" }
    return cipher("CBC", false, key, iv).doFinal(cipherText)
}