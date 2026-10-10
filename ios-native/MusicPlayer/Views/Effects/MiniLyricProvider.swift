import SwiftUI
import Combine

// MARK: - MiniLyricProvider（对标 Beans MiniPlayerView 实时歌词）
//
// 职责：为 MiniPlayer 提供当前歌词行。
//   - 切歌时按 onlineSongId 加载歌词（MusicService.lyrics）
//   - 二分查找当前行（O(log n)，歌词按时间升序）
//   - 无歌词时返回 nil，调用方回退显示歌手名
//   - 0.25s easeInOut 切换动画由调用方加

@MainActor
final class MiniLyricProvider: ObservableObject {
    @Published private(set) var currentLine: String?

    private var lines: [LyricLine] = []
    private var loadedSongId: String?
    private var cancellables = Set<AnyCancellable>()

    /// 绑定播放器：监听切歌 + 播放进度
    func bind(player: AudioPlayerManager, music: MusicService) {
        // 切歌 → 重新加载歌词
        player.$currentTrack
            .map { $0?.onlineSongId }
            .removeDuplicates()
            .sink { [weak self] songId in
                self?.loadLyrics(songId: songId, music: music)
            }
            .store(in: &cancellables)

        // 进度 → 二分查找当前行（节流到 0.5s，避免每帧计算）
        player.$currentTime
            .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                self?.updateCurrentLine(player: player)
            }
            .store(in: &cancellables)
    }

    private func loadLyrics(songId: String?, music: MusicService) {
        lines = []
        currentLine = nil
        loadedSongId = songId
        guard let songId else { return }
        Task {
            do {
                let result = try await music.lyrics(id: songId)
                await MainActor.run {
                    // 切歌竞态：只接受当前歌曲的歌词
                    guard self.loadedSongId == songId else { return }
                    self.lines = result
                    self.currentLine = nil
                }
            } catch {
                // 歌词加载失败不抛错，MiniPlayer 回退显示歌手名
            }
        }
    }

    /// 二分查找：lines 按 time 升序，找最后一个 time <= progress 的行
    private func updateCurrentLine(player: AudioPlayerManager) {
        guard !lines.isEmpty else {
            if currentLine != nil { currentLine = nil }
            return
        }
        let t = player.currentTime
        var low = 0
        var high = lines.count - 1
        var answer: String?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= t {
                answer = lines[mid].text
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        if answer != currentLine {
            currentLine = answer
        }
    }
}
