import SwiftUI

// MARK: - AppleTheme（2026-10-09）
//
// 职责：Apple 原生风设计语言在 SwiftUI 的集中落地。
//   - 颜色：系统语义色（label / secondaryLabel / systemBackground…），
//     强调色走 ThemeSettings.accentColor（用户可选，默认红）
//   - 形状：卡片 18pt、控件 10pt、CTA 胶囊；分隔线用原生 Divider
//   - 动效：弹簧为主。默认 damping 1.0（无回弹）；有动量时 0.8 回弹
//   - 交互：按压缩放 0.97（pointer-down 即时反馈）；拖拽 1:1 跟手、可打断
//   - Liquid Glass：iOS 26 用 .glassEffect()，低版本降级 .ultraThinMaterial
//
// 约定：所有 View 的颜色/圆角/动效从这里取，不硬编码。

// MARK: - 颜色

enum AppleTheme {
    /// 页面底
    static var background: Color { Color(.systemBackground) }
    /// 卡片底（secondarySystemBackground）
    static var cardBackground: Color { Color(.secondarySystemBackground) }
    /// 输入框底（tertiarySystemBackground）
    static var fieldBackground: Color { Color(.tertiarySystemBackground) }
    /// 主文字
    static var label: Color { Color(.label) }
    /// 次文字
    static var secondaryLabel: Color { Color(.secondaryLabel) }
    /// 三级文字
    static var tertiaryLabel: Color { Color(.tertiaryLabel) }

    /// 卡片圆角
    static let cardRadius: CGFloat = 18
    /// 控件圆角
    static let controlRadius: CGFloat = 10
    /// 列表行封面圆角
    static let artworkRadius: CGFloat = 8
}

// MARK: - 动效

extension Animation {
    /// 默认弹簧：无回弹，响应快。用于状态切换、显隐。
    static var appleDefault: Animation {
        .spring(response: 0.35, dampingFraction: 1.0, blendDuration: 0)
    }
    /// 带回弹：用于拖拽松手、有动量的场景。
    static var appleBouncy: Animation {
        .spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    }
    /// 快弹簧：按压反馈、小位移。
    static var appleSnappy: Animation {
        .spring(response: 0.25, dampingFraction: 1.0, blendDuration: 0)
    }

    // MARK: - GSAP easing 映射（2026-10-09）
    //
    // 把 GSAP 的经典缓动曲线映射到 SwiftUI，供全 App 统一使用。
    // 换算依据：~/workspace/trending/四工具适配.md（GSAP 章节）。

    /// GSAP "power2.out" ≈ easeOutQuad。
    /// 曲线：cubic-bezier(0.25, 0.46, 0.45, 0.94)。起步快、收尾缓。
    /// 场景：列表行出现/高亮切换、错误条消失、MiniPlayer 拖拽回位、歌词自动滚动。
    static var gsapPower2Out: Animation {
        .timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.35)
    }

    /// GSAP "power3.out" ≈ easeOutCubic。
    /// 曲线：cubic-bezier(0.215, 0.61, 0.355, 1)。比 power2.out 更陡的减速，干脆利落。
    /// 场景：播放页展开/收起、歌词面板切换、拖拽松手回位。
    static var gsapPower3Out: Animation {
        .timingCurve(0.215, 0.61, 0.355, 1.0, duration: 0.4)
    }

    /// GSAP "back.out(1.7)"：先过冲再回位，带一点弹性俏皮。
    /// 场景：弹窗/浮层出现（MiniPlayer 弹出、新建歌单 sheet 内容）。
    static var gsapBackOut: Animation {
        .spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0)
    }

    /// GSAP "elastic.out"：强回弹，果冻感。
    /// 场景：庆祝/强调时刻（如收藏成功的心跳），慎用——与 Apple 克制风格冲突。
    static var gsapElasticOut: Animation {
        .spring(response: 0.6, dampingFraction: 0.4, blendDuration: 0)
    }
}

// MARK: - 按压即时反馈（0.97 缩放）

