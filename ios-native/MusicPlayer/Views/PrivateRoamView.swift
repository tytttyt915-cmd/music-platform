import SwiftUI
import Combine

// MARK: - PrivateRoamView（v4.6）
//
// 私人漫游：从一首歌开始，沿"相似歌曲"无限漫游（对标 Beans「从喜欢的歌开始漫游」）。
//
// 实现（[Beans#7] 顺序即推荐：个性化入口）：
//   - 种子：热歌榜 Top15 随机（免登录；收藏种子待 FavoriteStore 存 platformId 后升级）
//   - 漫游链：当前歌曲 → /simi/song 取相似 → 追加到播放队列 → 快播完时再取下一环
//   - 去重：seenIds 保证不重复
//
// 工具规则：
// [Beans#内容为王] 大封面是当前歌曲真实封面
// [Beans#4] 字号层级：标题 28pt bold，状态 15pt 灰
// [Beans#8] 状态不撒谎：漫游中/已停止/加载中如实显示
// [三铁律①] 按钮 .pressable()

/// 漫游控制器：种子 → 相似链 → 队列追加
@MainActor
final class RoamController: ObservableObject {
    @Published var isRoaming = false
    @Published var roamCount = 0
    @Published var statusText = "准备漫游…"

    private var timer: Timer?
    private var fetching = false
    private var seenIds = Set<String>()
    private let service = NeteaseDiscoverService.shared

    /// 开始漫游
    func start(player: AudioPlayerManager) async {
        guard !isRoaming else { return }
        statusText = "正在找歌…"
        do {
            let seeds = try await service.chartSongs(idx: 1, limit: 15)
            guard !seeds.isEmpty else {
                statusText = "网络开小差了，稍后再试"
                return
            }
            let shuffled = seeds.shuffled()
            seenIds = Set(shuffled.map(\.platformId))
            player.playPlatformTracks(shuffled)
            isRoaming = true
            roamCount = 0
            statusText = "漫游中 · 越听越懂你"
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick(player: player) }
            }
        } catch {
            statusText = "网络开小差了，稍后再试"
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRoaming = false
        statusText = "已停止漫游"
    }

    /// 快播完时取当前歌曲的相似歌曲追加
    private func tick(player: AudioPlayerManager) {
        guard isRoaming, !fetching,
              player.duration > 0,
              player.duration - player.currentTime < 10,
              player.currentTrack?.platform == "netease",
              let pid = player.currentTrack?.platformId, !pid.isEmpty
        else { return }
        fetching = true
        Task {
            defer { Task { @MainActor in self.fetching = false } }
            guard let sims = try? await service.similarSongs(id: pid, limit: 10) else { return }
            let fresh = sims.filter { !seenIds.contains($0.platformId) }
            guard !fresh.isEmpty else { return }
            fresh.forEach { seenIds.insert($0.platformId) }
            await MainActor.run {
                player.appendPlatformTracks(fresh)
                self.roamCount += fresh.count
                self.statusText = "漫游中 · 已为你续了 \(self.roamCount) 首"
            }
        }
    }
}

struct PrivateRoamView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @StateObject private var roam = RoamController()

    var body: some View {
        ZStack {
            AppleTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // 标题
                VStack(spacing: 4) {
                    Text("私人漫游")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AppleTheme.label)
                    Text(roam.statusText)
                        .font(.system(size: 15))
                        .foregroundColor(AppleTheme.secondaryLabel)
                }
                .padding(.top, 16)

                Spacer()

                // 当前歌曲封面（真实封面，[Beans#内容为王]）
                Group {
                    if let url = player.currentTrack?.artworkURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFill()
                            default: Color(white: 0.12)
                            }
                        }
                    } else {
                        Color(white: 0.12)
                    }
                }
                .frame(width: 240, height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)

                // 歌名/歌手
                VStack(spacing: 4) {
                    Text(player.currentTrack?.title ?? "—")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AppleTheme.label)
                        .lineLimit(1)
                    Text(player.currentTrack?.artist ?? "—")
                        .font(.system(size: 15))
                        .foregroundColor(AppleTheme.secondaryLabel)
                        .lineLimit(1)
                }
                .padding(.top, 16)

                Spacer()

                // 控制：换一首 / 停止-开始
                HStack(spacing: 32) {
                    Button {
                        player.next()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 28))
                                .foregroundColor(AppleTheme.label)
                            Text("换一首")
                                .font(.caption)
                                .foregroundColor(AppleTheme.secondaryLabel)
                        }
                    }
                    .pressable()
                    .disabled(!roam.isRoaming)

                    Button {
                        if roam.isRoaming {
                            roam.stop()
                        } else {
                            Task { await roam.start(player: player) }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: roam.isRoaming ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(roam.isRoaming ? .red : AppleTheme.label)
                            Text(roam.isRoaming ? "停止" : "开始")
                                .font(.caption)
                                .foregroundColor(AppleTheme.secondaryLabel)
                        }
                    }
                    .pressable()
                }
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
        }
        .navigationTitle("私人漫游")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await roam.start(player: player) }
        }
        .onDisappear {
            // 离开页面不停播，只停"续歌"；用户点停止才彻底停
            roam.stop()
        }
    }
}
