import SwiftUI

// Views 适配（2026-10-09）：老搜索接口 → MusicService.search（返回 PagedResult，取 items）
struct DiscoverView: View {
    @EnvironmentObject var music: MusicService
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var theme: ThemeSettings
    @State private var keyword = ""
    @State private var results: [OnlineSong] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
                Text("发现")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)
            VStack(spacing: 0) {
                // 搜索栏
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(theme.secondaryTextColor)
                    TextField("搜索歌曲、歌手", text: $keyword, onCommit: search)
                        .textFieldStyle(.plain)
                    if !keyword.isEmpty {
                        Button { keyword = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(theme.secondaryTextColor)
                        }
                    }
                }
                .padding(10)
                .background((Color.gray as Color).opacity(0.15))
                .cornerRadius(10)
                .padding()
                
                if isSearching {
                    ProgressView()
                        .padding()
                } else if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                } else if results.isEmpty && !keyword.isEmpty {
                    Text("无搜索结果")
                        .foregroundColor(theme.secondaryTextColor)
                        .padding()
                } else {
                    List(results) { song in
                        Button {
                            if let idx = results.firstIndex(where: { $0.id == song.id }) {
                                player.playOnlineSongs(results, startAt: idx)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(song.title)
                                        .foregroundColor(theme.textColor)
                                        .lineLimit(1)
                                    Text("\(song.artist) · \(song.album)")
                                        .font(.caption)
                                        .foregroundColor(theme.secondaryTextColor)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                        }
                    }
                    .listStyle(.plain)
                }
                Spacer()
            }
            
            
            .background(Color.clear)
        }
    }
    
    private func search() {
        guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        errorMessage = nil
        Task {
            do {
                let page = try await music.search(keyword: keyword)
                await MainActor.run {
                    results = page.items
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "搜索失败：\(error.localizedDescription)"
                    isSearching = false
                }
            }
        }
    }
}
