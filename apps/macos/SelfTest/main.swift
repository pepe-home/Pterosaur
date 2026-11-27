// 自测入口：`swift run selftest`（CI 的 macOS job 用这个；见 apps/macos/AGENTS.md）。
import Foundation
import PterosaurTestSupport

@main
struct SelfTestMain {
    static func main() {
        let failed = SelfTest.runAll()
        if failed > 0 { exit(1) }
    }
}
