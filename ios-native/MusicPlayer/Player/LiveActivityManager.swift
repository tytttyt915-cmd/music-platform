import Foundation
import MediaPlayer
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - LiveActivityManager（v4.2）
//
// 职责：播放状态的系统级实时展示。
//
// 1. 锁屏 / 控制中心（立即生效，无需额外 target）：
//    MPNowPlayingInfoCenter —— 歌名/歌手/封面/进度/播放速率，
//    进度由系统按 playbackRate 自动推进，0.5s 粒度的 currentTime 足够实时。
//
// 2. 灵动岛 Live Activity（ActivityKit）：
//    本文件已含完整的 ActivityAttributes 定义与 start/update/end 逻辑。
//    注意：灵动岛/锁屏真正渲染出 Live Activity 卡片，需要一个 Widget Extension
//    target（含 ActivityConfiguration UI）。当前 Ad Hoc 只有一个主 App 的
//    mobileprovision，加 extension 需要新建 App ID + 描述文件，
//    由后续步骤在 Apple Developer 后台配好后再接入 extension target。
//    在此之前 startLiveActivity() 会静默跳过，不崩溃、不影响播放。

/// 灵动岛 Activity 属性（Widget Extension 接入后由系统渲染）
#if canImport(ActivityKit)
@available(iOS 16.1, *)
struct NowPlayingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var progress: Double   // 0~1
        var isPlaying: Bool
    }
    var songId: String
}
#endif

final class LiveActivityManager {
    static let shared = LiveActivityManager()

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private var currentActivity: Activity<NowPlayingActivityAttributes>?
    #endif

    private init() {}

    // MARK: - 对外：播放状态变化时调用

    /// 切歌 / 播放 / 暂停时调用，同步锁屏 + 灵动岛
    func sync(track: Track?, isPlaying: Bool, currentTime: Double, duration: Double) {
        updateNowPlaying(track: track, isPlaying: isPlaying, currentTime: currentTime, duration: duration)
        updateLiveActivity(track: track, isPlaying: isPlaying, currentTime: currentTime, duration: duration)
    }

    // MARK: - 锁屏（MPNowPlayingInfoCenter，立即生效）

    private func updateNowPlaying(track: Track?, isPlaying: Bool, currentTime: Double, duration: Double) {
        guard let track = track else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        // 封面异步加载，不阻塞
        if let url = track.artworkURL {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data = data, let image = UIImage(data: data) else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                DispatchQueue.main.async {
                    var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    current[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = current
                }
            }.resume()
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - 灵动岛（ActivityKit，需 Widget Extension 渲染）

    private func updateLiveActivity(track: Track?, isPlaying: Bool, currentTime: Double, duration: Double) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        guard let track = track else {
            endLiveActivity()
            return
        }
        let progress = duration > 0 ? min(max(currentTime / duration, 0), 1) : 0
        let state = NowPlayingActivityAttributes.ContentState(
            title: track.title,
            artist: track.artist,
            progress: progress,
            isPlaying: isPlaying
        )
        if let activity = currentActivity {
            // 同一首歌：更新；切歌：结束旧的开新的
            let attributes = activity.attributes
            if attributes.songId == track.id {
                Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
            } else {
                endLiveActivity()
                startLiveActivity(track: track, state: state)
            }
        } else {
            startLiveActivity(track: track, state: state)
        }
        #endif
    }

    private func startLiveActivity(track: Track, state: NowPlayingActivityAttributes.ContentState) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        // 没有 Widget Extension 时系统无处渲染，直接跳过（不抛错）
        guard Activity<NowPlayingActivityAttributes>.activities.isEmpty else { return }
        let attributes = NowPlayingActivityAttributes(songId: track.id)
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            // 无 extension / 被拒绝都不影响播放，静默
        }
        #endif
    }

    private func endLiveActivity() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        Task {
            let activities = Activity<NowPlayingActivityAttributes>.activities
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            await MainActor.run { self.currentActivity = nil }
        }
        #endif
    }
}
