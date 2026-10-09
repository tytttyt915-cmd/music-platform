import SwiftUI

/// React Bits DecryptedText：乱码逐字"解码"成正文（黑客帝国感）。
/// 用途：LyricsView 歌词加载中的占位——"在解密"而不是"在等待"。
struct DecryptedText: View {
    var target: String
    var duration: Double = 1.0
    var charset: [String] = ["█", "▓", "▒", "░", "<", ">", "/", "*", "+"]

    @State private var displayed: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(target: String, duration: Double = 1.0) {
        self.target = target
        self.duration = duration
        _displayed = State(initialValue: target.isEmpty ? "" : String(repeating: "█", count: target.count))
    }

    var body: some View {
        Text(displayed)
            .monospaced()
            .onAppear {
                if reduceMotion {
                    displayed = target
                } else {
                    decrypt()
                }
            }
    }

    private func decrypt() {
        let chars = Array(target)
        guard !chars.isEmpty else { return }
        let stepDelay = duration / Double(chars.count)
        Task {
            for i in 0..<chars.count {
                let decoded = String(chars.prefix(i + 1))
                let scrambled = (i + 1..<chars.count)
                    .map { _ in charset.randomElement() ?? "█" }
                    .joined()
                displayed = decoded + scrambled
                try? await Task.sleep(nanoseconds: UInt64(stepDelay * 1e9))
            }
            displayed = target
        }
    }
}
