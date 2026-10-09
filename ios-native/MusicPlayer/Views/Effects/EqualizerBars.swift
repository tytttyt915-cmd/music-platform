import SwiftUI

// MARK: - EqualizerBars（2026-10-09，React Bits 适配）
//
// 播放律动条：4 根竖条，高度随时间正弦跳动，每根频率/相位错开。
// 音乐 App 辨识度最高的微交互。
//
//   - isPlaying = true：TimelineView(.animation) 驱动，不用 Timer；
//     视图离开层级自动暂停，不耗电
//   - isPlaying = false：静止低条（暂停态）
//   - 颜色：默认走环境 accentColor，调用方可传 theme.accentColor
//   - 圆角：连续圆角，barWidth / 2
//   - 深色/浅色：颜色由调用方决定，默认 accentColor 双模式可用
//   - 减少动态效果：开启时只渲染静止条
//
// 用法：
//   EqualizerBars(isPlaying: player.isPlaying, color: theme.accentColor)

struct EqualizerBars: View {
    var isPlaying: Bool
    var barCount: Int = 4
    var color: Color? = nil
    var barWidth: CGFloat = 3
    var barSpacing: CGFloat = 2.5
    var minHeight: CGFloat = 4
    var maxHeight: CGFloat = 16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isPlaying && !reduceMotion {
            TimelineView(.animation) { context in
                bars(time: context.date.timeIntervalSinceReferenceDate, animated: true)
            }
        } else {
            bars(time: 0, animated: false)
        }
    }

    private func bars(time t: Double, animated: Bool) -> some View {
        HStack(alignment: .bottom, spacing: barSpacing) {
            ForEach(0 ..< max(barCount, 1), id: \.self) { i in
                RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                    .fill(color ?? Color.accentColor)
                    .frame(width: barWidth, height: barHeight(index: i, time: t, animated: animated))
            }
        }
        .frame(height: maxHeight, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func barHeight(index i: Int, time t: Double, animated: Bool) -> CGFloat {
        guard animated else { return minHeight }
        // 每根柱子频率与相位错开，避免同步摆动
        let wave = sin(t * (3.6 + Double(i) * 0.8) + Double(i) * 1.7)
        let normalized = 0.2 + 0.8 * abs(wave)
        return minHeight + (maxHeight - minHeight) * CGFloat(normalized)
    }
}
