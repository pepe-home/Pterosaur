// macOS 应用入口（SwiftUI + Liquid Glass，ADR-064）：原生端自带内核，无 server 也能用。
// UI 层不直接发网络请求——所有上游调用都经 PterosaurCore。
import SwiftUI

@main
struct PterosaurApp: App {
    init() {
        HostPorts.install()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)
    }
}