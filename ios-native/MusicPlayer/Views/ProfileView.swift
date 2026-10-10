import SwiftUI

// MARK: - ProfileView（2026-10-09 Apple 原生风重做）
//
// 职责：我的页。
//   - 顶部：圆形头像（首字）+ 昵称 + 登录态
//   - 原生分组列表：账号管理、设置
//   - 登录页用 sheet 弹出 LoginView

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var theme: ThemeSettings

    @State private var showLogin = false
    @State private var showSettings = false

    private var statusText: String {
        if !auth.isLoggedIn { return "未登录" }
        return auth.isGuest ? "游客试听中" : "已登录"
    }

    private var displayName: String {
        if !auth.isLoggedIn { return "未登录用户" }
        return auth.isGuest ? "游客" : "音乐用户"
    }

    var body: some View {
        ZStack {
            AppleTheme.background.ignoresSafeArea()
            List {
                // 头部
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(theme.accentColor.opacity(0.15))
                                .frame(width: 64, height: 64)
                            Text(String(displayName.prefix(1)))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(theme.accentColor)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(AppleTheme.label)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(auth.isLoggedIn ? Color.green : AppleTheme.tertiaryLabel)
                                    .frame(width: 8, height: 8)
                                Text(statusText)
                                    .font(.body)
                                    .foregroundColor(AppleTheme.secondaryLabel)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                // 菜单
                Section {
                    Button {
                        showLogin = true
                    } label: {
                        menuRow(
                            icon: "person.crop.circle",
                            title: auth.isLoggedIn ? "账号管理" : "登录",
                            subtitle: auth.isLoggedIn ? "退出登录 / 注销账号" : "手机号 / 游客试听"
                        )
                    }
                    .pressable()

                    Button {
                        showSettings = true
                    } label: {
                        menuRow(
                            icon: "gearshape",
                            title: "设置",
                            subtitle: "播放 / 外观 / 关于"
                        )
                    }
                    .pressable()
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("我的")
        .sheet(isPresented: $showLogin) { LoginView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private func menuRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            // impeccable: 去掉 icon-tile，SF Symbol 直接着主题色
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.accentColor)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(AppleTheme.label)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppleTheme.secondaryLabel)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppleTheme.tertiaryLabel)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
