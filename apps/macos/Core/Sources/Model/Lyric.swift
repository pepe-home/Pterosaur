// LRC 歌词解析（Swift 版，对应 shared/lyric.ts）。
import Foundation

private let TIMESTAMP = try! NSRegularExpression(pattern: #"(\d+):(\d{1,2})(?:[.:](\d{1,3}))?"#)
private let BRACKET = try! NSRegularExpression(pattern: #"\[([^\]]+)\]"#, options: [])

private func parseTimestamp(_ raw: String) -> Double? {
    let ns = raw as NSString
    guard let m = TIMESTAMP.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) else { return nil }
    func g(_ i: Int) -> String { m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
    let min = Double(g(1)) ?? 0
    let sec = Double(g(2)) ?? 0
    var frac = g(3)
    if frac.isEmpty { return min * 60 + sec }
    while frac.count < 3 { frac += "0" }
    return min * 60 + sec + (Double(frac.prefix(3)) ?? 0) / 1000.0
}

private func parseLines(_ lrc: String) -> [LyricLine] {
    var out = [LyricLine]()
    if lrc.isEmpty { return out }
    for raw in lrc.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
        if raw.isEmpty { continue }
        let ns = raw as NSString
        let stamps = BRACKET.matches(in: raw, range: NSRange(location: 0, length: ns.count)).map { ns.substring(with: $0.range(at: 1)) }
        if stamps.isEmpty { continue }
        let text = BRACKET.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: ns.length), withTemplate: "").trimmingCharacters(in: .whitespaces)
        for s in stamps {
            guard let time = parseTimestamp(s) else { continue }
            out.append(LyricLine(time: time, text: text))
        }
    }
    out.sort { $0.time < $1.time }
    return out
}

private func round2(_ v: Double) -> Int { Int((v * 100).rounded()) }

/// 解析带翻译的 LRC：以时间为键对齐翻译（容差 0.01s）。
public func parseLrc(_ lrc: String, translation: String? = nil) -> Lyric {
    var lines = parseLines(lrc)
    let timed = lines.contains { !$0.text.isEmpty }
    if let tlyric = translation, !tlyric.isEmpty, !lines.isEmpty {
        let trans = parseLines(tlyric)
        if !trans.isEmpty {
            let byTime = Dictionary(grouping: trans.filter { !$0.text.isEmpty }, by: { round2($0.time) })
                .compactMapValues { $0.first }
            for i in 0..<lines.count {
                let line = lines[i]
                let key = round2(line.time)
                if let hit = byTime[key] ?? byTime[key + 1] ?? byTime[key - 1] {
                    lines[i] = LyricLine(time: line.time, text: line.text, translation: hit.text)
                }
            }
        }
    }
    return Lyric(lines: lines, timed: timed)
}