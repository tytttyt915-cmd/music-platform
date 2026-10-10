import SwiftUI

/// React Bits TextType：逐字打出，带光标闪烁。
/// 用途：搜索框 placeholder 轮播——把"空状态"变成"邀请"。
struct TextType: View {
    var texts: [String]
    var typeSpeed: Double = 0.06      // 打字速度（秒/字）
    var deleteSpeed: Double = 0.03   // 删除速度
    var pauseDuration: Double = 1.6  // 打完停留
    var cursor: String = "▍"

    @State private var displayed = ""
    @State private var textIndex = 0
    @State private var cursorVisible = true
    @State private var stopFlag = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Text(displayed)
            Text(cursor)
                .opacity(cursorVisible ? 1 : 0)
        }
        .onAppear {
            if reduceMotion {
                displayed = texts.first ?? ""
            } else {
                stopFlag = false
                runLoop()
            }
        }
        .onDisappear { stopFlag = true }
    }

    private func runLoop() {
        Task {
            while !stopFlag {
                let full = texts[textIndex % texts.count]
                for i in 1...full.count {
                    if stopFlag { return }
                    displayed = String(full.prefix(i))
                    try? await Task.sleep(nanoseconds: UInt64(typeSpeed * 1e9))
                }
                try? await Task.sleep(nanoseconds: UInt64(pauseDuration * 1e9))
                for i in stride(from: full.count - 1, through: 0, by: -1) {
                    if stopFlag { return }
                    displayed = String(full.prefix(i))
                    try? await Task.sleep(nanoseconds: UInt64(deleteSpeed * 1e9))
                }
                textIndex += 1
            }
        }
        Task {
            while !stopFlag {
                cursorVisible.toggle()
                try? await Task.sleep(nanoseconds: 530_000_000)
            }
        }
    }
}
