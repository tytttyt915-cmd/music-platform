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

    /// Beans 风格封面底：封面图模糊放大铺满 + 深色压暗。
    /// 主色可见（不再是纯黑），上层文字用白色保证对比度。
    /// [Beans#背景] [impeccable-Contrast]
    private var coverBlurBackground: some View {
        Group {
            if let url = player.currentTrack?.artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 60, opaque: true)
                            .overlay(
                                // 压暗：顶部 40% → 中部 50% → 底部 60%
                                // （上层 AudioReactiveBackground 自带罩层，总压暗足够白字对比度）
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.40),
                                        Color.black.opacity(0.50),
                                        Color.black.opacity(0.60)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    default:
                        // 无封面/加载失败：用主色的深色渐变兜底（不是纯黑）
                        coverTintFallback
                    }
                }
            } else {
                coverTintFallback
            }
        }
        .ignoresSafeArea()
    }

    /// 主色深色渐变兜底：明度压到 0.10~0.22，有色相但保持深色氛围
    /// [impeccable-Quieter] 饱和度钳 0.85
    private var coverTintFallback: some View {
        let ui = UIColor(pageAccent)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let darkB = min(max(b * 0.30, 0.10), 0.22)
        let base = Color(hue: Double(h), saturation: Double(min(s, 0.85)), brightness: Double(darkB))
        return LinearGradient(
            colors: [base, base.opacity(0.55), Color(red: 0.03, green: 0.03, blue: 0.055)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        ZStack {
            // Beans 风格：封面模糊放大 + 压暗做底（主色可见，不再是纯黑）
            coverBlurBackground

            // Vanta.js WAVES 风格音频律动背景（iOS 17+ Metal Shader，低版本/低电量自动降级）
            // tint 由封面主色驱动；半透明叠加，让底层封面色透出来
            AudioReactiveBackground(coverTint: pageAccent)
                .opacity(0.55)

            VStack(spacing: 0) {
                // Beans 风格顶栏：返回（玻璃圆）｜ 正在播放/歌名双行 ｜ 睡眠+更多（玻璃圆）
                beansTopBar
                    .padding(.top, 8)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)

                // 黑胶封面（圆形，播放时旋转）
                vinylCover
                    .padding(.top, 8)

                // 歌曲信息 + 收藏（心动飞行动画）
                if let track = player.currentTrack {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
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
                    .padding(.top, 12)
                }

                // Beans 风格：歌词直接内嵌预览（3 行，当前行高亮），不藏在按钮后
                if let track = player.currentTrack, track.onlineSongId != nil {
                    LyricsPreview(songId: track.onlineSongId!)
                        .frame(height: 88)
                        .padding(.top, 8)
                        .onTapGesture {
                            // 点歌词展开全屏歌词
                            withAnimation(.gsapPower3Out) { showLyrics.toggle() }
                        }
                }

                // 全屏歌词（展开态）
                if showLyrics,
                   let track = player.currentTrack,
                   let songId = track.onlineSongId {
                    LyricsView(songId: songId)
                        .frame(maxHeight: 220)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer(minLength: 8)

                // 进度条 + ±15s（Beans 播客级精细控制）
                progressWithSkip
                    .padding(.horizontal, 24)

                // Beans 风格 5 按钮：循环｜上一曲｜播放(大)｜下一曲｜队列
                beansControlBar
                    .padding(.horizontal, 32)
                    .padding(.top, 16)

                Spacer(minLength: 20)
            }

            // v4.2 心动飞行动画层（在播放页内，保证可见）
            heartFlyLayer
        }
        .offset(y: dragOffset)
        .gesture(dismissGesture)
        .animation(.gsapPower3Out, value: dragOffset == 0)
        // 播放页强制深色：背景是深色氛围，文字必须用白色（修复黑字 on 黑底隐形）
        // [impeccable-Contrast] 深色底 + 白字，对比度 > 7:1
        .preferredColorScheme(.dark)
        // 切歌时提取封面主色，驱动整页主题
        .onChange(of: player.currentTrack?.id) { _ in
            coverColor.extract(from: player.currentTrack?.artworkURL)
        }
        .onAppear {
            coverColor.extract(from: player.currentTrack?.artworkURL)
        }
    }

    // MARK: - Beans 风格顶栏（对称三件套）

    private var beansTopBar: some View {
        HStack {
            // 返回（玻璃圆）
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppleTheme.label)
                    .frame(width: 40, height: 40)
                    .liquidGlass(cornerRadius: 20)
                    .contentShape(Circle())
            }
            .pressable()

            Spacer()

            // 正在播放 / 歌名双行
            VStack(spacing: 2) {
                Text("正在播放")
                    .font(.caption)
                    .foregroundColor(AppleTheme.secondaryLabel)
                if let track = player.currentTrack {
                    Text(track.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(AppleTheme.label)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 睡眠定时（玻璃圆）
            Button { showSleepTimer = true } label: {
                Image(systemName: sleepTimer.isActive ? "moon.zzz.fill" : "moon.zzz")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(sleepTimer.isActive ? pageAccent : AppleTheme.label)
                    .frame(width: 40, height: 40)
                    .liquidGlass(cornerRadius: 20)
                    .contentShape(Circle())
            }
            .pressable()
            .sheet(isPresented: $showSleepTimer) {
                SleepTimerView()
            }

            // 更多（玻璃圆）
            Button { Haptics.tap() } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppleTheme.label)
                    .frame(width: 40, height: 40)
                    .liquidGlass(cornerRadius: 20)
                    .contentShape(Circle())
            }
            .pressable()
        }
    }

    // MARK: - 黑胶封面（Beans 风格：圆形，播放时旋转）

    @State private var vinylRotation: Double = 0
    @State private var vinylTimer: Timer?

    private var vinylCover: some View {
        ZStack {
            // 黑胶底盘（比封面略大，营造黑胶感）
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: 292, height: 292)
                .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
            // 黑胶纹理圈
            ForEach([262, 232, 202], id: \.self) { d in
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    .frame(width: CGFloat(d), height: CGFloat(d))
            }
            // 封面（圆形，hero 转场 + 旋转）
            vinylCoverImage
                .frame(width: 240, height: 240)
                .clipShape(Circle())
            // 中心轴孔
            Circle()
                .fill(AppleTheme.background)
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .fill(pageAccent)
                        .frame(width: 10, height: 10)
                )
        }
        .rotationEffect(.degrees(vinylRotation))
        .onChange(of: player.isPlaying) { playing in
            playing ? startVinyl() : stopVinyl()
        }
        .onAppear {
            if player.isPlaying { startVinyl() }
        }
        .onDisappear { stopVinyl() }
    }

    /// 黑胶上的封面图（带 hero 转场配对）
    private var vinylCoverImage: some View {
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
    }

    private func startVinyl() {
        stopVinyl()
        // 12 秒一圈，0.05s 步进
        vinylTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            vinylRotation += 1.5
            if vinylRotation >= 360 { vinylRotation -= 360 }
        }
    }

    private func stopVinyl() {
        vinylTimer?.invalidate()
        vinylTimer = nil
    }

    // MARK: - 封面内容（v4.2 hero 转场 + Beans 黑胶共用）

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
        // Beans #5 教训：数据先行——先 toggle 收藏（动画中断也不丢），
        // 飞行只是纯视觉反馈
        favorites.toggle(track)
        Haptics.tap()
        // 阶段 1：飞行的爱心出现在按钮位置（成为几何源）
        heartPhase = 1
        // 下一 runloop 切到阶段 2：落点成为几何源，爱心飞过去
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                heartPhase = 2
            }
            // 落地后收尾
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                heartPhase = 0
            }
        }
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

    // MARK: - 进度条 + ±15s（Beans 播客级精细控制）

    private var progressWithSkip: some View {
        HStack(spacing: 12) {
            // 快退 15s
            Button {
                Haptics.tap()
                let t = max(player.currentTime - 15, 0)
                player.seek(to: t)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(AppleTheme.secondaryLabel)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .pressable()

            progressView

            // 快进 15s
            Button {
                Haptics.tap()
                let t = min(player.currentTime + 15, player.duration)
                player.seek(to: t)
            } label: {
                Image(systemName: "goforward.15")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(AppleTheme.secondaryLabel)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .pressable()
        }
    }

    // MARK: - Beans 风格 5 按钮：循环｜上一曲｜播放(大)｜下一曲｜队列

    @State private var showQueue = false

    private var beansControlBar: some View {
        HStack(spacing: 0) {
            // 循环模式
            Button { Haptics.tap(); player.cycleRepeatMode() } label: {
                Image(systemName: player.repeatMode.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(player.repeatMode == .sequential ? AppleTheme.secondaryLabel : pageAccent)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .pressable()

            Spacer()

            // 上一曲
            Button { Haptics.tap(); player.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(AppleTheme.label)
                    .frame(width: 60, height: 60)
                    .contentShape(Rectangle())
            }
            .pressable()

            Spacer()

            // 播放/暂停（大，视觉焦点）
            Button { Haptics.tap(); player.togglePlayPause() } label: {
                MorphPlayIcon(isPlaying: player.isPlaying, size: 38)
                    .foregroundColor(.white)
                    .frame(width: 76, height: 76)
                    .background(pageAccent)
                    .clipShape(Circle())
                    .shadow(color: pageAccent.opacity(0.4), radius: 16, x: 0, y: 8)
                    .contentShape(Circle())
            }
            .pressable()
            .clickSpark(color: pageAccent.opacity(0.9))

            Spacer()

            // 下一曲
            Button { Haptics.tap(); player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(AppleTheme.label)
                    .frame(width: 60, height: 60)
                    .contentShape(Rectangle())
            }
            .pressable()

            Spacer()

            // 队列
            Button { Haptics.tap(); showQueue = true } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(AppleTheme.secondaryLabel)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .pressable()
            .sheet(isPresented: $showQueue) {
                QueueSheet()
            }
        }
        .padding(.vertical, 8)
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

// MARK: - QueueSheet（播放队列）

/// Beans 风格 5 按钮中的"队列"：当前播放列表，点按切歌
struct QueueSheet: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(player.currentQueue.enumerated()), id: \.element.id) { idx, track in
                    Button {
                        Haptics.tap()
                        player.play(at: idx)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            if idx == player.queueIndex {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 14))
                            } else {
                                Text("\(idx + 1)")
                                    .font(.caption)
                                    .foregroundColor(AppleTheme.tertiaryLabel)
                                    .frame(width: 20)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.body)
                                    .foregroundColor(idx == player.queueIndex ? .orange : AppleTheme.label)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundColor(AppleTheme.secondaryLabel)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("播放队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