/// Apple 原则：pointer-down 瞬间给反馈，不等松手。
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            // Beans-Music 对标：brightness 双通道比 opacity 更"物理"（opacity 0.85 显廉价）
            // spring(response: 0.24, dampingFraction: 0.82) 来自 Beans GlassPressButtonStyle
            .brightness(configuration.isPressed ? 0.025 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

extension View {
    /// 快捷：给任意 Button 加按压缩放
    func pressable(_ scale: CGFloat = 0.97) -> some View {
        buttonStyle(PressScaleStyle(scale: scale))
    }
}

// MARK: - Liquid Glass
//
// 说明：iOS 26 的原生 .glassEffect() 需要 Xcode 26（iOS 26 SDK）才能编译，
// 当前 CI 为 Xcode 16（iOS 18 SDK），故此处用 .ultraThinMaterial 实现玻璃质感。
// 待 CI 升级到 Xcode 26 后，把下面的 material 实现换成：
//     self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
// 即可获得原生 Liquid Glass（折射/染色/高光四层结构）。
// 用户设备（iPhone 13）可升级 iOS 26，届时自动获得完整效果。

extension View {
    /// Liquid Glass 背景：悬浮层（TabBar / MiniPlayer / 弹窗 / 播放控制区）。
    /// 铁律：毛玻璃上文字用原生 label 色（自带 vibrancy），不用纯灰。
    func liquidGlass(cornerRadius: CGFloat = AppleTheme.cardRadius) -> some View {
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// 小控件玻璃：更轻的质感
    func liquidGlassLight(cornerRadius: CGFloat = AppleTheme.controlRadius) -> some View {
        self.background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - 通用组件

/// 原生风歌曲行：48pt 封面 + 标题/歌手 + 播放状态
/// v4.2：封面带 matchedGeometryEffect，点歌时飞进 FullPlayer（与 FullPlayerView 配对）
struct SongRow: View {
    let song: OnlineSong
    let isPlaying: Bool
    @EnvironmentObject private var theme: ThemeSettings
    @EnvironmentObject private var player: AudioPlayerManager
    @Environment(\.coverFlyNamespace) private var coverNS

    var body: some View {
        HStack(spacing: 12) {
            coverWithFly
            VStack(alignment: .leading, spacing: 3) {
                // Beans 对标：当前播放标题琥珀色高亮 + semibold
                Text(song.title)
                    .font(.body)
                    .fontWeight(isPlaying ? .semibold : .regular)
                    .foregroundColor(isPlaying ? .orange : AppleTheme.label)
                    .lineLimit(1)
                Text("\(song.artist) · \(formatDuration(song.duration))")
                    .font(.subheadline)
                    .foregroundColor(AppleTheme.secondaryLabel)
                    .lineLimit(1)
            }
            Spacer()
            if isPlaying {
                EqualizerBars(isPlaying: true, color: theme.accentColor)
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppleTheme.tertiaryLabel)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        // Beans 对标：当前行微缩放 1.012，spring 过渡
        .scaleEffect(isPlaying ? 1.012 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isPlaying)
    }

    /// 封面飞行：只有被点中的那一行参与（id 配对），避免多行冲突
    @ViewBuilder
    private var coverWithFly: some View {
        let art = coverArt(url: song.coverURL, size: 48)
        if let ns = coverNS, player.coverFlySongID == song.id {
            art.matchedGeometryEffect(id: "coverfly", in: ns, isSource: !player.showFullPlayer)
        } else {
            art
        }
    }
}

/// 平台歌曲行：带平台角标，标记外部来源（不可下载/收藏）
struct PlatformSongRow: View {
    let song: PlatformTrack
    let isPlaying: Bool
    @EnvironmentObject private var theme: ThemeSettings

    var body: some View {
        HStack(spacing: 12) {
            coverArt(url: song.coverURL, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(song.title)
                        .font(.body)
                        .foregroundColor(AppleTheme.label)
                        .lineLimit(1)
                    // 平台角标
                    Text(song.platformDisplayName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.accentColor.opacity(0.15))
                        .foregroundColor(theme.accentColor)
                        .clipShape(Capsule())
                }
                Text("\(song.artist) · \(formatDuration(song.duration))")
                    .font(.subheadline)
                    .foregroundColor(AppleTheme.secondaryLabel)
                    .lineLimit(1)
            }
            Spacer()
            if isPlaying {
                EqualizerBars(isPlaying: true, color: theme.accentColor)
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppleTheme.tertiaryLabel)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}

/// 封面图：有 URL 加载，无 URL 用音符占位
func coverArt(url: URL?, size: CGFloat) -> some View {    Group {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    coverPlaceholder
                }
            }
        } else {
            coverPlaceholder
        }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: AppleTheme.artworkRadius))
}

/// 封面占位
private var coverPlaceholder: some View {
    ZStack {
        RoundedRectangle(cornerRadius: AppleTheme.artworkRadius)
            .fill(Color(.tertiarySystemFill))
        Image(systemName: "music.note")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(AppleTheme.secondaryLabel)
    }
}

/// 大标题行
struct LargeTitleRow: View {
    let title: String
    var body: some View {
        HStack {
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(AppleTheme.label)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

/// 空态
struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(AppleTheme.tertiaryLabel)
            Text(title)
                .font(.headline)
                .foregroundColor(AppleTheme.secondaryLabel)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(AppleTheme.tertiaryLabel)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

/// 加载中
struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("正在加载…")
                .font(.subheadline)
                .foregroundColor(AppleTheme.secondaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

/// 错误浮条（顶部下滑提示，3 秒自动消失由调用方控制）
struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.9))
            .clipShape(Capsule())
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - 工具

/// 秒 → m:ss
func formatDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "--:--" }
    let total = Int(seconds)
    return String(format: "%d:%02d", total / 60, total % 60)
}
