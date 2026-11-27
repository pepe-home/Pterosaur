// 契约读取工具（MACOS 版）：读 packages/contract/**，不复制样例（ADR-069）。
//
// 在 `PterosaurTestSupport` 里（而不是测试 target）：本仓的自测跑在命令行工具链下，
// 没有 XCTest，自测入口是可执行 target `PterosaurSelfTest`。
import Foundation

enum Contract {
    /// 契约根目录：由 CI 注入环境变量 `PTEROSAUR_CONTRACT`（指向 packages/contract）；
    /// 缺省按源码位置从 `TestSupport/` 往上三层到仓库根再进 `packages/contract`。
    static let root: URL = {
        if let fromEnv = ProcessInfo.processInfo.environment["PTEROSAUR_CONTRACT"] {
            return URL(fileURLWithPath: fromEnv)
        }
        let here = URL(fileURLWithPath: #filePath)          // TestSupport/Contract.swift
            .deletingLastPathComponent()                     // TestSupport
            .deletingLastPathComponent()                     // macos
            .deletingLastPathComponent()                     // apps
            .deletingLastPathComponent()                     // 仓库根
        return here.appendingPathComponent("packages/contract")
    }()

    /// 本端自己的夹具目录（`TestSupport/Fixtures`，按源码位置定位，不随契约目录走）。
    static let fixtures: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    static func data(_ relative: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(relative))
    }

    static func json(_ relative: String) throws -> [String: Any] {
        guard let o = try JSONSerialization.jsonObject(with: data(relative)) as? [String: Any] else {
            throw NSError(domain: "contract", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(relative) 不是对象"])
        }
        return o
    }

    /// 一条向量。
    struct Vector {
        let kind: String
        let input: Any
        let expected: Any
    }

    /// 读 `vectors/<file>` 里的全部向量。
    static func vectors(_ file: String) throws -> [Vector] {
        let root = try json("vectors/\(file)")
        guard let list = root["vectors"] as? [[String: Any]] else { return [] }
        return list.map { Vector(kind: $0["kind"] as! String, input: $0["input"]!, expected: $0["expected"]!) }
    }

    /// 逐条复算并比较（JSON 结构深比较，忽略键序与数值的整数 / 浮点写法）。
    static func assertVectors(_ name: String, kinds: Set<String>, _ run: (Vector) throws -> Any, file: StaticString = #filePath, line: UInt = #line) throws {
        let all = try vectors(name)
        let picked = all.filter { kinds.contains($0.kind) }
        if picked.isEmpty {
            throw NSError(domain: "contract", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(name) 里没有 \(kinds.sorted()) 的向量"])
        }
        let missing = kinds.subtracting(Set(picked.map(\.kind)))
        if !missing.isEmpty {
            throw NSError(domain: "contract", code: 3, userInfo: [NSLocalizedDescriptionKey: "\(name) 缺少 kind：\(missing.sorted())"])
        }
        var failures: [String] = []
        for v in picked {
            let got = try run(v)
            if !jsonEqual(got, v.expected) {
                failures.append("\(v.kind)  expected=\(compact(v.expected))  actual=\(compact(got))")
            }
        }
        if !failures.isEmpty {
            throw NSError(domain: "contract", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "\(name)：\(failures.count)/\(picked.count) 条不符\n" + failures.joined(separator: "\n"),
            ])
        }
    }

    private static func compact(_ v: Any) -> String {
        // 顶层是标量时 JSONSerialization 会抛（不是合法的顶层类型），文本里夹带的引号也会被顺手转义成 `\"`；
        // 错误信息只是给人看的，改用 `String(describing:)`。
        let s = String(describing: v)
        return s.count > 160 ? String(s.prefix(160)) + "…" : s
    }
}

/// JSON 结构深比较：数字按值比（`1` 与 `1.0` 相等），对象忽略键序，数组保序。
func jsonEqual(_ a: Any, _ b: Any) -> Bool {
    if let na = a as? NSNumber, let nb = b as? NSNumber, !isBool(na), !isBool(nb) {
        return na.doubleValue == nb.doubleValue
    }
    if let sa = a as? String, let sb = b as? String { return sa == sb }
    if let ba = a as? Bool, let bb = b as? Bool { return ba == bb }
    if a is NSNull, b is NSNull { return true }
    if let da = a as? [String: Any], let db = b as? [String: Any] {
        if da.count != db.count { return false }
        for (k, v) in da { guard let w = db[k], jsonEqual(v, w) else { return false } }
        return true
    }
    if let la = a as? [Any], let lb = b as? [Any] {
        if la.count != lb.count { return false }
        for i in la.indices where !jsonEqual(la[i], lb[i]) { return false }
        return true
    }
    return false
}

private func isBool(_ n: NSNumber) -> Bool { CFGetTypeID(n) == CFBooleanGetTypeID() }