// 通用小组件：歌曲行、封面卡、主按钮、空 / 错误态（Liquid Glass 外壳，见 ADR-070）。
//
// 设计取向（仿 Apple Music 的分层，而不是「一堆卡片」）：
// - 内容层（列表、封面）铺在背景上，不套玻璃；可交互的浮动元素（主操作按钮、悬浮控制）才用玻璃。
// - 颜色只用于传达状态：正在播放用强调色，收藏用心形红，其余交给层级与字重。
import PterosaurCore
import SwiftUI

struct SongRow: View {
    let track: Track
    let playing: Bool
    let favorite: Bool
    let onToggleFavorite: () -> Void
    let onPlay: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: track.cover, corner: 6).frame(width: 40, height: 40)
                .overlay {
                    if hovering || playing {
                        RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.35))
                        Image(systemName: playing ? "speaker.wave.2.fill" : "play.fill")
                            .font(.caption).foregroundStyle(.white)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).lineLimit(1).fontWeight(playing ? .semibold : .regular)
                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if track.duration > 0 {
                Text(track.duration.formattedDuration)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button(action: onToggleFavorite) {
                Image(systemName: favorite ? "heart.fill" : "heart")
                    .foregroundStyle(favorite ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .opacity(favorite || hovering ? 1 : 0.35)
            .help("我喜欢")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onPlay)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.title)，\(track.artist)")
    }
}

/// 封面卡：歌单 / 专辑 / 艺人 / 磁带（磁带 16:9，见 ADR-044）。
/// 悬停时封面微微抬起并透出一枚玻璃播放钮——「可以播放」这件事用 affordance 表达，不写提示文字。
struct CoverCard<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let cover: String
    let wide: Bool
    var onPlay: (() -> Void)?
    @ViewBuilder var trailing: Trailing
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RemoteImage(url: cover, corner: 10)
                .aspectRatio(wide ? 16.0 / 9.0 : 1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(hovering ? 0.28 : 0.14), radius: hovering ? 14 : 8, y: hovering ? 8 : 4)
                .scaleEffect(hovering ? 1.02 : 1)
                .overlay(alignment: .bottomTrailing) {
                    if let onPlay {
                        Button(action: onPlay) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 38, height: 38)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .padding(10)
                        .opacity(hovering ? 1 : 0)
                        .scaleEffect(hovering ? 1 : 0.85)
                    }
                }
                .overlay(alignment: .topTrailing) { trailing.padding(8) }
            Text(title).font(.callout.weight(.medium)).lineLimit(1)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.22), value: hovering)
    }
}

extension CoverCard where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, cover: String, wide: Bool = false, onPlay: (() -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, cover: cover, wide: wide, onPlay: onPlay) { EmptyView() }
    }
}

/// 主操作（播放 / 播放全部）：玻璃底 + 强调色，是全页唯一「发光」的控件。
struct PrimaryActionButton: View {
    var title: String
    var symbol: String = "play.fill"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
    }
}

/// 圆形玻璃图标按钮（播放控制用；尺寸随图标）。
struct GlassIconButton: View {
    var symbol: String
    var size: CGFloat = 34
    var prominent = false
    var help: String = ""
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .glassEffect(prominent ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .circle)
        .help(help)
    }
}

struct ErrorState: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34)).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let retry {
                Button("重试", action: retry).buttonStyle(.glassProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyState: View {
    let text: String
    var symbol = "music.note"
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 34)).symbolRenderingMode(.hierarchical).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
