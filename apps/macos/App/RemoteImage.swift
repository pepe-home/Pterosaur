// 封面 / 头像：按 URL 加载并做内存缓存（网易云封面已由 Core 规范化为稳定地址，可安全以 URL 为键）。
import SwiftUI

@MainActor
private final class ImageCache {
    static let shared = ImageCache()
    private var images: [String: NSImage] = [:]

    func image(_ url: String) async -> NSImage? {
        if let hit = images[url] { return hit }
        guard let u = URL(string: url) else { return nil }
        let (data, _) = (try? await URLSession.shared.data(from: u)) ?? (nil, nil)
        guard let data, let img = NSImage(data: data) else { return nil }
        images[url] = img
        return img
    }
}

struct RemoteImage: View {
    let url: String
    var corner: CGFloat = 6

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: corner)
                    .fill(.quaternary)
                    .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .task(id: url) { image = await ImageCache.shared.image(url) }
    }
}
