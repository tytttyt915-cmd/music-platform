import SwiftUI

/// React Bits ClickSpark：点击处爆出放射状小火花。
/// 用途：FullPlayerView 播放/暂停按钮——和 pressable 缩放叠加，双层反馈。
/// 按钮场景用中心爆发；如需精确定位（列表行点击），再升级 GeometryReader 版。
struct ClickSpark: ViewModifier {
    @State private var sparks: [Spark] = []
    var color: Color = .white
    var count: Int = 8

    struct Spark: Identifiable {
        let id = UUID()
        var angle: Double
        var distance: CGFloat = 0
        var opacity: Double = 1
    }

    func body(content: Content) -> some View {
        content
            .overlay(
                ZStack {
                    ForEach(sparks) { s in
                        Circle()
                            .fill(color)
                            .frame(width: 4, height: 4)
                            .offset(
                                x: cos(s.angle) * s.distance,
                                y: sin(s.angle) * s.distance
                            )
                            .opacity(s.opacity)
                    }
                }
            )
            .simultaneousGesture(
                TapGesture().onEnded { _ in fire() }
            )
    }

    private func fire() {
        sparks = (0..<count).map { i in
            Spark(angle: Double(i) / Double(count) * 2 * .pi)
        }
        withAnimation(.easeOut(duration: 0.4)) {
            for i in sparks.indices {
                sparks[i].distance = 36
                sparks[i].opacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            sparks.removeAll()
        }
    }
}

extension View {
    func clickSpark(color: Color = .white, count: Int = 8) -> some View {
        modifier(ClickSpark(color: color, count: count))
    }
}
