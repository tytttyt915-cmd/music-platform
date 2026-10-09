import SwiftUI

// MARK: - ContentView（2026-10-09 Apple 原生风重做）
//
// 职责：App 主容器。
//   - 4 Tab：发现 / 歌单 / 本地 / 我的（每 tab 独立 NavigationStack，保留 iOS 右滑返回）
//   - 底部自定义 TabBar：Liquid Glass 背景（iOS 26 .glassEffect，低版本降级毛玻璃）
//   - MiniPlayer 悬浮在 TabBar 上方：Liquid Glass 胶囊，点击/上滑展开 FullPlayer
//   - FullPlayer 用 fullScreenCover + 下滑手势关闭（1:1 跟手，可打断）

struct ContentView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var theme: ThemeSettings

    @State private var selection = 0
    @State private var showFullPlayer = false

    private let tabs: [(title: String, icon: String, selectedIcon: String)] = [
        ("发现", "safari", "safari.fill"),
        ("歌单", "music.note.list", "music.note.list"),
        ("本地", "folder", "folder.fill"),
        ("我的", "person", "person.fill"),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            // 内容区：每 tab 独立导航栈
            Group {
                switch selection {
                case 0: NavigationStack { DiscoverView() }
                case 1: NavigationStack { PlaylistPlazaView() }
                case 2: NavigationStack { LocalMusicView() }
                default: NavigationStack { ProfileView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 底部：MiniPlayer + 玻璃 TabBar
            VStack(spacing: 8) {
                if player.currentTrack != nil {
                    MiniPlayerBar {
                        showFullPlayer = true
                    }
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                glassTabBar
            }
            .padding(.bottom, 8)
        }
        .background(AppleTheme.background.ignoresSafeArea())
        .animation(.appleDefault, value: player.currentTrack?.id)
        .fullScreenCover(isPresented: $showFullPlayer) {
            FullPlayerView()
        }
    }

    // MARK: - Liquid Glass TabBar

    private var glassTabBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { index in
                let tab = tabs[index]
                let isSelected = selection == index
                Button {
                    selection = index
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                        Text(tab.title)
                            .font(.caption2)
                            .fontWeight(isSelected ? .semibold : .regular)
                    }
                    .foregroundColor(isSelected ? theme.accentColor : AppleTheme.secondaryLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .pressable()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .liquidGlass(cornerRadius: 24)
        .padding(.horizontal, 12)
    }
}
