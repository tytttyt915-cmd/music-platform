import AVFoundation
import Combine
import Foundation
import UIKit

/// 睡眠定时：倒计时结束时 30 秒淡出音量后暂停
final class SleepTimerManager: ObservableObject {
    static let shared = SleepTimerManager()

    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var isActive: Bool = false
    @Published private(set) var isFadingOut: Bool = false
    /// 当前生效的预设描述（用于列表打勾）
    @Published private(set) var activePreset: String? = nil
    /// 播完当前歌曲模式（remainingSeconds = -1 为哨兵值）
    @Published private(set) var finishCurrentSong: Bool = false

    private var countdownTimer: AnyCancellable?
    private var fadeTimer: AnyCancellable?
    private var endObserver: NSObjectProtocol?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private weak var player: AVPlayer?
    private var originalVolume: Float = 1.0

    private init() {}

    /// 绑定播放器（由 AudioPlayerManager 调用一次）
    func bind(player: AVPlayer?) {
        self.player = player
    }

    /// 开始倒计时（秒）
    func start(seconds: Int, presetLabel: String? = nil) {
        cancel()
        guard seconds > 0 else { return }
        remainingSeconds = seconds
        isActive = true
        activePreset = presetLabel
        countdownTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.remainingSeconds -= 1
                if self.remainingSeconds <= 0 {
                    self.beginFadeOut()
                }
            }
    }

    /// 取消定时
    func cancel() {
        countdownTimer?.cancel()
        countdownTimer = nil
        fadeTimer?.cancel()
        fadeTimer = nil
        endBackgroundTask()
        if let endObserver = endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        remainingSeconds = 0
        isActive = false
        isFadingOut = false
        finishCurrentSong = false
        activePreset = nil
    }

    /// 播完当前歌曲后淡出停止（RetroMusic ACTION_PENDING_QUIT 的 iOS 实现）
    func startFinishCurrentSong() {
        cancel()
        finishCurrentSong = true
        isActive = true
        activePreset = "播完这首"
        remainingSeconds = -1
        // 监听当前 item 播完；item 切换时由 bind 重新注册（见 observeCurrentItemEnd）
        observeCurrentItemEnd()
    }

    /// 监听当前播放项的自然结束
    private func observeCurrentItemEnd() {
        if let endObserver = endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self,
                  self.finishCurrentSong,
                  !self.isFadingOut,
                  let item = note.object as? AVPlayerItem,
                  item == self.player?.currentItem else { return }
            self.beginFadeOut()
        }
    }

    /// 剩余时间文本（mm:ss；播完当前模式显示固定文案）
    var remainingText: String {
        if finishCurrentSong { return "播完这首" }
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func beginFadeOut() {
        countdownTimer?.cancel()
        countdownTimer = nil
        guard let player = player else {
            finish()
            return
        }
        isFadingOut = true
        originalVolume = player.volume
        // 后台任务：淡出 30 秒内即使用户切后台也能跑完
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "SleepTimerFadeOut") { [weak self] in
            self?.endBackgroundTask()
        }
        // 30 秒线性淡出，每 0.5 秒降一档
        let steps = 60
        var step = 0
        fadeTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                step += 1
                let progress = Float(step) / Float(steps)
                player.volume = self.originalVolume * max(0, 1 - progress)
                if step >= steps {
                    self.finish()
                }
            }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    private func finish() {
        fadeTimer?.cancel()
        fadeTimer = nil
        player?.pause()
        player?.volume = originalVolume
        remainingSeconds = 0
        isActive = false
        isFadingOut = false
        finishCurrentSong = false
        activePreset = nil
        endBackgroundTask()
        if let endObserver = endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}
