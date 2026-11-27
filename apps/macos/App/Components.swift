// 通用小组件：歌曲行、封面卡、播放条。
import PterosaurCore
import SwiftUI

struct SongRow: View {
    let track: Track
    let playing: Bool
    let favorite: Bool
    let onToggleFavorite: () -> Void
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            RemoteImage(url: track.cover, corner: 5).frame(width: 36, height: 36)
                .overlay { if playing { Circle().fill(.black.opacity(0.35)).frame(width: 18, height: 18)
                    Image(systemName: "waveform").font(.caption2).foregroundStyle(.white) } }
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).lineLimit(1)
                    .foregroundStyle(playing ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if track.duration > 0 {
                Text(track.duration.formattedDuration).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Button(action: onToggleFavorite) {
                Image(systemName: favorite ? "heart.fill" : "heart")
                    .foregroundStyle(favorite ? .red : .secondary)
            }
            .buttonStyle(.borderless)
            .help("我喜欢")
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onPlay)
        .padding(.vertical, 2)
    }
}

/// 封面卡：歌单 / 专辑 / 艺人 / 磁带（磁带 16:9，见 ADR-044）。
struct CoverCard<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let cover: String
    let wide: Bool
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: cover, corner: 8)
                .aspectRatio(wide ? 16.0 / 9.0 : 1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) { trailing.padding(6) }
            Text(title).font(.callout).lineLimit(1)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

extension CoverCard where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, cover: String, wide: Bool = false) {
        self.init(title: title, subtitle: subtitle, cover: cover, wide: wide) { EmptyView() }
    }
}

struct PlayButton: View {
    var playing: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 44, height: 44)
                .background(.tint, in: Circle())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
    }
}

struct ErrorState: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.secondary)
            Text(message).foregroundStyle(.secondary)
            if let retry { Button("重试", action: retry) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyState: View {
    let text: String
    var body: some View {
        Text(text).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Int {
    /// 秒 → `m:ss` / `h:mm:ss`。
    var formattedDuration: String {
        let total = Swift.max(0, self)
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
