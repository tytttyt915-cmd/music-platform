// Views 适配（2026-10-09）：重写。老歌单搜索在新后端无对应接口；
// 改为"我的歌单"：创建歌单（POST /playlists，需登录），歌单 ID 本地持久化，
// 点歌单进详情看歌曲列表并可直接播放。后端暂无"我的歌单列表"接口，用本地 ID 列表补位。
import SwiftUI

struct PlaylistPlazaView: View {
    @EnvironmentObject var music: MusicService
    @EnvironmentObject var auth: AuthService
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var theme: ThemeSettings

    @State private var newTitle = ""
    @State private var playlists: [OnlinePlaylist] = []
    @State private var isLoading = false
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showingDetail: PlaylistDetail?
    @State private var detailPresented = false

    private let idsKey = "myPlaylistIDs"

    var body: some View {
        VStack(spacing: 0) {
            Text("歌单")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)

            if !auth.isLoggedIn {
                Spacer()
                Text("登录后创建和管理歌单")
                    .foregroundColor(theme.secondaryTextColor)
                Spacer()
            } else {
                VStack(spacing: 0) {
                    HStack {
                        TextField("新建歌单名称", text: $newTitle)
                            .textFieldStyle(.roundedBorder)
                        Button("创建") { create() }
                            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                    }
                    .padding()

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                    if isLoading { ProgressView().padding() }

                    List(playlists) { playlist in
                        Button { loadDetail(playlist) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.title)
                                        .foregroundStyle(theme.textColor)
                                    Text("\(playlist.trackCount)首")
                                        .font(.caption)
                                        .foregroundStyle(theme.secondaryTextColor)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(theme.secondaryTextColor)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .background(Color.clear)
        .onAppear { reload() }
        .sheet(isPresented: $detailPresented) {
            if let detail = showingDetail {
                NavigationView {
                    PlaylistDetailView(detail: detail)
                }
            }
        }
    }

    // MARK: - 数据

    /// 用本地持久化的歌单 ID 逐个拉详情；失效 ID 自动丢弃
    private func reload() {
        guard auth.isLoggedIn else { return }
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
                }
            } catch {
                await MainActor.run {
                    errorMessage = "创建失败：\(error.localizedDescription)"
                    isCreating = false
                }
            }
        }
    }

    private func loadDetail(_ playlist: OnlinePlaylist) {
        Task {
            do {
                let detail = try await music.playlistDetail(id: playlist.id)
                await MainActor.run {
                    showingDetail = detail
                    detailPresented = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = "加载歌单失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

/// 歌单详情：歌曲列表，点击播放（与本文件配套，非独立复用组件）
private struct PlaylistDetailView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var theme: ThemeSettings
    let detail: PlaylistDetail

    var body: some View {
        Group {
            if detail.songs.isEmpty {
                Text("歌单暂无歌曲")
                    .foregroundColor(theme.secondaryTextColor)
            } else {
                List(detail.songs) { song in
                    Button {
                        if let idx = detail.songs.firstIndex(where: { $0.id == song.id }) {
                            player.playOnlineSongs(detail.songs, startAt: idx)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.title)
                                .foregroundColor(theme.textColor)
                                .lineLimit(1)
                            Text(song.artist)
                                .font(.caption)
                                .foregroundColor(theme.secondaryTextColor)
                                .lineLimit(1)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(detail.playlist.title)
    }
}
