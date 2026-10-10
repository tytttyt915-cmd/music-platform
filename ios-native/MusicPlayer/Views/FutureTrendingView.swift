import SwiftUI

// MARK: - FutureTrendingView（v4.2）
//
// 未来飙升榜：TimesFM 智能预测 7 天后热度，按 0.7 分位数（乐观预测）排序。
// 这是"多平台聚合 + 智能预测 + iOS 原生"定位里竞品没有的那一块：
// 榜单展示的不是现在火什么，而是 AI 预测未来 7 天会火什么。
//
// 数据源：GET /music/trending-future
//   - fallback=false：走了 TimesFM 真预测，行内显示"AI 预测 ↑35%"趋势
//   - fallback=true：后端降级为按播放量排序，顶部显示降级提示条

struct FutureTrendingView: View {
    @EnvironmentObject private var music: MusicService
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var theme: ThemeSettings

    @State private var items: [TrendingSong] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var isFallback = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            AppleTheme.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 0) {
                    // 榜单说明头
                    headerCard
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    if isFallback && !items.isEmpty {
                        fallbackBanner
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                    }

                    if isLoading && items.isEmpty {
                        LoadingStateView()
                    } else if items.isEmpty {
                        EmptyStateView(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "暂无预测数据",
                            subtitle: "下拉刷新试试"
                        )
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            Button {
                                let songs = items.map { $0.song }
                                player.playOnlineSongs(songs, startAt: idx)
                            } label: {
                                trendingRow(rank: idx + 1, item: item)
                            }
                            .pressable()
                            .padding(.horizontal, 12)
                            .onAppear {
                                if idx == items.count - 1 { loadMore() }
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
            .refreshable { await reload() }

            if let errorMessage {
                ErrorBanner(message: errorMessage)
                    .padding(.top, 8)
                    .zIndex(1)
            }
        }
        .navigationTitle("未来飙升榜")
        .navigationBarTitleDisplayMode(.large)
        .task { await reload() }
    }

    // MARK: - 榜单说明头

    private var headerCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(theme.accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("AI 预测未来 7 天")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(AppleTheme.label)
                    Text("AI 预测")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.accentColor.opacity(0.15))
                        .foregroundColor(theme.accentColor)
                        .clipShape(Capsule())
                }
                Text("TimesFM 时序模型 · 按爆发潜力排序")
                    .font(.caption)
                    .foregroundColor(AppleTheme.secondaryLabel)
            }
            Spacer()
        }
        .padding(12)
        .liquidGlassLight(cornerRadius: 16)
    }

    private var fallbackBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.orange)
            Text("预测服务暂不可用，当前按播放量排序")
                .font(.caption)
                .foregroundColor(AppleTheme.secondaryLabel)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 榜单行

    private func trendingRow(rank: Int, item: TrendingSong) -> some View {
        HStack(spacing: 12) {
            // 排名
            Text("\(rank)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(rankColor(rank))
                .frame(width: 28, alignment: .center)

            coverArt(url: item.song.coverURL, size: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.song.title)
                    .font(.body)
                    .foregroundColor(AppleTheme.label)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(item.song.artist) · \(formatDuration(item.song.duration))")
                        .font(.body)
                        .foregroundColor(AppleTheme.secondaryLabel)
                        .lineLimit(1)
                    // 趋势角标：只有真预测且上升才显示
                    if let rising = item.risingText {
                        Text(rising)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                }
            }
            Spacer()

            // 预测播放量（CountUp 数字滚动）
            if let predicted = item.predicted7d, item.isPredicted {
                VStack(alignment: .trailing, spacing: 2) {
                    CountUp(target: predicted)
                        .font(.caption)
                        .foregroundColor(theme.accentColor)
                    Text("预测播放")
                        .font(.caption)
                        .foregroundColor(AppleTheme.tertiaryLabel)
                }
            } else if player.currentTrack?.onlineSongId == item.song.id && player.isPlaying {
                EqualizerBars(isPlaying: true, color: theme.accentColor)
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppleTheme.tertiaryLabel)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.45, blue: 0.2)   // 冠军橙
        case 2: return Color(red: 1.0, green: 0.65, blue: 0.2)
        case 3: return Color(red: 0.95, green: 0.75, blue: 0.3)
        default: return AppleTheme.tertiaryLabel
        }
    }

    // MARK: - 数据

    private func reload() async {
        page = 1
        hasMore = true
        await fetch(reset: true)
    }

    private func loadMore() {
        guard hasMore && !isLoading else { return }
        page += 1
        Task { await fetch(reset: false) }
    }

    private func fetch(reset: Bool) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await music.trendingFuture(page: page, pageSize: 20)
            await MainActor.run {
                if reset {
                    items = result.items
                } else {
                    items.append(contentsOf: result.items)
                }
                hasMore = result.hasMore
                isFallback = result.fallback
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                if reset { items = [] }
                errorMessage = "加载失败：\(error.localizedDescription)"
            }
        }
    }
}
