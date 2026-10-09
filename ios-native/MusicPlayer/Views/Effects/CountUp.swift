import SwiftUI

// MARK: - CountUp（2026-10-09，React Bits 适配）
//
// 数字滚动增长：从 from 滚到 target，easeOutCubic 缓动。
// 给播放量、歌单歌曲数等加上"数据感"。
//
//   - TimelineView(.animation) 驱动，不用 Timer；播完自动换静态文本，不空转耗电
//   - 时长可配（duration，默认 1.2s）；target 变化时重新从当前值滚
//   - 格式可配：默认纯数字；CountUp.compactFormatter 给中文环境（万/亿）
//   - .monospacedDigit() 防跳动；accessibility 读最终值
//   - 减少动态效果：开启时直接显示最终值
//   - 深色/浅色：纯文本，自动适配
//
// 用法：
//   CountUp(target: 12345)
//   CountUp(target: playCount, duration: 1.5, formatter: CountUp.compactFormatter)
//       .font(.caption).foregroundColor(AppleTheme.secondaryLabel)

struct CountUp: View {
    var target: Int
    var duration: Double = 1.2
    var from: Int = 0
    var formatter: (Int) -> String = { "\($0)" }

    @State private var startDate: Date? = nil
    @State private var finished: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion || finished || duration <= 0 {
                Text(formatter(target))
            } else {
                TimelineView(.animation) { context in
                    let value = interpolatedValue(at: context.date)
                    Text(formatter(value))
                        .onChange(of: value >= target) { done in
                            if done { finished = true }
                        }
                }
            }
        }
        .monospacedDigit()
        .accessibilityLabel("\(target)")
        .onAppear {
            startDate = Date()
            finished = false
        }
        .onChange(of: target) { _ in
            // target 变化时重播
            startDate = Date()
            finished = false
        }
    }

    private func interpolatedValue(at date: Date) -> Int {
        guard let start = startDate, duration > 0 else { return target }
        let elapsed = date.timeIntervalSince(start)
        let progress = min(max(elapsed / duration, 0), 1)
        // easeOutCubic：起步快、收尾缓，数字滚动的经典缓动
        let eased = 1 - pow(1 - progress, 3)
        let delta = Double(target - from)
        return from + Int((delta * eased).rounded())
    }
}

// MARK: - 中文紧凑格式：1234 → "1234"，12345 → "1.2万"，123456789 → "1.2亿"

extension CountUp {
    static let compactFormatter: (Int) -> String = { value in
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        switch absValue {
        case 100_000_000...:
            return String(format: "%@%.1f亿", sign, Double(absValue) / 100_000_000)
        case 10_000...:
            return String(format: "%@%.1f万", sign, Double(absValue) / 10_000)
        default:
            return "\(value)"
        }
    }
}
