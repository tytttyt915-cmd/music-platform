import SwiftUI

// MARK: - LoginView（2026-10-09 Apple 原生风重做）
//
// 职责：登录页（短信验证码 + 游客试听）。
//   - 原生 Form 分组：手机号登录区 / 游客试听区
//   - 已登录：显示身份 + 退出登录 / 注销账号（Apple 审核要求保留注销闭环）
//   - 错误用红色文字行内提示

struct LoginView: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var phone = ""
    @State private var code = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var codeSent = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if auth.isLoggedIn {
                    loggedInView
                } else {
                    loginForm
                }
            }
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    // MARK: - 未登录：短信 + 游客

    private var loginForm: some View {
        Form {
            Section {
                TextField("11 位手机号", text: $phone)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                HStack {
                    TextField("6 位验证码", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                    Button(codeSent ? "重发" : "发送验证码") { sendCode() }
                        .disabled(isBusy || phone.count != 11)
                }
            } header: {
                Text("手机号登录")
            }

            Section {
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
        .disabled(isBusy)
    }

    // MARK: - 已登录：退出 / 注销

    private var loggedInView: some View {
        Form {
            Section {
                LabeledContent("当前身份", value: auth.isGuest ? "游客" : "已登录用户")
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
