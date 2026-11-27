// 黄金样例：上游原始 JSON → 共享模型（packages/contract/golden/normalize.json）。
//
// 模型 → JSON 的规则与 Kotlin 侧一致：`source` 恒出现；`nil` 的可选字段**不出现**。
import XCTest
@testable import PterosaurCore

final class GoldenTests: XCTestCase {

    func testGolden() throws {
        let root = try Contract.json("golden/normalize.json")
        let cases = root["cases"] as! [[String: Any]]
        XCTAssertGreaterThan(cases.count, 10)
        var failures: [String] = []
        for c in cases {
            let id = c["id"] as! String
            let fn = c["fn"] as! String
            let input = c["input"]!
            let expected = c["expected"]!
            let got = try! compute(fn, input)
            if !jsonEqual(got, expected) {
                failures.append("\(id) (\(fn))\n  expected=\(try! compact(expected))\n  actual  =\(try! compact(got))")
            }
        }
        if !failures.isEmpty {
            XCTFail("golden：\(failures.count)/\(cases.count) 条不符\n" + failures.joined(separator: "\n"))
        }
    }

    private func compute(_ fn: String, _ input: Any) throws -> Any {
        switch fn {
        case "netease.normalizeTrack": return modelJSON(normalizeTrack(input as! JSON))
        case "netease.normalizeArtist": return modelJSON(normalizeArtist(input as! JSON))
        case "netease.normalizeAlbum": return modelJSON(normalizeAlbum(input as! JSON))
        case "netease.normalizePlaylist": return modelJSON(normalizePlaylist(input as! JSON))
        case "bilibili.normalizeTrack": return modelJSON(normalizeBilibiliTrack(input as! JSON))
        case "bilibili.decodeTitle": return decodeTitle(input as! String)
        case "bilibili.parseDuration": return parseDuration(input as? String)
        case "bilibili.canonicalImage": return canonicalBiliImage(input as? String)
        default: throw NSError(domain: "golden", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有 \(fn) 的入口"])
        }
    }

    private func compact(_ v: Any) throws -> String {
        let d = try JSONSerialization.data(withJSONObject: v, options: [.sortedKeys])
        return String(data: d, encoding: .utf8)!
    }

    // MARK: - 模型 → JSON

    private func put(_ d: inout [String: Any], _ k: String, _ v: Any?) {
        if let v { d[k] = v }
    }

    func modelJSON(_ t: Track) -> Any {
        var d: [String: Any] = [
            "source": t.source, "id": t.id, "title": t.title, "artist": t.artist,
            "album": t.album, "cover": t.cover, "duration": t.duration, "fee": t.fee,
        ]
        put(&d, "artistRefs", t.artistRefs?.map { ["id": $0.id, "name": $0.name] as [String: Any] })
        put(&d, "albumId", t.albumId)
        return d
    }

    func modelJSON(_ a: Artist) -> Any {
        var d: [String: Any] = ["source": a.source, "id": a.id, "name": a.name, "avatar": a.avatar]
        put(&d, "alias", a.alias)
        put(&d, "albumSize", a.albumSize)
        put(&d, "musicSize", a.musicSize)
        put(&d, "briefDesc", a.briefDesc)
        return d
    }

    func modelJSON(_ a: Album) -> Any {
        var d: [String: Any] = ["source": a.source, "id": a.id, "name": a.name, "cover": a.cover, "artist": a.artist]
        put(&d, "artistId", a.artistId)
        put(&d, "artistRefs", a.artistRefs?.map { ["id": $0.id, "name": $0.name] as [String: Any] })
        put(&d, "year", a.year)
        put(&d, "genre", a.genre)
        put(&d, "type", a.type)
        put(&d, "trackCount", a.trackCount)
        return d
    }

    func modelJSON(_ p: Playlist) -> Any {
        var d: [String: Any] = ["source": p.source, "id": p.id, "name": p.name, "cover": p.cover]
        put(&d, "description", p.description)
        put(&d, "trackCount", p.trackCount)
        put(&d, "playCount", p.playCount)
        put(&d, "creator", p.creator)
        return d
    }
}