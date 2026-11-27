// 宿主端口注入：原生端没有服务端，网络与设备身份在应用启动时装进 Core（ADR-064 / ADR-066）。
import Foundation
import PterosaurCore

enum HostPorts {
    /// 应用启动时调用一次（`PterosaurApp.init` 之前）。可重复调用。
    static func install() {
        fetcher = ByteTransport()
        // 设备身份走 ADR-053 的纯算法（待落地）。未接上之前保持 Core 的空身份：扫码 801 / 802 阶段
        // 不受影响，手机确认后会命中 8821 设备风控，届时重开弹窗即可。
    }
}
