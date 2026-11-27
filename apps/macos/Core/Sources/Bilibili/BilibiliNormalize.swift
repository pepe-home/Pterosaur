// B 站（磁带）归一化（Swift 版，对应 packages/core/src/sources/bilibili.ts）。
import Foundation

private let TAG_RE = try! NSRegularExpression(pattern: "<[^>]+>")

/// 去掉 `<em>` 高亮标签并解码常见 HTML 实体。
public func decodeTitle(_ html: String) -> String {
    var s = TAG_RE.stringByReplacingMatches(in: html, range: NSRange(location: 0, length: (html as NSString).length), withTemplate: "")
    for (from, to) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")] {
        s = s.replacingOccurrences(of: from, with: to)
    }
    return s.trimmingCharacters(in: .whitespaces)
}

/// 时长 `"12:34"` / `"1:02:03"` → 秒；非法返回 0。
public func parseDuration(_ d: String?) -> Int {
    guard let d, !d.isEmpty else { return 0 }
    let parts = d.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
    var total = 0.0
    for p in parts {
        guard let n = Double(p) else { return 0 }
        total = total * 60 + n
    }
    return Int(total)
}

/// 视频条目 → 磁带曲目。`id` 取 bvid，缺省退回 aid。
public func normalizeBilibiliTrack(_ v: JSON) -> Track {
    let id = jsonString(v["bvid"]) ?? jsonLong(v["aid"]).map(String.init) ?? ""
    let title = decodeTitle(jsonString(v["title"]) ?? "")
    return Track(
        source: "bilibili",
        id: id,
        title: title.isEmpty ? "未知视频" : title,
        artist: jsonString(v["author"]) ?? "未知 UP 主",
        album: "",
        cover: canonicalBiliImage(jsonString(v["pic"])),
        duration: parseDuration(jsonString(v["duration"])),
        fee: "free")
}