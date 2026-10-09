import SwiftUI

// MARK: - BlurText（2026-10-09，React Bits 适配）
//
// 歌名入场：逐字模糊浮现（stagger）。
// 字号/字重/颜色全部走环境（调用方用 .font() / .foregroundColor() 控制）。
//
//   - 弹簧：AppleTheme 系（response 0.45 / damping 1.0，无回弹），逐字 delay stagger
//   - text 变化时自动重播一次
//   - 减少动态效果：直接显示终态，无动画
//   - 注意：内部是 HStack，不自动换行；适合短标题（歌名），调用方加 .lineLimit(1)
//
// 用法：
//   BlurText(text: track.title)
//       .font(.title2.bold())
//       .foregroundColor(AppleTheme.label)

struct BlurText: View {
    let text: String
    var stagger: Double = 0.03
    var blurRadius: CGFloat = 10
    var riseDistance: CGFloat = 14

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var settled: Bool { appeared || reduceMotion }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .blur(radius: settled ? 0 : blurRadius)
                    .opacity(settled ? 1 : 0)
                    .offset(y: settled ? 0 : riseDistance)
                    .animation(
                        .spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
                            .delay(Double(index) * stagger),
                        value: appeared
                    )
            }
        }
        .onAppear {
            appeared = true
        }
        .onChange(of: text) { _ in
            // 切歌时重播：先回初态，下一帧再触发
            appeared = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                appeared = true
            }
        }
    }
}
