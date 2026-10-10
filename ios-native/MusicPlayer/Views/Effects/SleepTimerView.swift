import SwiftUI

/// 睡眠定时选择器（弹窗）
struct SleepTimerView: View {
    @ObservedObject private var timer = SleepTimerManager.shared
    @Environment(\.dismiss) private var dismiss

    private let presets: [(String, Int)] = [
        ("15 分钟", 15 * 60),
        ("30 分钟", 30 * 60),
        ("45 分钟", 45 * 60),
        ("1 小时", 60 * 60),
        ("2 小时", 2 * 60 * 60),
        ("播完这首", -1),
    ]

    var body: some View {
        NavigationStack {
            List {
                if timer.isActive {
                    Section {
                        HStack {
                            Label("剩余时间", systemImage: "moon.zzz.fill")
                            Spacer()
                            Text(timer.isFadingOut ? "正在淡出…" : timer.remainingText)
                                .font(.body.monospacedDigit())
                                .foregroundColor(Color.blue)
                        }
                        Button("取消定时", role: .destructive) {
                            timer.cancel()
                        }
                    }
                }
                Section("定时关闭") {
                    ForEach(presets, id: \.0) { name, seconds in
                        Button {
                            if seconds > 0 {
                                timer.start(seconds: seconds, presetLabel: name)
                            } else {
                                // -1 = 播完当前这首
                                timer.startFinishCurrentSong()
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Text(name)
                                Spacer()
                                if timer.activePreset == name {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Color.blue)
                                }
                            }
                        }
                    }
                }
                Section {
                    Text("时间到后音量会在 30 秒内逐渐降低，然后暂停播放。")
                        .font(.body)
                        .foregroundColor(AppleTheme.secondaryLabel)
                }
            }
            .navigationTitle("睡眠定时")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
