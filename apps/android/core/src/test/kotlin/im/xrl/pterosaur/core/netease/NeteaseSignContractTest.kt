// 契约对拍：RSA 与网易云签名（packages/contract/vectors/netease-sign.json）。
package im.xrl.pterosaur.core.netease

import im.xrl.pterosaur.core.assertVectors
import im.xrl.pterosaur.core.asObject
import im.xrl.pterosaur.core.asString
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.test.Test

class NeteaseSignContractTest {

    @Test
    fun eapiSign() {
        assertVectors("netease-sign.json", setOf("netease.eapi.sign")) { v ->
            val o = v.input.asObject()
            val payload = o.getValue("payload")
            // payload 可能是字符串、对象或空串：对象按 JSON 紧凑序列化（与 TS 的 JSON.stringify 同形）
            val text = when {
                payload is JsonPrimitive -> payload.content
                else -> payload.toString()
            }
            JsonPrimitive(eapiSign(o.getValue("path").asString(), text))
        }
    }

    @Test
    fun weapiEncrypt() {
        assertVectors("netease-sign.json", setOf("netease.weapi.encrypt")) { v ->
            val o = v.input.asObject()
            val secret = o.getValue("secret").asString()
            val payload = o.getValue("payload")
            // TS 的 JSON.stringify 默认不插空格、键序即插入序；kotlinx 的 toString 同样是紧凑且保序
            val text = payload.toString()
            val rng = fixedRng(secret)
            val form = weapiEncrypt(text, rng)
            JsonObject(
                mapOf(
                    "params" to JsonPrimitive(form.params),
                    "encSecKey" to JsonPrimitive(form.encSecKey),
                ),
            )
        }
    }

    /** 让 `randomSecretKey` 依次产出给定 secret 的随机源（`round(r * 61) = idx` → `r = idx / 61`）。 */
    private fun fixedRng(secret: String): () -> Double {
        val seq = secret.map { BASE62_INDEX.getValue(it) / 61.0 }
        var i = 0
        return { if (i < seq.size) seq[i++] else 0.5 }
    }

    private companion object {
        val BASE62_INDEX: Map<Char, Int> =
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
                .withIndex()
                .associate { (i, c) -> c to i }
    }
}
