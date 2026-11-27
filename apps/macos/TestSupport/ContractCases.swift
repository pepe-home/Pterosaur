// 契约测试：编码 / 摘要 / AES / 签名 / 归一化 / URL / 实体 / 歌词（packages/contract/**）。
//
// 比对方式：把结果转成 JSON 可表达的形状（Swift 模型 → [String: Any]），与期望做结构深比较。
//
// 不用 XCTest：本仓只在 Xcode 命令行工具（CLT）下构建与自测，CLT 不带 XCTest。
// 入口是 `PterosaurSelfTest`（`swift run selftest`）与 CI 的 macOS job。
import Foundation
import PterosaurCore

enum ContractCases {

    // MARK: - 编码

    static func encodingVectors() throws {
        let kinds: Set<String> = ["utf8.encode", "utf8.decode", "hex.encode", "hex.decode",
                                  "base64.encode", "base64.decode", "form.encode", "form.encodeObject"]
        try Contract.assertVectors("encoding.json", kinds: kinds) { v in
            let s = v.input as? String
            switch v.kind {
            case "utf8.encode", "hex.encode": return Encoding.toHex(Encoding.utf8(s!))
            case "utf8.decode", "hex.decode": return Encoding.decodeUTF8(Encoding.fromHex(s!))
            case "base64.encode": return Encoding.base64(Encoding.utf8(s!))
            case "base64.decode": return Encoding.toHex(Encoding.fromBase64(s!))
            case "form.encode": return Encoding.formUrlEncode(s!)
            case "form.encodeObject":
                let o = v.input as! [String: Any]
                return o.keys.sorted().map { ($0, o[$0] as! String) }.isEmpty ? "" :
                    encodeForm(orderKeysPreserving(o))
            default: fatalError()
            }
        }
    }

    /// `encodeForm` 保持传入顺序；JSON 对象的键序在字典里不可靠，测试对单键对象无歧义，
    /// 多键时按 JSON 源顺序无从获取——契约的 `form.encodeObject` 目前都是单键。
    private static func orderKeysPreserving(_ o: [String: Any]) -> [(String, String)] {
        o.map { ($0.key, $0.value as! String) }
    }

    // MARK: - 摘要

    static func digestVectors() throws {
        let kinds: Set<String> = ["md5.hex", "sha1.hex", "sha256.hex", "pbkdf2.sha256"]
        try Contract.assertVectors("digest.json", kinds: kinds) { v in
            switch v.kind {
            case "md5.hex": return Encoding.toHex(Digest.md5(Encoding.utf8(v.input as! String)))
            case "sha1.hex": return Encoding.toHex(Digest.sha1(Encoding.utf8(v.input as! String)))
            case "sha256.hex": return Encoding.toHex(Digest.sha256(Encoding.utf8(v.input as! String)))
            case "pbkdf2.sha256":
                let o = v.input as! [String: Any]
                return Encoding.toHex(Digest.pbkdf2Sha256(
                    password: o["password"] as! String,
                    salt: o["salt"] as! String,
                    iterations: (o["iterations"] as! NSNumber).intValue))
            default: fatalError()
            }
        }
    }

    // MARK: - AES

    static func aesVectors() throws {
        let kinds: Set<String> = Set(
            [128, 192, 256].flatMap { bits in
                ["aes-\(bits).ecb.encrypt"] + ["encrypt", "decrypt"].map { "aes-\(bits).cbc.\($0)" }
            } + ["aes-128.ecb.decrypt"])
        try Contract.assertVectors("aes.json", kinds: kinds) { v in
            let o = v.input as! [String: Any]
            let key = Encoding.fromHex(o["key"] as! String)
            switch v.kind {
            case let k where k.hasSuffix(".ecb.encrypt"):
                return Encoding.toHex(Aes.ecbEncrypt(key: key, plain: Encoding.fromHex(o["plaintextHex"] as! String)))
            case let k where k.hasSuffix(".ecb.decrypt"):
                return Encoding.toHex(Aes.ecbDecrypt(key: key, cipher: Encoding.fromHex(o["ciphertextHex"] as! String)))
            case let k where k.hasSuffix(".cbc.encrypt"):
                return Encoding.toHex(Aes.cbcEncrypt(key: key, iv: Encoding.fromHex(o["iv"] as! String),
                                                     plain: Encoding.fromHex(o["plaintextHex"] as! String)))
            case let k where k.hasSuffix(".cbc.decrypt"):
                return Encoding.toHex(Aes.cbcDecrypt(key: key, iv: Encoding.fromHex(o["iv"] as! String),
                                                     cipher: Encoding.fromHex(o["ciphertextHex"] as! String)))
            default: fatalError()
            }
        }
    }

    // MARK: - 签名

