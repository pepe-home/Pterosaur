// 黄金样例的**快照**校验（不依赖 XCTest——命令行工具链里没有 XCTest）。
//
// `fixtures/golden-observed.json` 是本端归一化实现逐条跑 `packages/contract/golden/normalize.json`
// 得到的输出（含期望值与实际值）。此测试同时核对两件事：
// 1. 快照里的「期望值」与 `packages/contract` 原文逐条一致（契约没变）；
// 2. 快照里的「实际值」与现在的实现再跑一遍一致（实现没漂）。
// 契约一变，双重校验双双失败，提示重新生成快照——保证 Swift 侧不会在契约更新后静默落后。
import Foundation
import PterosaurCore

public enum GoldenObserved {
    public static func run() -> Int {
        var failures = 0
        do {
            let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: Contract.fixtures.appendingPathComponent("golden-observed.json"))) as! [String: Any]
            let golden = try Contract.json("golden/normalize.json")
            let saved = fixture["cases"] as? [[String: Any]] ?? []
            let cases = golden["cases"] as? [[String: Any]] ?? []
            if saved.count != cases.count {
                print("FAIL golden 快照条数 \(saved.count) ≠ 契约 \(cases.count)：契约更新后需重新生成快照")
                failures += 1
            }
            for (i, c) in cases.enumerated() {
                let id = c["id"] as! String
                let fn = c["fn"] as! String
                guard i < saved.count, saved[i]["fn"] as? String == fn else {
                    print("FAIL golden 第 \(i) 条顺序或 fn 与契约不一致（\(fn)）")
                    failures += 1
                    continue
                }
                if !jsonEqual(saved[i]["expected"]!, c["expected"]!) {
                    print("FAIL golden \(id) 快照里的期望值与契约原文不一致")
                    failures += 1
                }
                let got: Any
                do {
                    got = try Golden.compute(fn, c["input"]!)
                } catch {
                    print("FAIL golden \(id)：\(error)")
                    failures += 1
                    continue
                }
                if !jsonEqual(got, saved[i]["actual"]!) {
                    print("FAIL golden \(id)（\(fn)）实际值与快照不一致：\(compact(got)) vs \(compact(saved[i]["actual"]!))")
                    failures += 1
                }
                if !jsonEqual(saved[i]["actual"]!, c["expected"]!) {
                    print("FAIL golden \(id)（\(fn)）快照实际值与契约期望不一致")
                    failures += 1
                }
            }
        } catch {
            print("FAIL golden 读取失败：\(error)")
            failures += 1
        }
        return failures
    }

    private static func compact(_ v: Any) -> String {
        // 顶层是标量时 JSONSerialization 会抛（不是合法的顶层类型），文本里夹带的引号也会被顺手转义成 `\"`；
        // 错误信息只是给人看的，改用 `String(describing:)`。
        let s = String(describing: v)
        return s.count > 200 ? String(s.prefix(200)) + "…" : s
    }
}

/// 黄金样例的计算入口：模型 → JSON 形状（`nil` 可选字段不出现；`source` 恒出现）。
enum Golden {
    static func compute(_ fn: String, _ input: Any) throws -> Any {
        switch fn {
        case "netease.normalizeTrack":
            let t = normalizeTrack(input as! JSON)
            return dict("source", t.source, "id", t.id, "title", t.title, "artist", t.artist,
                        "album", t.album, "cover", t.cover, "duration", t.duration, "fee", t.fee,
                        "artistRefs", refs(t.artistRefs), "albumId", t.albumId)
        case "netease.normalizeArtist":
            let a = normalizeArtist(input as! JSON)
            return dict("source", a.source, "id", a.id, "name", a.name, "avatar", a.avatar,
                        "alias", a.alias, "albumSize", a.albumSize, "musicSize", a.musicSize,
                        "briefDesc", a.briefDesc)
        case "netease.normalizeAlbum":
            let a = normalizeAlbum(input as! JSON)
            return dict("source", a.source, "id", a.id, "name", a.name, "cover", a.cover,
                        "artist", a.artist, "artistId", a.artistId, "artistRefs", refs(a.artistRefs),
                        "year", a.year, "genre", a.genre, "type", a.type, "trackCount", a.trackCount)
        case "netease.normalizePlaylist":
            let p = normalizePlaylist(input as! JSON)
            return dict("source", p.source, "id", p.id, "name", p.name, "cover", p.cover,
                        "description", p.description, "trackCount", p.trackCount,
                        "playCount", p.playCount, "creator", p.creator)
        case "bilibili.normalizeTrack":
            let t = normalizeBilibiliTrack(input as! JSON)
            return dict("source", t.source, "id", t.id, "title", t.title, "artist", t.artist,
                        "album", t.album, "cover", t.cover, "duration", t.duration, "fee", t.fee,
                        "artistRefs", refs(t.artistRefs), "albumId", t.albumId)
        case "bilibili.decodeTitle": return decodeTitle(input as! String)
        case "bilibili.parseDuration": return parseDuration(input as? String)
        case "bilibili.canonicalImage": return canonicalBiliImage(input as? String)
        default:
            throw NSError(domain: "golden", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "没有 \(fn) 的入口"])
        }
    }

    private static func refs(_ r: [ArtistRef]?) -> Any? {
        r.map { list in list.map { ["id": $0.id, "name": $0.name] as [String: Any] } }
    }

    /// 成对的 key / value（值须为 JSON 可写类型或其 Optional；nil 不写入）。
    private static func dict(_ kv: Any?...) -> [String: Any] {
        var d = [String: Any]()
        var i = 0
        while i + 1 < kv.count {
            let k = kv[i] as! String
            if let v = kv[i + 1] { d[k] = v }
            i += 2
        }
        return d
    }
}
