import SwiftUI

// MARK: - SearchView（v4.4 独立搜索页）
//
// 职责：搜索 Tab。
//   - 顶部搜索框（原生 .searchable）；无关键字 → 热搜胶囊
//   - 有关键字 → 本地结果 + 平台分组结果（网易云/QQ/酷狗/付费音源）
//   - 点击播放；长按换源（付费平台）
//   - impeccable：图标去底座、字号 5 档、空分组给"暂无结果"提示

struct SearchView: View {
    @EnvironmentObject private var music: MusicService
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var theme: ThemeSettings

    @State private var keyword = ""
    @State private var songs: [OnlineSong] = []
    @State private var platformSongs: [PlatformTrack] = []
    @State private var enabledPlatforms: [String] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPlatform: String?
    @State private var sourceSwitchSong: OnlineSong?

    private var isSearchMode: Bool { !keyword.trimmingCharacters(in: .whitespaces).isEmpty }

    /// 热搜（与发现页一致）
    private let hotSearches = [
        "夜航星", "APT.", "晴天", "七里香",
        "海阔天空", "青花瓷", "稻香", "有何不可",
    ]

    private var filteredPlatformGroups: [(platform: String, songs: [PlatformTrack])] {
        let grouped = Dictionary(grouping: platformSongs, by: { $0.platform })
        let all = grouped.map { (platform: $0.key, songs: $0.value) }
            .sorted { $0.platform < $1.platform }
        guard let selected = selectedPlatform else { return all }
        return all.filter { $0.platform == selected }
    }

    private var enabledPaidPlatforms: [String] {
        enabledPlatforms.filter { PlatformTrack.paidPlatforms.contains($0) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !isSearchMode {
                    // 热搜胶囊
                    hotSearchCapsules
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                } else {
                    // 平台分段器
                    if !platformSongs.isEmpty {
                        platformSegmented
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                    }
                    // 搜索结果
                    if isLoading && songs.isEmpty && platformSongs.isEmpty {
                        LoadingStateView()
                    } else if songs.isEmpty && platformSongs.isEmpty {
                        EmptyStateView(
                            icon: "magnifyingglass",
                            title: "没有找到相关歌曲",
                            subtitle: "换个关键词试试"
                        )
                    } else {
                        if !songs.isEmpty {
                            sectionHeader("本地曲库", count: songs.count)
                            ForEach(Array(songs.enumerated()), id: \.element.id) { idx, song in
                                Button {
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
                        if !platformSongs.isEmpty {
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
            }
            // 底部留白躲开悬浮 MiniPlayer + TabBar
            .padding(.bottom, player.currentTrack != nil ? 170 : 100)
        }
        .refreshable { if isSearchMode { reload() } }
        .navigationTitle("搜索")
        .searchable(text: $keyword, prompt: "搜索歌曲、歌手、专辑")
        .onSubmit(of: .search) { reload() }
        .onChange(of: keyword) { newValue in
            if newValue.isEmpty { reload() }
        }
        .sheet(item: $sourceSwitchSong) { song in
            SourceSwitchView(song: song)
        }
        .overlay(alignment: .top) {
            if let errorMessage {
                ErrorBanner(message: errorMessage)
                    .padding(.top, 8)
                    .zIndex(1)
            }
        }
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
        guard hasMore, !isLoading, isSearchMode else { return }
        page += 1
        fetch()
    }

    private func fetch() {
        guard isSearchMode else { return }
        guard !isLoading else { return }
        isLoading = true
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                let result = try await music.searchWithPlatforms(keyword: kw, page: page, pageSize: 30)
                await MainActor.run {
                    songs += result.local
                    platformSongs += result.platforms
                    enabledPlatforms = result.enabledPlatforms
                    hasMore = result.hasMore
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    // MARK: - 组件

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(AppleTheme.label)
            Text("\(count)")
                .font(.caption)
                .foregroundColor(AppleTheme.tertiaryLabel)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    /// 热搜胶囊：前 3 带图标
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
                        .padding(.vertical, 8)
                        .background(AppleTheme.secondaryBackground)
                        .clipShape(Capsule())
                    }
                    .pressable()
                }
            }
        }
    }

    /// 平台分段器
    private var platformSegmented: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                platformChip(title: "全部", platform: nil)
                let platforms = Set(platformSongs.map { $0.platform }).sorted()
                ForEach(platforms, id: \.self) { p in
                    platformChip(title: PlatformTrack.displayName(for: p), platform: p)
                }
            }
        }
    }

    private func platformChip(title: String, platform: String?) -> some View {
        let isSelected = selectedPlatform == platform
        return Button {
            Haptics.tap()
            selectedPlatform = platform
        } label: {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : AppleTheme.label)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? theme.accentColor : AppleTheme.secondaryBackground)
                .clipShape(Capsule())
        }
        .pressable()
    }
}