    static func signVectors() throws {
        try Contract.assertVectors("netease-sign.json", kinds: ["netease.eapi.sign"]) { v in
            let o = v.input as! [String: Any]
            let payload = o["payload"]
            let text: String
            if let s = payload as? String { text = s }
            else {
                let d = try! JSONSerialization.data(withJSONObject: payload!, options: [.withoutEscapingSlashes])
                text = String(data: d, encoding: .utf8)!
            }
            return eapiSign(path: o["path"] as! String, payload: text)
        }
        try Contract.assertVectors("netease-sign.json", kinds: ["netease.weapi.encrypt"]) { v in
            let o = v.input as! [String: Any]
            let secret = o["secret"] as! String
            let payload = o["payload"]!
            let d = try! JSONSerialization.data(withJSONObject: payload, options: [])
            let text = String(data: d, encoding: .utf8)!
            let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
            var seq = secret.map { Double(chars.firstIndex(of: $0)!) / 61.0 }
            var i = 0
            let rng: () -> Double = { i < seq.count ? seq[i] : 0.5 }
            func next() -> Double { defer { i += 1 }; return rng() }
            let form = weapiEncrypt(payload: text, next)
            return ["params": form.params, "encSecKey": form.encSecKey]
        }
    }

    // MARK: - 图片 / 实体 / URL

    static func normalizeVectors() throws {
        let kinds: Set<String> = ["netease.image.canonical", "netease.image.coverAt", "bilibili.image.canonical"]
        try Contract.assertVectors("normalize.json", kinds: kinds) { v in
            switch v.kind {
            case "netease.image.canonical": return canonicalNeteaseImage(v.input as! String)
            case "bilibili.image.canonical": return canonicalBiliImage(v.input as! String)
            case "netease.image.coverAt":
                let o = v.input as! [String: Any]
                return coverAt(o["url"] as! String, (o["px"] as! NSNumber).intValue) as Any
            default: fatalError()
            }
        }
    }

    static func entityVectors() throws {
        let kinds: Set<String> = ["entity.keyOf", "entity.sourceOf", "stream.url"]
        try Contract.assertVectors("entity.json", kinds: kinds) { v in
            let o = v.input as? [String: Any]
            switch v.kind {
            case "entity.keyOf":
                return keyOf(source: sourceOf(o?["source"] as? String), id: o!["id"] as! String)
            case "entity.sourceOf":
                return sourceOf(o?["source"] as? String)
            case "stream.url":
                let id = o!["id"] as! String
                var q: [String] = []
                if let lvl = o?["level"] as? String { q.append("level=\(lvl)") }
                if let t = o?["token"] as? String { q.append("t=\(t)") }
                return "/stream/netease/\(id)" + (q.isEmpty ? "" : "?" + q.joined(separator: "&"))
            default: fatalError()
            }
        }
    }

    static func urlVectors() throws {
        let kinds: Set<String> = ["url.split", "url.join", "url.queryValues", "url.replaceQuery"]
        try Contract.assertVectors("url.json", kinds: kinds) { v in
            switch v.kind {
            case "url.split":
                guard let p = splitUrl(v.input as! String) else { return NSNull() }
                return ["protocol": p.protocolScheme, "userinfo": p.userinfo, "hostname": p.hostname,
                        "port": p.port, "rest": p.rest]
            case "url.join":
                let o = v.input as! [String: Any]
                let parts = UrlParts(protocolScheme: o["protocol"] as! String, userinfo: o["userinfo"] as! String,
                                     hostname: o["hostname"] as! String, port: o["port"] as! String,
                                     rest: o["rest"] as! String)
                return joinUrl(parts)
            case "url.queryValues":
                let o = v.input as! [String: Any]
                return queryValues(o["rest"] as! String, o["key"] as! String)
            case "url.replaceQuery":
                let o = v.input as! [String: Any]
                return replaceQuery(o["rest"] as! String, o["query"] as! String)
            default: fatalError()
            }
        }
    }

    static func lyricVectors() throws {
        try Contract.assertVectors("lyric.json", kinds: ["lyric.parseLrc"]) { v in
            let o = v.input as! [String: Any]
            let lyric = parseLrc(o["lrc"] as! String, translation: o["translation"] as? String)
            let lines: [Any] = lyric.lines.map { l -> [String: Any] in
                var d: [String: Any] = ["time": numberValue(l.time), "text": l.text]
                if let t = l.translation { d["translation"] = t }
                return d
            }
            return ["lines": lines, "timed": lyric.timed] as [String: Any]
        }
    }

    /// 时间数值：整数秒以整数写出（与 JS 的 `1` 而非 `1.0` 一致）。
    private static func numberValue(_ t: Double) -> Any {
        t == t.rounded() && t.isFinite ? Int(t) : t
    }
}