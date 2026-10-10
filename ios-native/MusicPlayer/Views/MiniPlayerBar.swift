import SwiftUI

// MARK: - MiniPlayerBar（2026-10-09 Apple 原生风重做）
//
// 职责：悬浮 Liquid Glass 迷你播放条。
//   - 玻璃胶囊：封面 + 歌名/歌手 + 播放暂停按钮
//   - 底部细进度条
//   - 点击整条 → 展开 FullPlayer；上滑手势也可展开（1:1 跟手）
//   - 播放按钮独立响应，不触发展开

struct MiniPlayerBar: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var theme: ThemeSettings
    @EnvironmentObject private var music: MusicService
    var onTap: () -> Void

    @GestureState private var dragOffset: CGFloat = 0
    @StateObject private var lyricProvider = MiniLyricProvider()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                coverArt(url: player.currentTrack?.artworkURL, size: 40)

                if let track = player.currentTrack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppleTheme.label)
                            .lineLimit(1)
                        // Beans 对标：MiniPlayer 显示实时歌词行，无歌词时回退歌手名
                        Text(lyricProvider.currentLine ?? track.artist)
                            .font(.caption)
                            .foregroundColor(AppleTheme.secondaryLabel)
                            .lineLimit(1)
                            .animation(.easeInOut(duration: 0.25), value: lyricProvider.currentLine)
                    }
                }
                Spacer()
                if player.isPlaying {
                    EqualizerBars(isPlaying: true, color: theme.accentColor)
                        .padding(.trailing, 2)
                }
                Button {
                    player.togglePlayPause()
                } label: {
                    MorphPlayIcon(isPlaying: player.isPlaying, size: 16)
                        .foregroundColor(AppleTheme.label)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .pressable()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // 细进度条
            if player.duration > 0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(theme.accentColor)
                        .frame(
                            width: geo.size.width * CGFloat(min(max(player.currentTime / player.duration, 0), 1)),
                            height: 2
                        )
                }
                .frame(height: 2)
                .clipShape(Capsule())
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .liquidGlass(cornerRadius: 16)
        .offset(y: dragOffset)
        .onTapGesture {
            onTap()
        }
        .gesture(
            DragGesture(minimumDistance: 10)
                .updating($dragOffset) { value, state, _ in
                    // 只响应上滑（负值），1:1 跟手
                    state = min(value.translation.height, 0)
                }
                .onEnded { value in
                    if value.translation.height < -40 {
                        // 上滑展开
                        onTap()
                    }
                }
        )
        .animation(.gsapPower2Out, value: dragOffset == 0)
        .onAppear {
            lyricProvider.bind(player: player, music: music)
        }
    }
}
