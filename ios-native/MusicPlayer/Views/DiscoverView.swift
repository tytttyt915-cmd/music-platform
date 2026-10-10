import SwiftUI

// MARK: - DiscoverView（2026-10-09 Apple 原生风重做）
//
// 职责：发现页。
//   - 原生 .searchable 搜索框；有关键字 → music.search，无关键字 → music.feed
//   - 歌曲行用 SongRow（48pt 封面 + 标题/歌手）；点击播放整单
//   - 分页：到底自动加载（hasMore）；下拉刷新
//   - 错误用顶部浮条提示，3 秒自动消失

/// 发现页壁纸选项（设置 → 外观与界面 → 动态壁纸 → 发现页背景）
///
/// [Beans#3 用户即背景]：Beans 没有"设计背景"，直接用用户自己的壁纸 + 模糊。
/// iOS 取不到系统壁纸，所以给"自选图片"：用户从相册选一张，App 做模糊 + 压暗。
enum DiscoverWallpaper: String, CaseIterable {
    case system = "跟随系统"
    case darkSpace = "深空渐变"
    case inkBlue = "墨蓝渐变"
    case ember = "暗夜红"
    case custom = "自选图片"

    /// 自选壁纸存 Documents/wallpaper.jpg（AppStorage 存不下图片）
    static var customImageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("wallpaper.jpg")
    }
}

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
    // 网易云真实内容（直连 ncm-api：大卡片真实封面）
    @State private var dailyCoverURL: URL?
    @State private var trendingCoverURL: URL?
    @State private var roamCoverURL: URL?
    @State private var hotChartCoverURL: URL?
    @State private var newChartCoverURL: URL?
    @State private var isLoadingPlaylists = false
    // Beans 风格：平台分段器选中态（nil = 全部）
    @State private var selectedPlatform: String?

    /// 发现页壁纸（设置 → 外观与界面 → 动态壁纸 → 发现页背景；默认深色渐变）
    /// impeccable Quieter：深色打底 + 低饱和，壁纸是氛围不是主角
    @AppStorage("settings.discover.wallpaper") private var wallpaperRaw = DiscoverWallpaper.darkSpace.rawValue
    private var wallpaper: DiscoverWallpaper { DiscoverWallpaper(rawValue: wallpaperRaw) ?? .darkSpace }

    private var isSearchMode: Bool { !keyword.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Beans 风格时间问候语
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<9: return "早上好"
        case 9..<12: return "上午好"
        case 12..<14: return "中午好"
        case 14..<18: return "下午好"
        case 18..<23: return "晚上好"
        default: return "夜深了"
        }
    }

    /// 热搜（Beans 风格胶囊，前 3 带图标）
    private let hotSearches = [
        "夜航星", "APT.", "晴天", "七里香",
        "海阔天空", "青花瓷", "稻香", "有何不可",
    ]

    /// 分段器过滤后的平台分组
    private var filteredPlatformGroups: [(platform: String, songs: [PlatformTrack])] {
        guard let sel = selectedPlatform else { return groupedPlatformSongs }
        return groupedPlatformSongs.filter { $0.platform == sel }
    }

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

    /// 壁纸背景：默认深空渐变；跟随系统时用 AppleTheme.background
    @ViewBuilder
    private var discoverBackground: some View {
        switch wallpaper {
        case .system:
            AppleTheme.background.ignoresSafeArea()
        case .darkSpace:
            LinearGradient(
                colors: [Color(white: 0.05), Color(white: 0.11), Color(white: 0.07)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()
        case .inkBlue:
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.09, blue: 0.16), Color(red: 0.03, green: 0.06, blue: 0.12)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()
        case .ember:
            LinearGradient(
                colors: [Color(red: 0.14, green: 0.05, blue: 0.05), Color(red: 0.07, green: 0.04, blue: 0.04)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()
        case .custom:
            // [Beans#3] 用户自选图片：模糊 + 压暗，保证文字可读
            Group {
                if let data = try? Data(contentsOf: DiscoverWallpaper.customImageURL),
                   let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 30)
                        .overlay(.black.opacity(0.55))
                } else {
                    // 没选图时回退深空渐变（不撒谎：不是"自选"失败，是还没选）
                    LinearGradient(
                        colors: [Color(white: 0.05), Color(white: 0.11), Color(white: 0.07)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
            }
            .ignoresSafeArea()
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            discoverBackground

            ScrollView {
                LazyVStack(spacing: 0) {
                    // Beans 风格：时间问候语（仅非搜索模式）
                    if !isSearchMode {
                        greetingHeader
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                    }
                    // [Beans#7] 个性化双卡：每日推荐 / 私人漫游
                    if !isSearchMode {
                        realCoverEntries
                            .padding(.bottom, 16)
                    }
                    // [Beans#7] 社会认同：排行榜（热歌榜/未来飙升榜/新歌榜）
                    if !isSearchMode {
                        rankingSection
                            .padding(.bottom, 12)
                    }
                    // Beans 风格：热搜胶囊（仅非搜索模式）
                    if !isSearchMode {
                        hotSearchCapsules
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                    // Beans 风格：平台分段器（仅搜索模式有平台结果时）
                    if isSearchMode && !groupedPlatformSongs.isEmpty {
                        platformSegmented
                            .padding(.horizontal, 16)
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
                        // Beans #4 教训：空分组给"暂无结果"提示，不静默消失
                        if isSearchMode && !platformSongs.isEmpty {
                            if filteredPlatformGroups.isEmpty {
                                Text("该平台暂无结果，换个平台试试")
                                    .font(.body)
                                    .foregroundColor(AppleTheme.tertiaryLabel)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            }
                            ForEach(filteredPlatformGroups, id: \.platform) { group in
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
                // Beans #22 教训：底部留白必须躲开悬浮 MiniPlayer + TabBar，
                // 否则最后两行被遮住点不到
                .padding(.bottom, player.currentTrack != nil ? 170 : 100)
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
        // 壁纸为深色渐变时强制深色模式，保证文字对比度（craft floor 对比度 4.5:1）
        .preferredColorScheme(wallpaper == .system ? nil : .dark)
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
        // 非搜索模式：拉取大卡片真实封面
        if keyword.trimmingCharacters(in: .whitespaces).isEmpty {
            fetchDiscoverContent()
        }
    }

    private func loadMore() {
        guard hasMore, !isLoading else { return }
        page += 1
        fetch()
    }

    // MARK: - Beans 风格组件

    /// 时间问候语："晚上好" + "发现好音乐"
    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(AppleTheme.label)
            Text("发现好音乐")
                .font(.body)
                .foregroundColor(AppleTheme.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 热搜胶囊：前 3 带图标（皇冠/火焰/星星），其余带数字
    private var hotSearchCapsules: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("热搜")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(AppleTheme.label)
            FlowLayout(spacing: 8) {
                ForEach(Array(hotSearches.enumerated()), id: \.offset) { idx, term in
                    Button {
                        Haptics.tap()
                        keyword = term
                        reload()
                    } label: {
                        HStack(spacing: 4) {
                            if idx == 0 {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            } else if idx == 1 {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)
                            } else if idx == 2 {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.yellow)
                            } else {
                                Text("\(idx + 1)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(AppleTheme.tertiaryLabel)
                            }
                            Text(term)
                                .font(.body)
                                .foregroundColor(AppleTheme.label)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .liquidGlass(cornerRadius: 16)
                    }
                    .pressable()
                }
            }
        }
    }

    /// 平台分段器：全部 ｜ 网易云 ｜ QQ音乐 ｜ 酷狗 …
    private var platformSegmented: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                platformChip(title: "全部", platform: nil)
                ForEach(groupedPlatformSongs, id: \.platform) { group in
                    platformChip(
                        title: PlatformTrack.displayName(for: group.platform),
                        platform: group.platform
                    )
                }
            }
        }
    }

    private func platformChip(title: String, platform: String?) -> some View {
        let selected = selectedPlatform == platform
        return Button {
            Haptics.tap()
            withAnimation(.gsapPower2Out) { selectedPlatform = platform }
        } label: {
            Text(title)
                .font(.body)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundColor(selected ? .white : AppleTheme.label)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    selected ? theme.accentColor : Color(.tertiarySystemFill),
                    in: Capsule()
                )
        }
        .pressable()
    }

    // MARK: - v4.4 真实封面（网易云直连）
    //
    // 工具规则标注：
    // [Beans#内容为王] 大卡片用真实封面图打底，不再是渐变占位
    // [Beans#1] 大卡片三层结构：封面图 + 底部大标题 + 副标题，圆角 20pt
    // [Beans#2] 图标去底座化：线性图标直接着白色
    // [Beans#7] 颜色即信息：AI 徽章保留（飙升榜标识）
    // [impeccable-Typeset] 字号 5 档内（20/13/11）
    // [三铁律①] 按压反馈走 .pressable()

    // [Beans#7 顺序即推荐] 首页纵向顺序：个性化（每日推荐+私人漫游）→ 社会认同（排行榜）。
    // 未来飙升榜属于"排行榜"家族，和热歌榜/新歌榜在一起，不再与每日推荐并列。
    /// 真实封面大卡片：每日推荐 / 私人漫游（Beans home.jpg 双卡片语言）
    private var realCoverEntries: some View {
        HStack(spacing: 12) {
            NavigationLink {
                DailyRecommendView()
            } label: {
                realCoverCard(
                    coverURL: dailyCoverURL,
                    icon: "calendar",
                    title: "每日推荐",
                    subtitle: "30 首 · 每天 6:00 更新",
                    badge: nil
                )
            }
            .pressable()

            NavigationLink {
                PrivateRoamView()
            } label: {
                realCoverCard(
                    coverURL: roamCoverURL,
                    icon: "waveform",
                    title: "私人漫游",
                    subtitle: "从一首歌开始漫游",
                    badge: nil
                )
            }
            .pressable()
        }
        .padding(.horizontal, 16)
    }

    /// 排行榜区：热歌榜 / 未来飙升榜 / 新歌榜（[Beans#7] 颜色即信息：红/紫/绿）
    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("排行榜")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(AppleTheme.label)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    rankingCard(
                        title: "热歌榜",
                        color: Color(red: 0.93, green: 0.35, blue: 0.44),
                        coverURL: hotChartCoverURL,
                        idx: 1
                    )
                    // 未来飙升榜：我们的 AI 预测榜，归入排行榜家族
                    NavigationLink {
                        FutureTrendingView()
                    } label: {
                        rankingCardContent(
                            title: "未来飙升榜",
                            subtitle: "AI 预测",
                            color: Color(red: 0.50, green: 0.45, blue: 0.89),
                            coverURL: trendingCoverURL
                        )
                    }
                    .pressable()
                    rankingCard(
                        title: "新歌榜",
                        color: Color(red: 0.24, green: 0.78, blue: 0.49),
                        coverURL: newChartCoverURL,
                        idx: 2
                    )
                }
                .padding(.horizontal, 16)
            }
        }
    }

    /// 榜单卡片：点进去播该榜歌曲
    private func rankingCard(title: String, color: Color, coverURL: URL?, idx: Int) -> some View {
        Button {
            Task { await playChart(idx: idx) }
        } label: {
            rankingCardContent(title: title, subtitle: "大家都在听", color: color, coverURL: coverURL)
        }
        .pressable()
    }

    /// 榜单卡片内容：实心色块（[Beans#6] 内容用实心，不用玻璃）
    private func rankingCardContent(title: String, subtitle: String, color: Color, coverURL: URL?) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let coverURL {
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: color
                        }
                    }
                } else {
                    color
                }
            }
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(12)
        }
        .frame(width: 160, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    /// 播榜单歌曲
    private func playChart(idx: Int) async {
        do {
            let songs = try await NeteaseDiscoverService.shared.chartSongs(idx: idx, limit: 20)
            await MainActor.run {
                player.playPlatformTracks(songs)
            }
        } catch {
            // 静默失败，不打扰
        }
    }

    /// 大卡片：真实封面打底 + 底部压暗渐变 + 图标/标题/副标题
    private func realCoverCard(coverURL: URL?, icon: String, title: String, subtitle: String, badge: String?) -> some View {
        ZStack(alignment: .bottomLeading) {
            // 真实封面（无 URL 时深色占位）
            Group {
                if let coverURL {
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Color(white: 0.12)
                        }
                    }
                } else {
                    Color(white: 0.12)
                }
            }
            // 底部压暗，保证白字可读
            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    // [Beans#2] 图标去底座化
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(radius: 4)
                    Spacer()
                    if let badge {
                        Text(badge)
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.22))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
                Spacer()
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .shadow(radius: 4)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .padding(.top, 4)
                    .shadow(radius: 4)
            }
            .padding(16)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// 发现页网易云内容：大卡片真实封面 + 榜单封面（仅非搜索模式拉取）
    private func fetchDiscoverContent() {
        guard !isSearchMode, !isLoadingPlaylists else { return }
        isLoadingPlaylists = true
        Task {
            async let daily = NeteaseDiscoverService.shared.dailyCoverURL()
            async let trending = NeteaseDiscoverService.shared.trendingCoverURL()
            async let roam = NeteaseDiscoverService.shared.chartSongs(idx: 1, limit: 1)
            async let hot = NeteaseDiscoverService.shared.chartInfo(idx: 1)
            async let newsong = NeteaseDiscoverService.shared.chartInfo(idx: 2)
            do {
                let d = try await daily
                let t = try await trending
                let r = try await roam
                let h = try await hot
                let n = try await newsong
                await MainActor.run {
                    dailyCoverURL = d
                    trendingCoverURL = t
                    roamCoverURL = r.first?.coverURL
                    hotChartCoverURL = h.coverURL
                    newChartCoverURL = n.coverURL
                    isLoadingPlaylists = false
                }
            } catch {
                await MainActor.run { isLoadingPlaylists = false }
            }
        }
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
