// 主界面：搜索 → 曲目列表（数据经 PterosaurCore 的接口与归一化）。
import PterosaurCore
import SwiftUI

struct ContentView: View {
    @StateObject private var model = SearchModel()
    @State private var keyword = ""

    var body: some View {
        NavigationSplitView {
            List {
                Section("资料库") {
                    Label("最近播放", systemImage: "clock")
                    Label("我喜欢的音乐", systemImage: "heart")
                    Label("本地歌单", systemImage: "music.note.list")
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索歌曲、专辑、艺人", text: $keyword)
                        .textFieldStyle(.plain)
                        .onSubmit { model.search(keyword) }
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding()

                switch model.state {
                case .idle:
                    Spacer(); Text("输入关键词开始搜索").foregroundStyle(.secondary); Spacer()
                case .loading:
                    Spacer(); ProgressView(); Spacer()
                case let .failed(message):
                    Spacer(); Text(message).foregroundStyle(.secondary); Spacer()
                case let .done(tracks):
                    if tracks.isEmpty {
                        Spacer(); Text("没有结果").foregroundStyle(.secondary); Spacer()
                    } else {
                        List(tracks, id: \.id) { track in
                            TrackRow(track: track)
                        }
                        .listStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct TrackRow: View {
    let track: Track

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).lineLimit(1)
                Text("\(track.artist) — \(track.album)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if track.fee == "vip" {
                Text("VIP").font(.caption2).foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 搜索状态与请求（调用 PterosaurCore）。
@MainActor
final class SearchModel: ObservableObject {
    enum State {
        case idle, loading
        case done([Track])
        case failed(String)
    }

    @Published var state: State = .idle

    func search(_ keyword: String) {
        let k = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        state = .loading
        Task.detached {
            let result: State
            do {
                let res = cloudsearch(keywords: k, limit: 30)
                guard let body = res.body as? [String: Any],
                      let resultObj = body["result"] as? [String: Any],
                      let songs = resultObj["songs"] as? [[String: Any]] else {
                    await MainActor.run { self.state = .done([]) }
                    return
                }
                result = .done(songs.map { normalizeTrack($0) })
            } catch {
                result = .failed("\(error)")
            }
            await MainActor.run { self.state = result }
        }
    }
}