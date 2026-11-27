// RSA 与网易云 weapi 的签名（ADR-068）：`encSecKey` 是**裸 RSA**，不是 PKCS#1 v1.5。
//
// - `rsaRaw`：消息字节直接当整数做 `m^e mod n`，左侧补零到模长；用 JCA 的 `RSA/ECB/NoPadding`
//   完成（它接受任意长度 ≤ 模长的输入，不足左侧天然补零）。
// - `rsaEncryptPkcs1`：保留为通用原语（契约里没有它的向量，但 TS 参考实现有；以后若有需要，
//   语义对齐即可），此处仍实现，供对照。
package im.xrl.pterosaur.core.crypto

import java.math.BigInteger
import java.security.KeyFactory
import java.security.interfaces.RSAPublicKey
import java.security.spec.X509EncodedKeySpec
import javax.crypto.Cipher

/** RSA 公钥（`n` / `e`），可从 SPKI DER 解析。 */
data class RsaPublicKey(val n: BigInteger, val e: BigInteger) {
    /** 模长（字节）。 */
    val modulusBytes: Int get() = (n.bitLength() + 7) / 8

    companion object {
        /** 从 SPKI DER（即 PEM 主体 base64 解码后的字节）解析。 */
        fun fromSpki(der: ByteArray): RsaPublicKey {
            val key = KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(der)) as RSAPublicKey
            return RsaPublicKey(key.modulus, key.publicExponent)
        }
    }
}

private fun rsaDoPublic(key: RsaPublicKey, block: ByteArray): ByteArray {
    require(block.size <= key.modulusBytes) { "RSA：输入长度超过模长" }
    // JCA 的 NoPadding 要求输入恰好为模长——左侧补零
    val padded = ByteArray(key.modulusBytes)
    block.copyInto(padded, key.modulusBytes - block.size)
    val spec = java.security.spec.RSAPublicKeySpec(key.n, key.e)
    val pub = KeyFactory.getInstance("RSA").generatePublic(spec)
    val c = Cipher.getInstance("RSA/ECB/NoPadding")
    c.init(Cipher.ENCRYPT_MODE, pub)
    return c.doFinal(padded)
}

/**
 * RSA 原始运算（不做填充）：`c = m^e mod n`，输出定长 `modulusBytes` 字节。
 *
 * 网易云 weapi 的 `encSecKey` 就是裸 RSA——第三方库用 `forge.encrypt(secret, 'NONE')`，
 * 消息字节直接求幂。迁入内核时按 PKCS#1 实现过一次，上游一律回空体（ADR-068 记了这段）。
 */
fun rsaRaw(key: RsaPublicKey, message: ByteArray): ByteArray = rsaDoPublic(key, message)

/**
 * RSA PKCS#1 v1.5 加密（type 2 填充，`00 02 PS 00 D`）。`random` 每次返回 [0,1) 的浮点，
 * 填充串取非零字节；随机源由调用方注入以便测试复现。
 */
fun rsaEncryptPkcs1(key: RsaPublicKey, message: ByteArray, random: () -> Double): ByteArray {
    val k = key.modulusBytes
    require(message.size <= k - 11) { "RSA：明文过长" }
    val em = ByteArray(k)
    em[1] = 0x02
    for (i in 2 until k - message.size - 1) {
        var b = 0
        while (b == 0) b = (random() * 256).toInt() and 0xff
        em[i] = b.toByte()
    }
    message.copyInto(em, k - message.size)
    return rsaDoPublic(key, em)
}