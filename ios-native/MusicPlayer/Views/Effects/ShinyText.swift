import SwiftUI

// MARK: - ShinyText（2026-10-09，React Bits 适配）
//
// 流光扫过文字：高光带周期性从左向右扫过，用于标题/徽标点缀。
// 底字颜色走环境（.foregroundColor），高光默认 Color.accentColor（深浅模式都可见）。
//
//   - TimelineView 驱动（30fps），不用 Timer；视图离开层级自动暂停
//   - 实现：全幅渐变（高光带位置编码在 stops 里）+ 文字 mask，
//     无需量宽，对齐天然正确，多行文字也可用
//   - 减少动态效果：只显示底字，无扫光
//
// 用法：
//   ShinyText(text: "为你推荐", color: theme.accentColor)
//       .font(.title3.bold())
//       .foregroundColor(AppleTheme.label)

struct ShinyText: View {
    let text: String
    var color: Color? = nil
    var sweepPeriod: Double = 3.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shine: Color { color ?? Color.accentColor }

    var body: some View {
        if reduceMotion {
            Text(text)
        } else {
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = (t / sweepPeriod).truncatingRemainder(dividingBy: 1.0)
                // 高光带中心从 -0.25（屏外左）扫到 1.25（屏外右）
                let center = -0.25 + phase * 1.5
                Text(text)
                    .overlay {
                        LinearGradient(
                            stops: [
                                Gradient.Stop(color: .clear, location: 0),
                                Gradient.Stop(color: shine.opacity(0), location: clamp01(center - 0.18)),
                                Gradient.Stop(color: shine, location: clamp01(center)),
                                Gradient.Stop(color: shine.opacity(0), location: clamp01(center + 0.18)),
                                Gradient.Stop(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .mask {
                            Text(text)
                        }
                    }
            }
        }
    }

    private func clamp01(_ v: Double) -> CGFloat {
        CGFloat(min(max(v, 0), 1))
    }
}
