import SwiftUI

// MARK: - MyPlaylistsView（v4.5 从 PlaylistPlazaView 拆出）
//
// 职责：我的歌单（登录用户创建/管理）。
//   - 创建歌单（POST /playlists，需登录）；歌单 ID 本地持久化
//   - 歌单卡片：64pt 圆角封面 + 标题/信息 + chevron
//   - 新建用原生 sheet + TextField；点卡片 → NavigationLink 进详情
// 入口：我的 Tab → 我的歌单

struct MyPlaylistsView: View {
    @EnvironmentObject private var music: MusicService
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var theme: ThemeSettings

    @State private var newTitle = ""
    @State private var playlists: [OnlinePlaylist] = []
    @State private var isLoading = false
    @State private var isCreating = false
    @State private var showCreateSheet = false
    @State private var errorMessage: String?

    private let idsKey = "myPlaylistIDs"

    var body: some View {
        ZStack(alignment: .top) {
            AppleTheme.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 0) {
                    if !auth.isLoggedIn {
                        notLoggedInView
                    } else if isLoading && playlists.isEmpty {
                        LoadingStateView()
                    } else if playlists.isEmpty {
                        EmptyStateView(
                            icon: "music.note.list",
                            title: "还没有歌单",
                            subtitle: "点右上角 + 创建一个吧"
                        )
                    } else {
                        ForEach(playlists) { playlist in
                            NavigationLink {
                                MyPlaylistDetailScreen(playlistID: playlist.id, title: playlist.title)
                            } label: {
                                playlistCard(playlist)
                            }
                            .pressable()
                            Divider().padding(.leading, 88)
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
        .navigationTitle("我的歌单")
        .toolbar {
            if auth.isLoggedIn {
                Button {
                    newTitle = ""
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            createSheet
        }
        .onAppear { reload() }
        .onChange(of: auth.isLoggedIn) { _ in reload() }
    }

    // MARK: - 子视图

    private func playlistCard(_ playlist: OnlinePlaylist) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: AppleTheme.artworkRadius)
                    .fill(theme.accentColor.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: "music.note.list")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(theme.accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.title)
                    .font(.body)
                    .foregroundColor(AppleTheme.label)
                    .lineLimit(1)
                Text("\(playlist.trackCount) 首 · \(playlist.creator)")
                    .font(.body)
                    .foregroundColor(AppleTheme.secondaryLabel)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppleTheme.tertiaryLabel)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    private var notLoggedInView: some View {
        EmptyStateView(
            icon: "music.note.list",
            title: "登录后创建和管理歌单",
            subtitle: "手机号登录或游客试听"
        )
    }

    private var createSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("歌单名称", text: $newTitle)
                } footer: {
                    Text("给你的歌单起个名字")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("新建歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showCreateSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { create() }
                        .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - 数据

    private func reload() {
        guard auth.isLoggedIn else {
            playlists = []
            return
        }
        isLoading = true
        errorMessage = nil
        Task {
            let ids = UserDefaults.standard.stringArray(forKey: idsKey) ?? []
            var loaded: [OnlinePlaylist] = []
            var validIDs: [String] = []
            for id in ids {
                do {
                    let detail = try await music.playlistDetail(id: id)
                    loaded.append(detail.playlist)
                    validIDs.append(id)
                } catch {
                    // 失效的歌单 ID 丢弃，不打断其余加载
                }
            }
            UserDefaults.standard.set(validIDs, forKey: idsKey)
            await MainActor.run {
                playlists = loaded
                isLoading = false
            }
        }
    }

    private func create() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        isCreating = true
        errorMessage = nil
        Task {
            do {
                let playlist = try await music.createPlaylist(title: title)
                var ids = UserDefaults.standard.stringArray(forKey: idsKey) ?? []
                ids.insert(playlist.id, at: 0)
                UserDefaults.standard.set(ids, forKey: idsKey)
                await MainActor.run {
                    playlists.insert(playlist, at: 0)
                    newTitle = ""
                    isCreating = false
                    showCreateSheet = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "创建失败：\(error.localizedDescription)"
                    isCreating = false
                }
            }
        }
    }
}

// MARK: - 我的歌单详情

private struct MyPlaylistDetailScreen: View {
    let playlistID: String
    let title: String

    @EnvironmentObject private var music: MusicService
    @EnvironmentObject private var player: AudioPlayerManager

    @State private var songs: [OnlineSong] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            AppleTheme.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 0) {
                    if isLoading {
                        LoadingStateView()
                    } else if songs.isEmpty {
                        EmptyStateView(
                            icon: "music.note",
                            title: "歌单是空的",
                            subtitle: "去发现页加几首吧"
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
                            Divider().padding(.leading, 64)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            if let errorMessage {
                ErrorBanner(message: errorMessage)
                    .padding(.top, 8)
                    .zIndex(1)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
    }

    private func load() async {
        do {
            let detail = try await music.playlistDetail(id: playlistID)
            await MainActor.run {
                songs = detail.songs
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "加载失败：\(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}
