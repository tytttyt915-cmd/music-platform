import SwiftUI

// Views 适配（2026-10-09）：移除老网易云 API 引用；歌手 tab 下线（新后端无歌手接口），剩余 4 tab
/// 主容器：4 Tab + MiniPlayer + FullPlayer
struct ContentView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var favorites: FavoriteStore
    @EnvironmentObject var theme: ThemeSettings
    @EnvironmentObject var profile: UserProfile
    
    @State private var selectedTab = 0
    @State private var showFullPlayer = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                DynamicAuraBackground()
                
                VStack(spacing: 0) {
                    Group {
                        switch selectedTab {
                        case 0: DiscoverView()
                        case 1: PlaylistPlazaView()
                        case 2: LocalMusicView()
                        case 3: ProfileView()
                        default: DiscoverView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, bottomInset(geo: geo))
                }
                
                VStack(spacing: 0) {
                    if player.currentTrack != nil {
                        MiniPlayerBar { showFullPlayer = true }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                    }
                    tabBar(geo: geo)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showFullPlayer) {
            FullPlayerView()
                .environmentObject(player)
                .environmentObject(theme)
        }
    }
    
    private func bottomInset(geo: GeometryProxy) -> CGFloat {
        let mini: CGFloat = player.currentTrack != nil ? 68 : 0
        return 84 + mini + geo.safeAreaInsets.bottom
    }
    
    private func tabBar(geo: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { i in
                Button { selectedTab = i } label: {
                    VStack(spacing: 3) {
                        Image(systemName: icon(i)).font(.system(size: 20))
                        Text(title(i)).font(.system(size: 10))
                    }
                    .foregroundColor(selectedTab == i ? theme.accentColor : .gray)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, geo.safeAreaInsets.bottom + 10)
        .background(glassBackground())
    }
    
    private func glassBackground() -> AnyView {
        if #available(iOS 26, *) {
            // iOS 26 液态玻璃：半透明背景 + 玻璃效果
            return AnyView(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            )
        } else {
            return AnyView(theme.backgroundColor.opacity(0.95))
        }
    }
    
    private func icon(_ i: Int) -> String {
        ["safari", "music.note.list", "folder.fill", "person.fill"][i]
    }
    private func title(_ i: Int) -> String {
        ["发现", "歌单", "本地", "我的"][i]
    }
}
