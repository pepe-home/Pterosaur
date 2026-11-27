// LRC 歌词解析（Kotlin 版，对应 shared/lyric.ts）。
package im.xrl.pterosaur.core.model

private val TIMESTAMP = Regex("""(\d+):(\d{1,2})(?:[.:](\d{1,3}))?""")
private val BRACKET = Regex("""\[([^\]]+)]""")

/** 解析单条时间戳为秒；支持 `[mm:ss]`、`[mm:ss.xx]`、`[mm:ss.xxx]`。 */
private fun parseTimestamp(raw: String): Double? {
    val m = TIMESTAMP.find(raw) ?: return null
    val min = m.groupValues[1].toIntOrNull() ?: 0
    val sec = m.groupValues[2].toIntOrNull() ?: 0
    val fracRaw = m.groupValues[3]
    val frac = if (fracRaw.isEmpty()) 0.0 else (fracRaw.padEnd(3, '0').take(3).toIntOrNull() ?: 0) / 1000.0
    return min * 60 + sec + frac
}

/** 解析 LRC 文本为若干 `{ time, text }`（不含翻译）；一行多时间戳会展开为多行。 */
private fun parseLines(lrc: String): List<LyricLine> {
    val out = mutableListOf<LyricLine>()
    if (lrc.isEmpty()) return out
    for (raw in lrc.split(Regex("\r?\n"))) {
        val line = raw.trim()
        if (line.isEmpty()) continue
        val stamps = BRACKET.findAll(line).map { it.groupValues[1] }.toList()
        if (stamps.isEmpty()) continue
        val text = line.replace(BRACKET, "").trim()
        for (s in stamps) {
            val time = parseTimestamp(s) ?: continue
            out += LyricLine(time = time, text = text)
        }
    }
    out.sortBy { it.time }
    return out
}

private fun round2(v: Double): Long = Math.round(v * 100)

/** 解析带翻译的 LRC：以时间为键对齐翻译（容差 0.01s）。 */
fun parseLrc(lrc: String, tlyric: String? = null): Lyric {
    var lines: MutableList<LyricLine> = parseLines(lrc).toMutableList()
    val timed = lines.any { it.text.isNotEmpty() }
    if (!tlyric.isNullOrEmpty() && lines.isNotEmpty()) {
        val trans = parseLines(tlyric)
        if (trans.isNotEmpty()) {
            val byTime = trans.filter { it.text.isNotEmpty() }.associateBy { round2(it.time) }
            for (i in lines.indices) {
                val line = lines[i]
                val key = round2(line.time)
                val hit = byTime[key] ?: byTime[key + 1] ?: byTime[key - 1]
                if (hit != null) lines[i] = line.copy(translation = hit.text)
            }
        }
    }
    return Lyric(lines = lines, timed = timed)
}