// 契约对拍：编解码 / 摘要 / AES（packages/contract/vectors/{encoding,digest,aes}.json）。
package im.xrl.pterosaur.core.crypto

import im.xrl.pterosaur.core.assertVectors
import im.xrl.pterosaur.core.asInt
import im.xrl.pterosaur.core.asObject
import im.xrl.pterosaur.core.asString
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlin.test.Test

class CryptoContractTest {

    private companion object {
        val ENCODING_KINDS = setOf(
            "utf8.encode", "utf8.decode", "hex.encode", "hex.decode",
            "base64.encode", "base64.decode", "form.encode", "form.encodeObject",
        )
        val DIGEST_KINDS = setOf("md5.hex", "sha1.hex", "sha256.hex", "pbkdf2.sha256")

        /** AES 的 kind 形如 `aes-128.ecb.encrypt`：按后缀归组，覆盖 128/192/256 与 ECB/CBC、加/解密。 */
        val AES_KINDS = buildSet {
            // 契约里实际存在的 kind：ECB 只有 128 位解密；CBC 三种密钥长度都有加解密
            for (bits in listOf(128, 192, 256)) add("aes-$bits.ecb.encrypt")
            add("aes-128.ecb.decrypt")
            for (bits in listOf(128, 192, 256)) for (op in listOf("encrypt", "decrypt")) add("aes-$bits.cbc.$op")
        }
    }

    @Test
    fun encoding() {
        assertVectors("encoding.json", ENCODING_KINDS) { v ->
            val input = v.input
            when (v.kind) {
                "utf8.encode", "hex.encode" -> JsonPrimitive(input.asString().utf8().toHex())
                "utf8.decode" -> JsonPrimitive(input.asString().fromHex().decodeUtf8())
                "hex.decode" -> JsonPrimitive(input.asString().fromHex().decodeUtf8())
                "base64.encode" -> JsonPrimitive(input.asString().utf8().toBase64())
                "base64.decode" -> JsonPrimitive(input.asString().fromBase64().toHex())
                "form.encode" -> JsonPrimitive(formUrlEncode(input.asString()))
                "form.encodeObject" -> {
                    val fields = input.asObject().map { (k, v) -> k to v.asString() }
                    JsonPrimitive(encodeForm(fields))
                }
                else -> error("测试没有 ${v.kind} 的入口")
            }
        }
    }

    @Test
    fun digest() {
        assertVectors("digest.json", DIGEST_KINDS) { v ->
            when (v.kind) {
                "md5.hex" -> JsonPrimitive(md5(v.input.asString().utf8()).toHex())
                "sha1.hex" -> JsonPrimitive(sha1(v.input.asString().utf8()).toHex())
                "sha256.hex" -> JsonPrimitive(sha256(v.input.asString().utf8()).toHex())
                "pbkdf2.sha256" -> {
                    val o = v.input.asObject()
                    JsonPrimitive(
                        pbkdf2Sha256(
                            o.getValue("password").asString(),
                            o.getValue("salt").asString(),
                            o.getValue("iterations").asInt(),
                        ).toHex(),
                    )
                }
                else -> error("测试没有 ${v.kind} 的入口")
            }
        }
    }

    @Test
    fun aes() {
        assertVectors("aes.json", AES_KINDS) { v ->
            val o = v.input.asObject()
            val key = o.getValue("key").asString().fromHex()
            when {
                v.kind.endsWith(".ecb.encrypt") ->
                    JsonPrimitive(aesEcbEncrypt(key, o.getValue("plaintextHex").asString().fromHex()).toHex())
                v.kind.endsWith(".ecb.decrypt") ->
                    JsonPrimitive(aesEcbDecrypt(key, o.getValue("ciphertextHex").asString().fromHex()).toHex())
                v.kind.endsWith(".cbc.encrypt") -> {
                    val iv = o.getValue("iv").asString().fromHex()
                    JsonPrimitive(aesCbcEncrypt(key, iv, o.getValue("plaintextHex").asString().fromHex()).toHex())
                }
                v.kind.endsWith(".cbc.decrypt") -> {
                    val iv = o.getValue("iv").asString().fromHex()
                    JsonPrimitive(aesCbcDecrypt(key, iv, o.getValue("ciphertextHex").asString().fromHex()).toHex())
                }
                else -> error("测试没有 ${v.kind} 的入口")
            }
        }
    }
}