// 契约读取与「逐条复算」骨架（ADR-069）。
//
// 契约在仓库的 `packages/contract/`，由 Gradle 以系统属性 `pterosaur.contract` 传入绝对路径；
// 测试直接读文件，**不复制样例**。
package im.xrl.pterosaur.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File

/** 契约根目录（绝对路径）。 */
val contractDir: File by lazy {
    val fromProperty = System.getProperty("pterosaur.contract")
    val root = if (!fromProperty.isNullOrBlank()) File(fromProperty) else File("../../../packages/contract")
    require(root.isDirectory) { "找不到契约目录：${root.absolutePath}" }
    root.canonicalFile
}

private val json = Json { ignoreUnknownKeys = true }

/** 一条向量。 */
data class Vector(val kind: String, val input: JsonElement, val expected: JsonElement)

/** 读 `vectors/<file>` 里的全部向量。 */
fun loadVectors(file: String): List<Vector> {
    val root = json.parseToJsonElement(File(contractDir, "vectors/$file").readText()).jsonObject
    return root.getValue("vectors").jsonArray.map { v ->
        val o = v.jsonObject
        Vector(
            kind = o.getValue("kind").jsonPrimitive.content,
            input = o.getValue("input"),
            expected = o.getValue("expected"),
        )
    }
}

/** 断言「复算结果 == 期望」时给出的失败明细（一次报全部，而不是在第一条就停）。 */
fun assertVectors(file: String, kinds: Set<String>, run: (Vector) -> JsonElement) {
    val failures = mutableListOf<String>()
    // 只取本测试负责的 kind：多组测试共用一个文件时，每组都必须**真的**复算，而不是跳过即通过
    val all = loadVectors(file)
    val vectors = all.filter { v -> v.kind in kinds }
    require(vectors.isNotEmpty()) { "$file 里没有 ${kinds.joinToString()} 的向量" }
    val covered = vectors.map { it.kind }.toSet()
    val missing = kinds - covered
    require(missing.isEmpty()) { "$file 里缺少这些 kind 的向量：${missing.joinToString()}（测试声明了却没东西可测）" }
    for (v in vectors) {
        val got = run(v)
        if (got != v.expected) {
            failures += "${v.kind}  input=${compact(v.input)}\n    expected=${compact(v.expected)}\n    actual  =${compact(got)}"
        }
    }
    if (failures.isNotEmpty()) {
        throw AssertionError("$file：${failures.size}/${vectors.size} 条不符\n" + failures.joinToString("\n"))
    }
}

private fun compact(e: JsonElement): String = e.toString().let { if (it.length > 160) it.take(160) + "…" else it }

/* ============================ JSON 便捷构造 ============================ */

fun JsonElement.asString(): String = jsonPrimitive.content
fun JsonElement.asObject(): JsonObject = jsonObject
fun JsonElement.asArray(): JsonArray = jsonArray
fun JsonElement.asInt(): Int = jsonPrimitive.content.toInt()
fun String.toJson(): JsonElement = json.parseToJsonElement(this)