import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var theme: ThemeSettings
    var body: some View {
        NavigationView {
            Form {
                Section("主题") {
                    Picker("强调色", selection: $theme.accent) {
                        ForEach(ThemeSettings.AccentChoice.allCases, id: \.self) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                }
                Section("显示") {
                    Toggle("灵动岛", isOn: $theme.showDynamicIsland)
                    Toggle("隐藏Tab栏", isOn: $theme.tabBarHidden)
                }
            }
            .navigationTitle("设置")
        }
    }
}
