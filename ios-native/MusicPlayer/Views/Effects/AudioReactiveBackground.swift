import SwiftUI

// MARK: - AudioReactiveBackground（Vanta.js WAVES 风格的音频律动背景）
//
// 职责：播放页全屏背景。iOS 17+ 用 Metal Shader 跑三层正弦波，
//   振幅由播放状态驱动（真音频 FFT 分析太重，用时间相位模拟律动包络——
//   Vanta 本体做不到音频联动，这是我们的超集）。
//
// 性能策略（Vanta 在 Web 上不管这个，iOS 必须管）：
//   1. 只在播放页挂载时渲染，离开页面 TimelineView 自动停止
//   2. 暂停时降帧到 15fps（呼吸模式），播放时全帧率
//   3. 低电量模式 → 静态渐变
//   4. iOS 16 及以下 → 静态渐变（Shader 需要 iOS 17+）
//   5. 开启"减少动态效果" → 静态渐变
//
// 可读性：顶层始终罩一层深色渐变，保证歌词/文字清晰。

struct AudioReactiveBackground: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var theme: ThemeSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if #available(iOS 17, *), shouldUseShader {
                shaderBackground
            } else {
                staticBackground
            }

            // 深色罩层：保证歌词/文字可读（深浅模式都压得住）
            LinearGradient(
                colors: [
                    Color.black.opacity(0.38),
                    Color.black.opacity(0.12),
                    Color.black.opacity(0.42)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - 开关

    private var shouldUseShader: Bool {
        guard !reduceMotion else { return false }
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return false }
        if #available(iOS 17, *) {
            return true
        } else {
            return false
        }
    }

    // MARK: - Metal Shader 背景（iOS 17+）

    @available(iOS 17, *)
    private var shaderBackground: some View {
        // 播放时全帧率，暂停时 15fps 呼吸
        let interval: Double? = player.isPlaying ? nil : 1.0 / 15.0
        let schedule = AnimationTimelineSchedule.animation(minimumInterval: interval)
        return TimelineView(schedule) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            return Rectangle()
                .colorEffect(
                    ShaderLibrary.waveBackground(
                        .float(Float(now)),
                        .float(simulatedAmplitude(isPlaying: player.isPlaying, time: now)),
                        .float3(accentRGB),
                        .boundingRect
                    )
                )
        }
        .ignoresSafeArea()
    }

    // MARK: - 静态降级（iOS 16 / 低电量 / 减少动态效果）

    private var staticBackground: some View {
        ZStack {
            // 深底（固定深色，播放页氛围优先）
            Color(red: 0.03, green: 0.03, blue: 0.055)
            // 顶部品牌色微光
            LinearGradient(
                colors: [
                    theme.accentColor.opacity(0.22),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            // 底部品牌色微光
            LinearGradient(
                colors: [
                    Color.clear,
                    theme.accentColor.opacity(0.12)
                ],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - 辅助

    /// 主题强调色 → RGB（供 shader 的 tintColor 用）
    private var accentRGB: SIMD3<Float> {
        let uiColor = UIColor(theme.accentColor)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: nil)
        return SIMD3<Float>(Float(r), Float(g), Float(b))
    }

    /// 模拟音频振幅包络：播放时 0.35~0.9 跳动，暂停时 0.12 保底呼吸感。
    /// 真 FFT 需要 AudioEngine tap 整条播放链路，成本过高；用多层正弦
    /// 叠加模拟 beat 包络，视觉上足够"随音乐律动"。
    private func simulatedAmplitude(isPlaying: Bool, time: Double) -> Float {
        guard isPlaying else { return 0.12 }
        let beat = 0.5 + 0.5 * sin(time * 2.4)
        let shimmer = 0.5 + 0.5 * sin(time * 7.3 + 1.7)
        return Float(0.35 + 0.35 * beat + 0.18 * shimmer)
    }
}
