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
    // Beans #4 教训：用户手动滚歌词时暂停自动跟随，3 秒无操作再恢复
    @State private var userDragging = false
    @State private var resumeTask: DispatchWorkItem?

    var body: some View {
        Group {
            if isLoading {
                DecryptedText(target: "正在解码歌词…", duration: 0.9)
                    .font(.body)
                    .foregroundColor(AppleTheme.secondaryLabel)
            } else if lines.isEmpty {
                Text("暂无歌词")
                    .font(.body)
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
                    // 检测用户拖拽：拖拽时暂停跟随
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { _ in
                                userDragging = true
                                resumeTask?.cancel()
                            }
                            .onEnded { _ in
                                // 3 秒无操作后恢复跟随
                                let task = DispatchWorkItem { userDragging = false }
                                resumeTask = task
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
                            }
                    )
                    .onChange(of: currentIndex) { idx in
                        guard !userDragging, idx >= 0, idx < lines.count else { return }
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

// MARK: - LyricsPreview（Beans 风格：歌词内嵌预览）
//
// 播放页封面下方直接显示 3 行歌词（上一行/当前行/下一行），
// 当前行高亮放大。点按展开全屏歌词。不藏在按钮后面。
struct LyricsPreview: View {
    let songId: String
    @EnvironmentObject private var music: MusicService
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var theme: ThemeSettings

    @State private var lines: [LyricLine] = []

    private var currentIndex: Int {
        let t = player.currentTime
        var idx = -1
        for (i, line) in lines.enumerated() {
            if line.time <= t { idx = i } else { break }
        }
        return idx
    }

    /// 当前行上下各 1 行
    private var visibleLines: [(line: LyricLine, isCurrent: Bool)] {
        guard !lines.isEmpty else { return [] }
        let c = max(currentIndex, 0)
        let start = max(c - 1, 0)
        let end = min(c + 1, lines.count - 1)
        return (start...end).map { i in
            (lines[i], i == c)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            if lines.isEmpty {
                Text("暂无歌词")
                    .font(.body)
                    .foregroundColor(AppleTheme.tertiaryLabel)
            } else {
                ForEach(visibleLines, id: \.line.id) { item in
                    Text(item.line.text)
                        .font(.system(size: item.isCurrent ? 17 : 14,
                                      weight: item.isCurrent ? .semibold : .regular))
                        .foregroundColor(item.isCurrent ? AppleTheme.label : AppleTheme.tertiaryLabel)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .animation(.gsapPower2Out, value: currentIndex)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { load() }
    }

    private func load() {
        Task {
            do {
                let result = try await music.lyrics(id: songId)
                await MainActor.run { lines = result }
            } catch {
                // 无歌词就空着，不打扰
            }
        }
    }
}
