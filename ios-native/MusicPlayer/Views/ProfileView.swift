import SwiftUI

// Views 适配（2026-10-09）：网易云登录 → LoginView（短信+游客）；显示 AuthService 登录态
struct ProfileView: View {
    @EnvironmentObject var profile: UserProfile
    @EnvironmentObject var theme: ThemeSettings
    @EnvironmentObject var auth: AuthService
    @State private var showSettings = false
    @State private var showLogin = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Circle().fill(theme.accentColor).frame(width: 60, height: 60)
                        VStack(alignment: .leading) {
                            Text(profile.nickname).font(.headline)
                            Text(auth.isLoggedIn ? (auth.isGuest ? "游客" : "已登录") : "未登录")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                Section {
                    Button(auth.isLoggedIn ? "账号管理" : "登录") { showLogin = true }
                    Button("设置") { showSettings = true }
                }
            }
            .navigationTitle("我的")
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showLogin) { LoginView() }
        }
    }
}
