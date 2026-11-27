// swift-tools-version: 6.0
import PackageDescription

// macOS 端（ADR-066）：Core 是引擎无关的纯 Swift 协议层，App 是 SwiftUI 外壳。
// 自测跑在 `PterosaurSelfTest` 可执行 target 上（不用 XCTest：本仓只在 Xcode 命令行工具下构建，
// CLT 不带 XCTest，`swift test` 在 CLT 机器上编译不过）。
let package = Package(
    name: "Pterosaur",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PterosaurCore", targets: ["PterosaurCore"]),
        .executable(name: "Pterosaur", targets: ["PterosaurApp"]),
        .executable(name: "selftest", targets: ["PterosaurSelfTest"]),
    ],
    targets: [
        // 协议层：不得依赖 SwiftUI / AVFoundation / WebKit。
        // 不列 linkerSettings：CommonCrypto 与 Security 都是 SDK 的模块，`import` 即由 clang 自动链接
        // （显式 `-lcommonCrypto` 反而会去找命令行工具链里不存在的 tbd / framework）。
        .target(
            name: "PterosaurCore",
            path: "Core/Sources"
        ),
        // 外壳：只依赖 Core 的公开接口
        .executableTarget(
            name: "PterosaurApp",
            dependencies: ["PterosaurCore"],
            path: "App"
        ),
        // 自测用例：读 ../../packages/contract/**（ADR-069），不得复制样例；
        // 黄金快照夹具（fixtures/golden-observed.json）是本端输出，随实现更新。
        .target(
            name: "PterosaurTestSupport",
            dependencies: ["PterosaurCore"],
            path: "TestSupport",
            // 夹具按源码位置读取（见 Contract.fixtures），不经 Bundle 资源
            exclude: ["Fixtures"]
        ),
        .executableTarget(
            name: "PterosaurSelfTest",
            dependencies: ["PterosaurTestSupport"],
            path: "SelfTest"
        ),
    ]
)
