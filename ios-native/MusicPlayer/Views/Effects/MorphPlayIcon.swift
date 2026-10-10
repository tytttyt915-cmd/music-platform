import SwiftUI

// MARK: - MorphPlayIcon（对标 Beans PlayPauseMorphIcon）
//
// 不是切换两个 SF Symbol，而是在同一 ZStack 内形变：
//   play 三角形：opacity 1→0 + scale 1→0.82 + x +5
//   pause 双条：opacity 0→1 + scale 0.82→1 + x -5→0
//   spring(response: 0.28, dampingFraction: 0.78)
//
// 铁律③（可打断）：连续点击从当前值继续，不闪烁。
// 替代：Image(systemName: isPlaying ? "pause" : "play") 的硬切换。

struct MorphPlayIcon: View {
    let isPlaying: Bool
    var size: CGFloat = 22

    private var progress: CGFloat { isPlaying ? 1 : 0 }

    var body: some View {
        ZStack {
            // play 三角形：播→停时淡出右移
            Image(systemName: "play.fill")
                .font(.system(size: size, weight: .semibold))
                .opacity(1 - progress)
                .scaleEffect(1 - progress * 0.18)
                .offset(x: progress * 5)
            // pause 双条：停→播时淡入左移
            HStack(spacing: max(3, size * 0.18)) {
                RoundedRectangle(cornerRadius: max(1.5, size * 0.08), style: .continuous)
                    .frame(width: max(4, size * 0.24), height: size * 0.86)
                RoundedRectangle(cornerRadius: max(1.5, size * 0.08), style: .continuous)
                    .frame(width: max(4, size * 0.24), height: size * 0.86)
            }
            .opacity(progress)
            .scaleEffect(0.82 + progress * 0.18)
            .offset(x: (1 - progress) * -5)
        }
        .frame(width: size + 6, height: size + 6)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isPlaying)
    }
}
