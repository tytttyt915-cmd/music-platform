import SwiftUI

// MARK: - AudioReactiveBackground（Vanta.js WAVES 风格的音频律动背景）
//
// 职责：播放页全屏背景。iOS 17+ 用 Metal Shader 跑三层正弦波，
//   每层波由真 FFT 三频段能量驱动（低频→主波/鼓点，中频→细节波/人声，
//   高频→碎波/镲片）——Vanta 本体做不到音频联动，这是我们的超集。
//   tap 挂不上（如 DRM）时回退为时间相位模拟包络。
//
// 性能策略（Vanta 在 Web 上不管这个，iOS 必须管）：
//   1. 只在播放页挂载时渲染，离开页面 TimelineView 自动停止
//   2. 暂停时降帧到 15fps（呼吸模式），播放时全帧率
//   3. 低电量模式 → 静态渐变
//   4. iOS 16 及以下 → 静态渐变（Shader 需要 iOS 17+）
//   5. 开启"减少动态效果" → 静态渐变
//   6. FFT 在音频线程跑，每 2048 帧一次，CPU < 1%；UI 只读锁保护的 SIMD3
//
// 可读性：顶层始终罩一层深色渐变，保证歌词/文字清晰。

struct AudioReactiveBackground: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var theme: ThemeSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 封面主色覆盖（nil 时用主题强调色）
    var coverTint: Color? = nil

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
            WaveShaderView(
                time: now,
                amps: bandAmplitudes(time: now),
                tintColor: accentRGB
            )
        }
        .ignoresSafeArea()
    }

    /// 三频段能量：真 FFT 优先（tap 挂上且有信号），否则时间相位模拟包络。
    /// 暂停时 0.12 保底呼吸感。
    private func bandAmplitudes(time: Double) -> SIMD3<Float> {
        guard player.isPlaying else { return SIMD3<Float>(repeating: 0.12) }
        let analyzer = SpectrumAnalyzer.shared
        if analyzer.hasSignal {
            let s = analyzer.liveSpectrum
            return SIMD3<Float>(
                min(max(s.x, 0), 1),
                min(max(s.y, 0), 1),
                min(max(s.z, 0), 1)
            )
        }
        let sim = simulatedAmplitude(isPlaying: true, time: time)
        return SIMD3<Float>(repeating: sim)
    }

    /// 独立 View：把 Shader 表达式隔离出来，类型错误可精确定位。
    @available(iOS 17, *)
    private struct WaveShaderView: View {
        let time: Double
        let amps: SIMD3<Float>  // x=低频 y=中频 z=高频
        let tintColor: SIMD3<Float>

        var body: some View {
            Rectangle()
                .colorEffect(
                    ShaderLibrary.waveBackground(
                        .float(Float(time)),
                        .float(amps.x),
                        .float(amps.y),
                        .float(amps.z),
                        .float3(tintColor.x, tintColor.y, tintColor.z),
                        .boundingRect
                    )
                )
        }
    }

    // MARK: - 静态降级（iOS 16 / 低电量 / 减少动态效果）

    private var staticBackground: some View {
        ZStack {
            // 深底（固定深色，播放页氛围优先）
            Color(red: 0.03, green: 0.03, blue: 0.055)
            // 顶部品牌色微光（封面主色优先）
            LinearGradient(
                colors: [
                    (coverTint ?? theme.accentColor).opacity(0.22),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            // 底部品牌色微光
            LinearGradient(
                colors: [
                    Color.clear,
                    (coverTint ?? theme.accentColor).opacity(0.12)
                ],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - 辅助

    /// 主题强调色 → RGB（供 shader 的 tintColor 用）；封面主色优先
    private var accentRGB: SIMD3<Float> {
        let uiColor = UIColor(coverTint ?? theme.accentColor)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: nil)
        return SIMD3<Float>(Float(r), Float(g), Float(b))
    }

    /// 模拟音频振幅包络（降级用）：播放时 0.35~0.9 跳动。
    /// 只有 tap 挂不上（如 DRM 内容）时才走这里；正常走真 FFT。
    private func simulatedAmplitude(isPlaying: Bool, time: Double) -> Float {
        guard isPlaying else { return 0.12 }
        let beat = 0.5 + 0.5 * sin(time * 2.4)
        let shimmer = 0.5 + 0.5 * sin(time * 7.3 + 1.7)
        return Float(0.35 + 0.35 * beat + 0.18 * shimmer)
    }
}
