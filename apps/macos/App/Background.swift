// 应用背景：一层随主题的柔和渐变 + 详情页代表色，作为玻璃的「底」——玻璃要有可折射的东西才成立。
//
// 代表色来自 `hooks/useArtColor` 的网络端同款思路的轻量版：取当前播放曲封面主色（Core 之外的小工具），
// 换曲时平滑过渡；没有播放时回落到品牌色。
import AppKit
import PterosaurCore
import SwiftUI

/// 全局背景（挂在根视图最底层，内容与玻璃都在它上面）。
struct AppBackground: View {
    var artColor: Color?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(
                colors: [(artColor ?? Color.accentColor).opacity(0.35), .clear],
                center: .topLeading, startRadius: 10, endRadius: 720)
            RadialGradient(
                colors: [(artColor ?? Color.pink).opacity(0.22), .clear],
                center: .bottomTrailing, startRadius: 10, endRadius: 640)
        }
        .animation(.easeInOut(duration: 0.9), value: artColor)
        .ignoresSafeArea()
    }
}

/// 从封面取一个低饱和的代表色（按主色相微调明度，避免刺眼）。
@MainActor
final class ArtColorLoader: ObservableObject {
    @Published private(set) var color: Color?
    private var key: String?
    private var cache: [String: Color] = [:]

    func load(cover: String?) {
        guard let cover, !cover.isEmpty else { color = nil; key = nil; return }
        guard cover != key else { return }
        key = cover
        if let hit = cache[cover] { color = hit; return }
        Task.detached(priority: .utility) {
            let c = Self.dominant(from: cover)
            await MainActor.run {
                if let c { self.cache[cover] = c }
                if self.key == cover { self.color = c }
            }
        }
    }

    /// 缩到 32px 统计像素：跳过近白 / 近黑与低饱和像素，取出现最多的色相分桶的中位色。
    nonisolated private static func dominant(from url: String) -> Color? {
        guard let u = URL(string: url),
              let data = try? Data(contentsOf: u),
              let img = NSImage(data: data),
              let rep = NSBitmapImageRep(data: img.tiffRepresentation ?? Data()) else { return nil }
        var buckets: [Int: [(Int, Int, Int)]] = [:]
        let w = rep.pixelsWide, h = rep.pixelsHigh
        let step = max(1, min(w, h) / 32)
        for y in stride(from: 0, to: h, by: step) {
            for x in stride(from: 0, to: w, by: step) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let r = Int(c.redComponent * 255), g = Int(c.greenComponent * 255), b = Int(c.blueComponent * 255)
                let mx = max(r, g, b), mn = min(r, g, b)
                if mx > 235 || mn < 20 || mx - mn < 28 { continue }
                buckets[(r / 32) * 64 + (g / 32) * 8 + (b / 32), default: []].append((r, g, b))
            }
        }
        guard let (_, pixels) = buckets.max(by: { $0.value.count < $1.value.count }), !pixels.isEmpty else { return nil }
        let n = pixels.count
        let r = pixels.reduce(0) { $0 + $1.0 } / n, g = pixels.reduce(0) { $0 + $1.1 } / n, b = pixels.reduce(0) { $0 + $1.2 } / n
        return Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}
