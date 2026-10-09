import AVFoundation
import Combine
import Foundation

/// 睡眠定时：倒计时结束时 30 秒淡出音量后暂停
final class SleepTimerManager: ObservableObject {
    static let shared = SleepTimerManager()

    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var isActive: Bool = false
    @Published private(set) var isFadingOut: Bool = false

    private var countdownTimer: AnyCancellable?
    private var fadeTimer: AnyCancellable?
    private weak var player: AVPlayer?
    private var originalVolume: Float = 1.0

    private init() {}

    /// 绑定播放器（由 AudioPlayerManager 调用一次）
    func bind(player: AVPlayer?) {
        self.player = player
    }

    /// 开始倒计时（秒）
    func start(seconds: Int) {
        cancel()
        guard seconds > 0 else { return }
        remainingSeconds = seconds
        isActive = true
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
        remainingSeconds = 0
        isActive = false
        isFadingOut = false
    }

    /// 剩余时间文本（mm:ss）
    var remainingText: String {
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

    private func finish() {
        fadeTimer?.cancel()
        fadeTimer = nil
        player?.pause()
        player?.volume = originalVolume
        remainingSeconds = 0
        isActive = false
        isFadingOut = false
    }
}
