import SwiftUI

// MARK: - PlaylistPlazaView（v4.5 按 Beans discover.jpg 真机重做）
//
// 职责：歌单广场（发现 Tab）。
//   - 顶部：红色 Logo + "搜索歌单"搜索框 + 头像
//   - 分类 chips：全部 / 推荐歌单 / 精品歌单 / 官方 / 华语 / 欧美（横滑）
//   - 2 列真实封面卡片：封面图 + 歌单名（标题是歌单名，不是功能名）+ "网易云 · 作者"
//   - 点卡片 → 拉取曲目 → 网易云源直接播放
//   - 数据直连 ncm-api（NeteaseDiscoverService），真实封面
//
// 工具规则标注：
// [Beans#内容为王] 2 列大封面三层结构（封面/标题/来源），圆角 18
// [Beans#chips] 分类胶囊横滑，选中态高亮
// [impeccable-Typeset] 字号档（15/13）
// [三铁律①] 按压反馈走 .pressable()

struct PlaylistPlazaView: View {
    @EnvironmentObject private var player: AudioPlayerManager

    @State private var category: NeteaseDiscoverService.PlaylistCategory = .all
    @State private var playlists: [NeteasePlaylist] = []
    @State private var isLoading = false
    @State private var loadingPlaylistId: Int64?
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            // 深色背景（Beans 壁纸质感用深色渐变代替）
            LinearGradient(
                colors: [Color(white: 0.06), Color(white: 0.10), Color(white: 0.07)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 0) {
                    // 顶部：Logo + 搜索框 + 头像
                    topBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    // 分类 chips
                    categoryChips
                        .padding(.bottom, 14)

                    // 2 列歌单网格
                    if isLoading && playlists.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 40)
                    } else if playlists.isEmpty {
                        EmptyStateView(
                            icon: "music.note.list",
                            title: "暂无歌单",
                            subtitle: "下拉刷新试试"
                        )
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            spacing: 18
                        ) {
                            ForEach(playlists) { playlist in
                                playlistCard(playlist)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                // Beans #22：底部留白躲开悬浮 MiniPlayer + TabBar
                .padding(.bottom, player.currentTrack != nil ? 170 : 100)
            }
            .refreshable { reload() }

            if let errorMessage {
                ErrorBanner(message: errorMessage)
                    .padding(.top, 8)
                    .zIndex(1)
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .task { reload() }
        .onChange(of: category) { _ in reload() }
    }

    // MARK: - 顶部栏

    /// Logo（红圆）+ 搜索框"搜索歌单" + 头像
    private var topBar: some View {
        HStack(spacing: 12) {
            // 红色 Logo
            ZStack {
                Circle()
                    .fill(Color(red: 0.92, green: 0.20, blue: 0.16))
                    .frame(width: 44, height: 44)
                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }

            // 搜索框（点进搜索页）
            NavigationLink {
                SearchView()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppleTheme.secondaryLabel)
                    Text("搜索歌单")
                        .font(.body)
                        .foregroundColor(AppleTheme.secondaryLabel)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.white.opacity(0.10))
                .clipShape(Capsule())
            }
            .pressable()

            // 头像占位
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "person.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    // MARK: - 分类 chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(NeteaseDiscoverService.PlaylistCategory.allCases, id: \.self) { cat in
                    let selected = category == cat
                    Button {
                        Haptics.tap()
                        withAnimation(.gsapPower2Out) { category = cat }
                    } label: {
                        Text(cat.rawValue)
                            .font(.system(size: 15, weight: selected ? .semibold : .regular))
                            .foregroundColor(selected ? .white : .white.opacity(0.65))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                selected
                                    ? Color.white.opacity(0.22)
                                    : Color.white.opacity(0.08)
                            )
                            .clipShape(Capsule())
                    }
                    .pressable()
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - 歌单卡片

    /// 封面 + 歌单名 + "网易云 · 作者"（Beans discover.jpg 三层结构）
    private func playlistCard(_ playlist: NeteasePlaylist) -> some View {
        Button {
            playPlaylist(playlist)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                ZStack {
                    coverArt(url: playlist.coverURL, size: 400)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    if loadingPlaylistId == playlist.id {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.black.opacity(0.45))
                        ProgressView()
                            .tint(.white)
                    }
                }
                // 标题 = 歌单名（单行截断）
                Text(playlist.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // 来源行
                Text("网易云 · \(playlist.creator)")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .pressable()
        .disabled(loadingPlaylistId != nil)
    }

    // MARK: - 数据

    private func reload() {
        isLoading = true
        errorMessage = nil
        let cat = category
        Task {
            do {
                let lists = try await NeteaseDiscoverService.shared.playlists(for: cat)
                await MainActor.run {
                    // 分类切换后只应用最新请求的结果
                    if cat == category {
                        playlists = lists
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "加载失败：\(error.localizedDescription)"
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await MainActor.run {
                            withAnimation(.gsapPower2Out) { errorMessage = nil }
                        }
                    }
                }
            }
        }
    }

    /// 点歌单 → 拉取曲目 → 网易云源直接播放
    private func playPlaylist(_ playlist: NeteasePlaylist) {
        guard loadingPlaylistId == nil else { return }
        loadingPlaylistId = playlist.id
        Haptics.tap()
        Task {
            do {
                let tracks = try await NeteaseDiscoverService.shared.playlistTracks(id: playlist.id)
                await MainActor.run {
                    loadingPlaylistId = nil
                    if !tracks.isEmpty {
                        player.playPlatformTracks(tracks, startAt: 0)
                    }
                }
            } catch {
                await MainActor.run {
                    loadingPlaylistId = nil
                    errorMessage = "歌单加载失败：\(error.localizedDescription)"
                }
            }
        }
    }
}
