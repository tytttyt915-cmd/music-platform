import UIKit

// MARK: - Haptics（对标 Beans BeansHaptics）
//
// 铁律①：触觉也是"反馈"。100ms 因果窗口内给触觉确认，
// 手指"按上了"的感知 = 视觉（scale+brightness）+ 触觉（haptic）双通道。
//
// 用法：
//   Button { Haptics.tap(); player.togglePlayPause() } label: { ... }
//   // 重要操作：Haptics.medium()

enum Haptics {
    /// 轻触：普通按钮点击（对标 BeansHaptics.tap）
    static func tap() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        g.impactOccurred()
    }

    /// 中触：重要操作（下载、换源、删除）（对标 BeansHaptics.medium）
    static func medium() {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare()
        g.impactOccurred()
    }

    /// 成功：操作完成确认（如收藏成功、导入完成）
    static func success() {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.success)
    }

    /// 警告：操作失败或需要确认
    static func warning() {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.warning)
    }
}
