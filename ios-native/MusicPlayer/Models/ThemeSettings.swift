import SwiftUI
import Combine

/// 主题设置 - 干净重写版
class ThemeSettings: ObservableObject {
    enum AccentChoice: String, CaseIterable, Codable {
        case red = "红色"
        case orange = "橙色"
        case yellow = "黄色"
        case green = "绿色"
        case blue = "蓝色"
        case purple = "紫色"
        case pink = "粉色"
    }
    
    @Published var accent: AccentChoice = .red {
        didSet { save() }
    }
    @Published var showDynamicIsland: Bool = true {
        didSet { save() }
    }
    @Published var tabBarHidden: Bool = false {
        didSet { save() }
    }
    
    var accentColor: Color {
        // impeccable quieter：饱和度压到 75%，不刺眼
        let base: Color
        switch accent {
        case .red: base = .red
        case .orange: base = .orange
        case .yellow: base = .yellow
        case .green: base = .green
        case .blue: base = .blue
        case .purple: base = .purple
        case .pink: base = .pink
        }
        return base.quieter()
    }
    
    var backgroundColor: Color {
        Color(.systemBackground)
    }
    
    var textColor: Color {
        Color(.label)
    }
    
    var secondaryTextColor: Color {
        Color(.secondaryLabel)
    }
    
    private let key = "sond.theme"
    
    init() {
        load()
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            accent = saved.accent
            showDynamicIsland = saved.showDynamicIsland
            tabBarHidden = saved.tabBarHidden
        }
    }
    
    private func save() {
        let saved = Saved(accent: accent, showDynamicIsland: showDynamicIsland, tabBarHidden: tabBarHidden)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    private struct Saved: Codable {
        let accent: AccentChoice
        let showDynamicIsland: Bool
        let tabBarHidden: Bool
    }
}
