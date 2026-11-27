// 应用级状态容器：模型之间互相依赖，集中在这里组装一次；导航栈也在这里（卡片 / 行内链接统一 push）。
import Foundation
import PterosaurCore
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    let library = Library()
    let account = Account()
    let queue = Queue()
    let player = Player()
    lazy var playback = PlaybackController(queue: queue, player: player, library: library, account: account)

    /// 详情区导航栈（侧栏切换分区时清空）。
    @Published var path: [Route] = []

    func open(_ route: Route) { path.append(route) }

    func reset(to route: Route) {
        path.removeAll()
        self.route = route
    }

    /// 侧栏当前分区。
    @Published var route: Route = .discover
}
