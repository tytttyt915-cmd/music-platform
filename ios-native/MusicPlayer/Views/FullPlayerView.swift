import SwiftUI

// MARK: - FullPlayerView（2026-10-09 Apple 原生风重做）
//
// 职责：全屏播放页（重点界面）。
//   - 大封面（280pt，圆角 16，阴影）；无封面用音符占位
//   - 歌名（title2/bold）+ 歌手（次文字）
//   - pill 形进度条：可拖拽 seek，1:1 跟手
//   - Liquid Glass 控制条：上一曲 / 播放暂停 / 下一曲，按压缩放 0.97
//   - 下滑手势关闭：1:1 跟手，中途可打断，松手后弹簧回位或关闭
//   - 歌词开关 → LyricsView

struct FullPlayerView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var theme: ThemeSettings
    @Environment(\.dismiss) private var dismiss

    @State private var sliderValue: Double = 0
    @State private var isSeeking = false
    @State private var showLyrics = false
    @GestureState private var dragOffset: CGFloat = 0
    @StateObject private var coverColor = CoverColorExtractor()
    @State private var showSleepTimer = false
    @ObservedObject private var sleepTimer = SleepTimerManager.shared

    private var dismissThreshold: CGFloat { 140 }

    /// 当前页面的强调色：封面主色优先，未提取到时用主题色
    private var pageAccent: Color {
        coverColor.isReady ? coverColor.themeColor : theme.accentColor
    }

    var body: some View {
        ZStack {
            // Vanta.js WAVES 风格音频律动背景（iOS 17+ Metal Shader，低版本/低电量自动降级）
            // tint 由封面主色驱动
            AudioReactiveBackground(coverTint: pageAccent)

            VStack(spacing: 0) {
                // 顶部把手 + 关闭
                HStack {
                    Spacer(minLength: 44)
                    Capsule()
                        .fill(AppleTheme.tertiaryLabel.opacity(0.5))
                        .frame(width: 36, height: 5)
                    Spacer(minLength: 0)
                    // 睡眠定时入口
                    Button { showSleepTimer = true } label: {
                        Image(systemName: sleepTimer.isActive ? "moon.zzz.fill" : "moon.zzz")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(sleepTimer.isActive ? pageAccent : AppleTheme.secondaryLabel)
                            .frame(width: 44, height: 32)
                            .contentShape(Rectangle())
                    }
                    .pressable()
                    .sheet(isPresented: $showSleepTimer) {
                        SleepTimerView()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Spacer(minLength: 8)

                // 封面
                coverView
                    .padding(.horizontal, 32)

                Spacer(minLength: 12)

                // 歌曲信息
                if let track = player.currentTrack {
                    VStack(spacing: 6) {
                        BlurText(text: track.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(AppleTheme.label)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.body)
                            .foregroundColor(AppleTheme.secondaryLabel)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 32)
                }

                // 歌词开关
                if let track = player.currentTrack, track.onlineSongId != nil {
                    Button(showLyrics ? "隐藏歌词" : "显示歌词") {
                        withAnimation(.gsapPower3Out) { showLyrics.toggle() }
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(pageAccent)
                    .pressable()
                    .padding(.top, 12)
                }

                // 歌词
                if showLyrics,
                   let track = player.currentTrack,
                   let songId = track.onlineSongId {
                    LyricsView(songId: songId)
                        .frame(height: 180)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer(minLength: 12)

                // 进度条
                progressView
                    .padding(.horizontal, 32)

                // 玻璃控制条
                controlBar
                    .padding(.horizontal, 48)
                    .padding(.top, 20)

                Spacer(minLength: 24)
            }
        }
        .offset(y: dragOffset)
        .gesture(dismissGesture)
        .animation(.gsapPower3Out, value: dragOffset == 0)
        // 切歌时提取封面主色，驱动整页主题
        .onChange(of: player.currentTrack?.id) { _ in
            coverColor.extract(from: player.currentTrack?.artworkURL)
        }
        .onAppear {
            coverColor.extract(from: player.currentTrack?.artworkURL)
        }
    }

    // MARK: - 封面

    private var coverView: some View {
        Group {
            if let url = player.currentTrack?.artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        coverFallback
                    }
                }
            } else {
                coverFallback
            }
        }
        .frame(width: 280, height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 12)
    }

    private var coverFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.accentColor.opacity(0.25))
            Image(systemName: "music.note")
                .font(.system(size: 80, weight: .semibold))
                .foregroundColor(theme.accentColor)
        }
    }

    // MARK: - 进度条（pill，可拖拽）

    private var progressView: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { isSeeking ? sliderValue : player.currentTime },
                    set: { sliderValue = $0 }
                ),
                in: 0...(player.duration > 0 ? player.duration : 1),
                onEditingChanged: { editing in
                    isSeeking = editing
                    if !editing {
                        player.seek(to: sliderValue)
                    }
                }
            )
            .tint(pageAccent)

            HStack {
                Text(formatDuration(isSeeking ? sliderValue : player.currentTime))
                Spacer()
                Text(formatDuration(player.duration))
            }
            .font(.caption)
            .foregroundColor(AppleTheme.secondaryLabel)
            .monospacedDigit()
        }
    }

    // MARK: - 玻璃控制条

    private var controlBar: some View {
        HStack(spacing: 0) {
            Spacer()
            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(AppleTheme.label)
                    .frame(width: 60, height: 60)
                    .contentShape(Rectangle())
            }
            .pressable()
            Spacer()
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundColor(AppleTheme.label)
                    .contentShape(Rectangle())
            }
            .pressable()
            Spacer()
            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(AppleTheme.label)
                    .frame(width: 60, height: 60)
                    .contentShape(Rectangle())
            }
            .pressable()
            Spacer()
        }
        .padding(.vertical, 12)
        .liquidGlass(cornerRadius: 28)
    }

    // MARK: - 下滑关闭手势（1:1 跟手，可打断）

    private var dismissGesture: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                // 只响应下滑
                state = max(value.translation.height, 0)
            }
            .onEnded { value in
                // 下滑超阈值或快速下滑 → 关闭；否则弹簧回位
                let velocity = value.predictedEndTranslation.height - value.translation.height
                if value.translation.height > dismissThreshold || velocity > 400 {
                    dismiss()
                }
                // 回位由 .animation(.gsapPower3Out, value: dragOffset == 0) 处理
            }
    }
}
