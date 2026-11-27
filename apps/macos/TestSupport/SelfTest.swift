// 自测入口的用例清单（被 `PterosaurSelfTest` 可执行 target 调用）。
//
// 之所以自带一个入口而不是 `swift test`：本仓只在 Xcode 命令行工具（CLT）下构建，
// CLT 不带 XCTest，`swift test` 在 CLT 机器上根本无法编译测试 target。
import Foundation
import PterosaurCore

public enum SelfTest {
    /// 跑全部用例；返回失败条数（0 即全过）。每条用例的名字与失败详情打到标准输出。
    public static func runAll() -> Int {
        let cases: [(String, () throws -> Void)] = [
            ("contract.encoding", ContractCases.encodingVectors),
            ("contract.digest", ContractCases.digestVectors),
            ("contract.aes", ContractCases.aesVectors),
            ("contract.sign", ContractCases.signVectors),
            ("contract.normalize", ContractCases.normalizeVectors),
            ("contract.entity", ContractCases.entityVectors),
            ("contract.url", ContractCases.urlVectors),
            ("contract.lyric", ContractCases.lyricVectors),
            ("golden", { if GoldenObserved.run() > 0 { throw SelfTestFailure("golden 快照不符") } }),
            ("netease.pure", NeteasePureCases.run),
            ("bilibili.pure", BilibiliPureCases.run),
            ("bilibili.transport", BilibiliTransportCases.run),
        ]
        var failed = 0
        for (name, body) in cases {
            do {
                try body()
                print("ok    \(name)")
            } catch {
                failed += 1
                print("FAIL  \(name)\n      \(message(of: error).replacingOccurrences(of: "\n", with: "\n      "))")
            }
        }
        print(failed == 0 ? "全部 \(cases.count) 组通过" : "\(failed)/\(cases.count) 组失败")
        return failed
    }

    private static func message(of error: Error) -> String {
        if let e = error as? SelfTestFailure { return e.text }
        let ns = error as NSError
        return ns.domain == "contract" || ns.domain == "golden" ? (ns.userInfo[NSLocalizedDescriptionKey] as? String ?? "\(error)") : "\(error)"
    }
}

/// 断言失败（自测里最常用的一种）。
public struct SelfTestFailure: Error {
    public let text: String
    public init(_ text: String) { self.text = text }
}

/// 相等断言：不符即抛。
public func expectEqual<T: Equatable>(_ got: T, _ want: T, _ what: String) throws {
    if got != want { throw SelfTestFailure("\(what)：期望 \(want)，实际 \(got)") }
}

/// 真值断言。
public func expect(_ cond: Bool, _ what: String) throws {
    if !cond { throw SelfTestFailure(what) }
}
