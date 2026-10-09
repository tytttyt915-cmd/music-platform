import SwiftUI

// MARK: - DiscoverView（2026-10-09 Apple 原生风重做）
//
// 职责：发现页。
//   - 原生 .searchable 搜索框；有关键字 → music.search，无关键字 → music.feed
//   - 歌曲行用 SongRow（48pt 封面 + 标题/歌手）；点击播放整单
//   - 分页：到底自动加载（hasMore）；下拉刷新
//   - 错误用顶部浮条提示，3 秒自动消失

struct DiscoverView: View {
    @EnvironmentObject private var music: MusicService
    @EnvironmentObject private var player: AudioPlayerManager

    @State private var keyword = ""
    @State private var songs: [OnlineSong] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isSearchMode: Bool { !keyword.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack(alignment: .top) {
            AppleTheme.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 0) {
                    if isLoading && songs.isEmpty {
                        LoadingStateView()
                    } else if songs.isEmpty {
                        EmptyStateView(
                            icon: isSearchMode ? "magnifyingglass" : "music.note",
                            title: isSearchMode ? "没有找到相关歌曲" : "暂无推荐",
                            subtitle: isSearchMode ? "换个关键词试试" : "下拉刷新试试"
                        )
                    } else {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { idx, song in
                            Button {
                                player.playOnlineSongs(songs, startAt: idx)
                            } label: {
                                SongRow(
                                    song: song,
                                    isPlaying: player.currentTrack?.onlineSongId == song.id && player.isPlaying
                                )
                            }
                            .pressable()
                            .padding(.horizontal, 12)
                            .onAppear {
                                if idx == songs.count - 1 { loadMore() }
                            }
                            Divider()
                                .padding(.leading, 64)
                        }
                        if isLoading {
                            ProgressView()
                                .padding(.vertical, 16)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable { reload() }

            if let errorMessage {
                ErrorBanner(message: errorMessage)
                    .padding(.top, 8)
                    .zIndex(1)
            }
        }
        .navigationTitle(isSearchMode ? "搜索" : "发现")
        .searchable(text: $keyword, prompt: "搜索歌曲、歌手、专辑")
        .onSubmit(of: .search) { reload() }
        .onChange(of: keyword) { newValue in
            if newValue.isEmpty { reload() }
        }
        .task { reload() }
    }

    // MARK: - 数据

    private func reload() {
        page = 1
        hasMore = true
        songs = []
        errorMessage = nil
        fetch()
    }

    private func loadMore() {
        guard hasMore, !isLoading else { return }
        page += 1
        fetch()
    }

    private func fetch() {
        guard !isLoading else { return }
        isLoading = true
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        let p = page
        Task {
            do {
                let result: PagedResult<OnlineSong>
                if kw.isEmpty {
                    result = try await music.feed(page: p)
                } else {
                    result = try await music.search(keyword: kw, page: p)
                }
                await MainActor.run {
                    if p == 1 {
                        songs = result.items
                    } else {
                        songs.append(contentsOf: result.items)
                    }
                    hasMore = result.hasMore
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    showError("加载失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                withAnimation(.appleDefault) { errorMessage = nil }
            }
        }
    }
}
