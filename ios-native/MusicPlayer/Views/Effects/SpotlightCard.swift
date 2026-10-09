import SwiftUI

// MARK: - SpotlightCard（2026-10-09，React Bits 适配）
//
// 触摸聚光灯卡片：手指按住卡片时，一束径向光跟随触摸点。
// React Bits 的招牌交互之一（Web 端靠 hover，iOS 上靠触摸）。
//
//   - DragGesture(minimumDistance: 0) 追踪触摸位置 → RadialGradient 的 center 跟随
//   - 松手后光斑消失
//   - 用 GeometryReader 取真实尺寸换算 UnitPoint，不写死宽高
//   - 减少动态效果：开启时不渲染光斑
//   - 深色/浅色：光斑默认白色半透明，双模式可用；调用方可自定义颜色
//
// 用法：
//   SpotlightCard {
//       VStack { ... } // 歌单卡片 / 推荐卡片内容
//   }

struct SpotlightCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var spotlightColor: Color = .white
    var spotlightOpacity: Double = 0.16
    var spotlightRadius: CGFloat = 140

    @State private var location: CGPoint? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            content()
                .frame(width: geo.size.width, height: geo.size.height)
                .overlay(spotlightOverlay(size: geo.size))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { location = $0.location }
                        .onEnded { _ in location = nil }
                )
        }
    }

    @ViewBuilder
    private func spotlightOverlay(size: CGSize) -> some View {
        if !reduceMotion, size.width > 0, size.height > 0 {
            // 无触摸时把光斑停在中心并淡出，避免 if-let 插入/移除时的生硬跳变
            let point = location ?? CGPoint(x: size.width / 2, y: size.height / 2)
            let unit = UnitPoint(
                x: max(0, min(1, point.x / size.width)),
                y: max(0, min(1, point.y / size.height))
            )
            RadialGradient(
                gradient: Gradient(colors: [
                    spotlightColor.opacity(spotlightOpacity),
                    spotlightColor.opacity(0)
                ]),
                center: unit,
                startRadius: 0,
                endRadius: spotlightRadius
            )
            .opacity(location == nil ? 0 : 1)
            .animation(.gsapPower2Out, value: location == nil)
        }
    }
}
