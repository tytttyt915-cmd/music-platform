import SwiftUI

// MARK: - LyricsView（2026-10-09 Apple 原生风重做）
//
// 职责：歌词页。
//   - 当前行高亮（强调色 + 粗体 + 放大），其余行次文字
//   - 自动滚动到当前行（anchor .center，弹簧动画）
//   - 无歌词显示空态

struct LyricsView: View {
    let songId: String
    @EnvironmentObject private var music: MusicService
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var theme: ThemeSettings

    @State private var lines: [LyricLine] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if lines.isEmpty {
                Text("暂无歌词")
                    .font(.subheadline)
                    .foregroundColor(AppleTheme.secondaryLabel)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(lines) { line in
                                let current = isCurrent(line)
                                Text(line.text)
                                    .font(.system(size: current ? 19 : 15, weight: current ? .bold : .regular))
                                    .foregroundColor(current ? theme.accentColor : AppleTheme.secondaryLabel)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .id(line.id)
                                    .animation(.gsapPower2Out, value: current)
                            }
                        }
                        .padding(.vertical, 20)
                        .padding(.horizontal, 24)
                    }
                    .onChange(of: currentIndex) { idx in
                        guard idx >= 0, idx < lines.count else { return }
                        withAnimation(.gsapPower2Out) {
                            proxy.scrollTo(lines[idx].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .onAppear { load() }
    }

    private var currentIndex: Int {
        let t = player.currentTime
        var idx = -1
        for (i, line) in lines.enumerated() {
            if line.time <= t { idx = i } else { break }
        }
        return idx
    }

    private func isCurrent(_ line: LyricLine) -> Bool {
        guard let idx = lines.firstIndex(where: { $0.id == line.id }) else { return false }
        return idx == currentIndex
    }

    private func load() {
        isLoading = true
        Task {
            do {
                let result = try await music.lyrics(id: songId)
                await MainActor.run {
                    lines = result
                    isLoading = false
                }
            } catch {
                await MainActor.run { isLoading = false }
            }
        }
    }
}
