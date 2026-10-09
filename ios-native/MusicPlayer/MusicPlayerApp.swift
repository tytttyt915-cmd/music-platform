// Views 适配（2026-10-09）：老网易云 API 单例已删除，改为注入 AuthService.shared + MusicService.shared
import SwiftUI

@main
struct MusicPlayerApp: App {
    @StateObject private var player = AudioPlayerManager()
    @StateObject private var library = LibraryStore()
    @StateObject private var favorites = FavoriteStore()
    @StateObject private var theme = ThemeSettings()
    @StateObject private var profile = UserProfile()
    @StateObject private var auth = AuthService.shared
    @StateObject private var music = MusicService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .environmentObject(library)
                .environmentObject(favorites)
                .environmentObject(theme)
                .environmentObject(profile)
                .environmentObject(auth)
                .environmentObject(music)
        }
    }
}
