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

/// 心动按钮中心（全局坐标）偏好键：供飞行动画定位起点
private struct HeartCenterKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}

struct FullPlayerView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var theme: ThemeSettings
    @EnvironmentObject private var favorites: FavoriteStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coverFlyNamespace) private var coverNS

    @State private var showLyrics = false
    @GestureState private var dragOffset: CGFloat = 0
    @StateObject private var coverColor = CoverColorExtractor()
    @State private var showSleepTimer = false
    @ObservedObject private var sleepTimer = SleepTimerManager.shared

    // v4.2 心动飞行动画：0=静止，1=出现在按钮处，2=飞往底部（朝 TabBar"我的"方向）
    @Namespace private var heartNS
    @State private var heartPhase = 0
    @State private var heartButtonGlobal: CGPoint = .zero

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

                // 歌曲信息 + 收藏（心动飞行动画）
                if let track = player.currentTrack {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
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
                        Spacer()
                        favoriteButton(for: track)
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

            // v4.2 心动飞行动画层（在播放页内，保证可见）
            heartFlyLayer
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

    // MARK: - 封面（v4.2：从列表 cell 飞进来的 hero 转场）

    private var coverView: some View {
        Group {
            if let ns = coverNS,
               let flyID = player.coverFlySongID,
               flyID == player.currentTrack?.onlineSongId {
                coverContent
                    .matchedGeometryEffect(id: "coverfly", in: ns, isSource: player.showFullPlayer)
            } else {
                coverContent
            }
        }
        .frame(width: 280, height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 12)
    }

    private var coverContent: some View {
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
    }

    // MARK: - 收藏 + 心动飞行动画（v4.2）

    /// 收藏按钮：点按后爱心从按钮处飞往屏幕底部（朝 TabBar"我的"方向），
    /// 用 matchedGeometryEffect 配对按钮起点与底部落点。
    /// 说明：FullPlayer 是 fullScreenCover，TabBar 被盖在下面看不见，
    /// 跨 cover 的飞行不可见，所以落点放在播放页底部、方向指向"我的"。
    private func favoriteButton(for track: Track) -> some View {
        let isFav = favorites.isFavorite(track)
        return Button {
            startHeartFly(track: track, currentlyFavorite: isFav)
        } label: {
            Image(systemName: isFav ? "heart.fill" : "heart")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(isFav ? .red : AppleTheme.secondaryLabel)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .scaleEffect(heartPhase == 1 ? 1.25 : 1.0)
        }
        .pressable()
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: HeartCenterKey.self,
                    value: CGPoint(x: geo.frame(in: .global).midX, y: geo.frame(in: .global).midY)
                )
            }
        )
        .onPreferenceChange(HeartCenterKey.self) { heartButtonGlobal = $0 }
        .animation(.gsapBackOut, value: heartPhase == 1)
    }

    private func startHeartFly(track: Track, currentlyFavorite: Bool) {
        guard heartPhase == 0 else { return }
        // 阶段 1：飞行的爱心出现在按钮位置（成为几何源）
        heartPhase = 1
        // 下一 runloop 切到阶段 2：落点成为几何源，爱心飞过去
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                heartPhase = 2
            }
            // 落地后收尾：真正切换收藏状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                favorites.toggle(track)
                heartPhase = 0
            }
        }
        // 取消收藏也给同样的飞行反馈（心飞走）
        _ = currentlyFavorite
    }

    /// 飞行的爱心 overlay + 底部落点（都在 FullPlayer 内，保证可见）
    private var heartFlyLayer: some View {
        ZStack {
            // 落点：屏幕底部中央（TabBar"我的"方向）
            VStack {
                Spacer()
                Color.clear
                    .frame(width: 44, height: 44)
                    .matchedGeometryEffect(id: "fly-heart", in: heartNS, isSource: heartPhase == 2)
                    .padding(.bottom, 120)
            }
            // 飞行的爱心
            GeometryReader { proxy in
                if heartPhase > 0 {
                    let origin = proxy.frame(in: .global).origin
                    let local = CGPoint(
                        x: heartButtonGlobal.x - origin.x,
                        y: heartButtonGlobal.y - origin.y
                    )
                    Image(systemName: "heart.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.red)
                        .matchedGeometryEffect(id: "fly-heart", in: heartNS, isSource: heartPhase == 1)
                        .position(local)
                        .opacity(heartPhase == 2 ? 0.9 : 1.0)
                }
            }
        }
        .allowsHitTesting(false)
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

    // MARK: - 进度条（波形，可拖拽）

    private var progressView: some View {
        // 在线歌曲用服务端预计算波形；本地文件用默认样式
        WaveformProgressView(
            trackId: player.currentTrack?.onlineSongId,
            accentColor: pageAccent
        )
        .environmentObject(player)
    }

    // MARK: - 玻璃控制条

    private var controlBar: some View {
        HStack(spacing: 0) {
            Spacer()
            Button { Haptics.tap(); player.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(AppleTheme.label)
                    .frame(width: 60, height: 60)
                    .contentShape(Rectangle())
            }
            .pressable()
            Spacer()
            Button { Haptics.tap(); player.togglePlayPause() } label: {
                MorphPlayIcon(isPlaying: player.isPlaying, size: 40)
                    .foregroundColor(AppleTheme.label)
                    .frame(width: 72, height: 72)
                    .contentShape(Rectangle())
            }
            .pressable()
            .clickSpark(color: pageAccent.opacity(0.9))
            Spacer()
            Button { Haptics.tap(); player.next() } label: {
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
