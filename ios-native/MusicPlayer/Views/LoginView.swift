// Views 适配（2026-10-09）：重写。老二维码登录已删除；改为短信验证码登录 +
// 游客试听（调 AuthService），并保留注销账号闭环（Apple 审核要求）。
import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthService
    @EnvironmentObject var theme: ThemeSettings
    @Environment(\.dismiss) var dismiss

    @State private var phone = ""
    @State private var code = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var codeSent = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationView {
            Group {
                if auth.isLoggedIn {
                    loggedInView
                } else {
                    loginForm
                }
            }
            .navigationTitle("登录")
            .toolbar {
                Button("关闭") { dismiss() }
            }
        }
    }

    // MARK: - 未登录：短信 + 游客

    private var loginForm: some View {
        Form {
            Section("手机号登录") {
                TextField("11 位手机号", text: $phone)
                    .keyboardType(.numberPad)
                HStack {
                    TextField("6 位验证码", text: $code)
                        .keyboardType(.numberPad)
                    Button(codeSent ? "重发" : "发送验证码") { sendCode() }
                        .disabled(isBusy || phone.count != 11)
                }
                Button("登录") { verify() }
                    .disabled(isBusy || phone.count != 11 || code.count != 6)
            }
            Section {
                Button("游客试听") { guest() }
                    .disabled(isBusy)
            } footer: {
                Text("游客模式可直接试听，无需手机号")
            }
            if let error = errorMessage {
                Section {
                    Text(error).foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - 已登录：退出 / 注销

    private var loggedInView: some View {
        Form {
            Section {
                Text(auth.isGuest ? "当前为游客身份" : "已登录")
                    .foregroundColor(theme.textColor)
            }
            Section {
                Button("退出登录", role: .destructive) {
                    Task { await auth.logout() }
                }
                Button("注销账号", role: .destructive) {
                    showDeleteConfirm = true
                }
            } footer: {
                Text("注销账号将永久删除账号及相关数据，不可恢复")
            }
            if let error = errorMessage {
                Section {
                    Text(error).foregroundColor(.red)
                }
            }
        }
        .alert("确认注销？", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认注销", role: .destructive) { deleteAccount() }
        } message: {
            Text("账号、歌单、播放记录将被永久删除")
        }
    }

    // MARK: - 动作

    private func sendCode() {
        isBusy = true
        errorMessage = nil
        Task {
            do {
                try await auth.sendSMSCode(phone: phone)
                await MainActor.run {
                    codeSent = true
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "发送失败：\(error.localizedDescription)"
                    isBusy = false
                }
            }
        }
    }

    private func verify() {
        isBusy = true
        errorMessage = nil
        Task {
            do {
                try await auth.verifySMSCode(phone: phone, code: code)
                await MainActor.run {
                    isBusy = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "登录失败：\(error.localizedDescription)"
                    isBusy = false
                }
            }
        }
    }

    private func guest() {
        isBusy = true
        errorMessage = nil
        Task {
            do {
                try await auth.guestLogin()
                await MainActor.run {
                    isBusy = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "游客登录失败：\(error.localizedDescription)"
                    isBusy = false
                }
            }
        }
    }

    private func deleteAccount() {
        Task {
            do {
                try await auth.deleteAccount()
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = "注销失败：\(error.localizedDescription)"
                }
            }
        }
    }
}
