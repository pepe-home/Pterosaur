// 侧栏：玻璃背景（`NavigationSplitView` 在 Liquid Glass 下自带材质），搜索入口 + 发现 + 资料库，
// 底部账户入口浮在侧栏底部（`.safeAreaInset`），不写侧栏自己的底色。
import PterosaurCore
import SwiftUI

struct Sidebar: View {
    @ObservedObject var state: AppState
    @Binding var showingAccount: Bool

    @State private var keyword = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        List(selection: Binding(get: { state.route }, set: { state.reset(to: $0) })) {
            Section {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索歌曲、专辑、艺人", text: $keyword)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onSubmit {
                            let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !q.isEmpty else { return }
                            state.open(.search(query: q))
                        }
                }
                .padding(.vertical, 3)
            }
            Section("发现") {
                Label("新发现", systemImage: "sparkles").tag(Route.discover)
                Label("排行榜", systemImage: "list.number").tag(Route.topLists)
            }
            Section("资料库") {
                Label("最近播放", systemImage: "clock").tag(Route.recent)
                Label("我喜欢的音乐", systemImage: "heart").tag(Route.favorites)
                Label("歌单与磁带", systemImage: "music.note.list").tag(Route.savedPlaylists)
                Label("艺人", systemImage: "music.mic").tag(Route.savedArtists)
                Label("专辑", systemImage: "square.stack").tag(Route.savedAlbums)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button {
                showingAccount = true
            } label: {
                HStack(spacing: 9) {
                    Group {
                        if let avatar = state.account.status.avatarUrl, !avatar.isEmpty {
                            RemoteImage(url: avatar, corner: 11).frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.account.status.logged ? (state.account.status.nickname ?? "已登录") : "登录网易云")
                            .lineLimit(1)
                        Text(state.account.status.logged ? (state.account.status.vip ? "VIP 会员" : "已绑定账号") : "扫码或粘贴 Cookie")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "gearshape").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .onAppear { searchFocused = false }
    }
}
