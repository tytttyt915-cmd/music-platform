import SwiftUI

// MARK: - DailyRecommendView（v4.3）
//
// 每日推荐：取 music.feed 前 30 首当今日精选（对标 Beans「30 首 · 每天 6:00 更新」）。
// 后端如上线专属每日推荐接口，可替换 load() 内的数据源。
//
// 工具规则：
// [Beans#5] 当前信息最大化不适用此处；列表沿用 SongRow（48pt 封面 + 标题/歌手）
// [三铁律①] 行点击 .pressable() 按压反馈

struct DailyRecommendView: View {
    @EnvironmentObject private var music: MusicService
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var theme: ThemeSettings

    @State private var songs: [OnlineSong] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppleTheme.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 0) {
                    header
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 8)

                    if isLoading && songs.isEmpty {
                        LoadingStateView()
                    } else if songs.isEmpty {
                        EmptyStateView(
                            icon: "calendar",
                            title: "暂无推荐",
                            subtitle: "下拉刷新试试"
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
                        }
                    }
                }
            }
            .refreshable { await load() }
        }
        .navigationTitle("每日推荐")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("为你精选 30 首")
                    .font(.headline)
                    .foregroundColor(AppleTheme.label)
                Text("每天 6:00 更新")
                    .font(.caption)
                    .foregroundColor(AppleTheme.secondaryLabel)
            }
            Spacer()
            Button {
                player.playOnlineSongs(songs, startAt: 0)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(theme.accentColor, in: Circle())
            }
            .pressable()
            .disabled(songs.isEmpty)
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await music.feed(page: 1, pageSize: 30)
            songs = result.items
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
