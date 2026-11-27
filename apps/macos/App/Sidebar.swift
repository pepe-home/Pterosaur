// 侧栏：搜索入口 + 发现 + 资料库 + 底部的账户 / 主题入口（底部单独分区）。
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
        .safeAreaInset(edge: .bottom) {
            Button {
                showingAccount = true
            } label: {
                HStack(spacing: 8) {
                    if let avatar = state.account.status.avatarUrl, !avatar.isEmpty {
                        RemoteImage(url: avatar, corner: 10).frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "person.crop.circle").font(.title3).foregroundStyle(.secondary)
                    }
                    Text(state.account.status.logged ? "\(state.account.status.nickname ?? "已登录") \(state.account.status.vip ? "VIP" : "")" : "登录网易云")
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "gearshape").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .onAppear { searchFocused = false }
    }
}
