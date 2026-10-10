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
    @EnvironmentObject private var theme: ThemeSettings

    @State private var keyword = ""
    @State private var songs: [OnlineSong] = []
    @State private var platformSongs: [PlatformTrack] = []
    /// 后端启用的平台（platformEnabled）：含付费平台，仅后端配置 Key 时出现
    @State private var enabledPlatforms: [String] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var sourceSwitchSong: OnlineSong?

    private var isSearchMode: Bool { !keyword.trimmingCharacters(in: .whitespaces).isEmpty }

    /// 平台结果按平台分组（网易云/QQ/酷狗/付费音源各一段），固定顺序
    private var groupedPlatformSongs: [(platform: String, songs: [PlatformTrack])] {
        let grouped = Dictionary(grouping: platformSongs, by: { $0.platform })
        let order = ["netease", "qq", "kugou", "wy", "kg", "kw", "mg", "tx"]
        return grouped.keys.sorted {
            let a = order.firstIndex(of: $0) ?? Int.max
            let b = order.firstIndex(of: $1) ?? Int.max
            return a < b
        }.map { ($0, grouped[$0] ?? []) }
    }

    /// 已启用的付费平台（换源菜单用；无 Key 时为空，菜单不显示）
    private var enabledPaidPlatforms: [String] {
        enabledPlatforms.filter { PlatformTrack.paidPlatforms.contains($0) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppleTheme.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 0) {
                    // v4.2 功能入口（仅非搜索模式）：未来飙升榜 / 歌单导入
                    if !isSearchMode {
                        featureEntries
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                    }
                    if isLoading && songs.isEmpty && platformSongs.isEmpty {
                        LoadingStateView()
                    } else if songs.isEmpty && platformSongs.isEmpty {
                        EmptyStateView(
                            icon: isSearchMode ? "magnifyingglass" : "music.note",
                            title: isSearchMode ? "没有找到相关歌曲" : "暂无推荐",
                            subtitle: isSearchMode ? "换个关键词试试" : "下拉刷新试试"
                        )
                    } else {
                        // 本地结果
                        if !songs.isEmpty {
                            if isSearchMode {
                                sectionHeader("本地曲库", count: songs.count)
                            }
                            ForEach(Array(songs.enumerated()), id: \.element.id) { idx, song in
                                Button {
                                    // v4.2 封面飞进播放页：先登记飞行 id 让行封面配对，
                                    // 下一 runloop 再打开播放页，hero 转场从 cell 飞到大封面
                                    player.coverFlySongID = song.id
                                    player.playOnlineSongs(songs, startAt: idx)
                                    DispatchQueue.main.async {
                                        player.showFullPlayer = true
                                    }
                                } label: {
                                    SongRow(
                                        song: song,
                                        isPlaying: player.currentTrack?.onlineSongId == song.id && player.isPlaying
                                    )
                                }
                                .pressable()
                                .contextMenu {
                                    Button {
                                        sourceSwitchSong = song
                                    } label: {
                                        Label("换源", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                }
                                .padding(.horizontal, 12)
                                .onAppear {
                                    if idx == songs.count - 1 { loadMore() }
                                }
                                Divider()
                                    .padding(.leading, 64)
                            }
                        }
                        // 平台结果（网易云/QQ/酷狗/付费音源）：仅搜索模式，按平台分组
                        if isSearchMode && !platformSongs.isEmpty {
                            ForEach(groupedPlatformSongs, id: \.platform) { group in
                                sectionHeader(
                                    PlatformTrack.displayName(for: group.platform),
                                    count: group.songs.count
                                )
                                ForEach(Array(group.songs.enumerated()), id: \.element.id) { idx, song in
                                    // 在分组内的序号 → 映射回 platformSongs 全局序号，保证队列顺序
                                    let globalIdx = platformSongs.firstIndex(of: song) ?? 0
                                    Button {
                                        player.playPlatformTracks(platformSongs, startAt: globalIdx)
                                    } label: {
                                        PlatformSongRow(
                                            song: song,
                                            isPlaying: player.currentTrack?.platform == song.platform
                                                && player.currentTrack?.title == song.title
                                                && player.isPlaying
                                        )
                                    }
                                    .pressable()
                                    .padding(.horizontal, 12)
                                    // 付费音源换源：长按选平台（仅后端配置 Key 时显示）
                                    .contextMenu {
                                        if !enabledPaidPlatforms.isEmpty {
                                            ForEach(enabledPaidPlatforms, id: \.self) { paid in
                                                Button {
                                                    player.playPlatformTracks(
                                                        platformSongs,
                                                        startAt: globalIdx,
                                                        via: paid
                                                    )
                                                } label: {
                                                    Label(
                                                        "用\(PlatformTrack.displayName(for: paid))播放",
                                                        systemImage: "arrow.triangle.2.circlepath"
                                                    )
                                                }
                                            }
                                        }
                                    }
                                    Divider()
                                        .padding(.leading, 64)
                                }
                            }
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
        .sheet(item: $sourceSwitchSong) { song in
            SourceSwitchView(song: song)
        }
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
        platformSongs = []
        enabledPlatforms = []
        errorMessage = nil
        fetch()
    }

    private func loadMore() {
        guard hasMore, !isLoading else { return }
        page += 1
        fetch()
    }

    // MARK: - v4.2 功能入口

    /// 未来飙升榜 / 歌单导入：横向双卡片
    private var featureEntries: some View {
        HStack(spacing: 12) {
            NavigationLink {
                FutureTrendingView()
            } label: {
                featureCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "未来飙升榜",
                    subtitle: "AI 预测 7 天热歌",
                    badge: "AI 预测"
                )
            }
            .pressable()

            NavigationLink {
                PlaylistImportView()
            } label: {
                featureCard(
                    icon: "square.and.arrow.down.on.square",
                    title: "歌单导入",
                    subtitle: "网易云/QQ 一键搬家",
                    badge: nil
                )
            }
            .pressable()
        }
    }

    private func featureCard(icon: String, title: String, subtitle: String, badge: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(theme.accentColor)
                .frame(width: 40, height: 40)
                .background(theme.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(AppleTheme.label)
                    if let badge {
                        Text(badge)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(theme.accentColor.opacity(0.15))
                            .foregroundColor(theme.accentColor)
                            .clipShape(Capsule())
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppleTheme.secondaryLabel)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(AppleTheme.tertiaryLabel)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .liquidGlassLight(cornerRadius: 16)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(AppleTheme.label)
            Text("\(count)")
                .font(.caption)
                .foregroundColor(AppleTheme.secondaryLabel)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func fetch() {
        guard !isLoading else { return }
        isLoading = true
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        let p = page
        Task {
            do {
                if kw.isEmpty {
                    let result: PagedResult<OnlineSong> = try await music.feed(page: p)
                    await MainActor.run {
                        if p == 1 {
                            songs = result.items
                        } else {
                            songs.append(contentsOf: result.items)
                        }
                        hasMore = result.hasMore
                        isLoading = false
                    }
                } else {
                    // 搜索模式：本地 + 平台分组
                    let result = try await music.searchWithPlatforms(keyword: kw, page: p)
                    await MainActor.run {
                        if p == 1 {
                            songs = result.local
                            platformSongs = result.platforms
                            enabledPlatforms = result.enabledPlatforms
                        } else {
                            songs.append(contentsOf: result.local)
                            // 平台结果只取第一页（后端已按相关度截断）
                        }
                        hasMore = result.hasMore
                        isLoading = false
                    }
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
                withAnimation(.gsapPower2Out) { errorMessage = nil }
            }
        }
    }
}
