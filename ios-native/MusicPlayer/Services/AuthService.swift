import Combine
import Foundation
import Security

// MARK: - AuthService
//
// 职责：
//   新后端的 JWT 认证流程，替代老 App 的网易云扫码登录模块
//   （二维码扫码 + cookie 彻底删除）。
//   - 登录方式：游客（POST /auth/guest）、短信（/auth/sms/send + /verify）、微信（/auth/wechat/login）
//   - token 存储在 Keychain（accessToken + refreshToken），不在 UserDefaults 留明文
//   - accessToken 过期前由 APIClient 在 401 时自动触发 refreshTokens() 并重试一次
//   - @Published 的 isLoggedIn / isGuest 供 UI 层订阅
//
// 线程模型：
//   AuthService 是 @MainActor（UI 状态必须在主线程更新）；
//   APIClient 在后台线程通过 tokenProvider 读 token，所以 token 本体放在
//   线程安全的 TokenBox 里，避免跨 actor 数据竞争。

// MARK: - Token 模型

/// 后端登录/刷新的返回：{ accessToken, refreshToken, tokenType, expiresIn }
/// 注意：后端不返回 isGuest，由调用方根据登录方式决定
struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    /// 如 "3600s"
    let expiresIn: String

    /// expiresIn 解析成秒数，解析失败默认 3600
    var expiresInSeconds: TimeInterval {
        let digits = expiresIn.filter(\.isNumber)
        return TimeInterval(digits).map { $0 > 0 ? $0 : 3600 } ?? 3600
    }
}

/// Keychain 存储用：token + 是否游客
private struct StoredTokens: Codable {
    let tokens: AuthTokens
    let isGuest: Bool
}

// MARK: - 线程安全的 token 盒子

final class TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: AuthTokens?
    private var expiry: Date?

    func read() -> (tokens: AuthTokens?, expiry: Date?) {
        lock.withLock { (tokens, expiry) }
    }

    func write(tokens: AuthTokens?, expiry: Date?) {
        lock.withLock {
            self.tokens = tokens
            self.expiry = expiry
        }
    }
}

// MARK: - Keychain 存储

enum TokenStore {
    private static let service = "com.musicplatform.auth"
    private static let account = "tokens"

    static func save(_ tokens: AuthTokens, isGuest: Bool) throws {
        let stored = StoredTokens(tokens: tokens, isGuest: isGuest)
        let data = try JSONEncoder().encode(stored)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // 先删后增，避免重复条目
        SecItemDelete(query as CFDictionary)
        let attributes = query.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]) { _, new in new }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw APIError.business(code: Int(status), message: "Keychain 保存失败")
        }
    }

    static func load() -> StoredTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(AuthTokens.self, from: data)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - AuthService

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    /// 供全 App 使用的、带认证的 APIClient（401 自动刷新重试）
    let api: APIClient

    @Published private(set) var isLoggedIn: Bool = false
    @Published private(set) var isGuest: Bool = false

    private let box = TokenBox()

    private init() {
        // 先建 client，再补闭包，避免 init 内 self 捕获问题
        let client = APIClient()
        self.api = client
        client.tokenProvider = { [box] in box.read().tokens?.accessToken }
        client.onUnauthorized = { [weak self] in
            guard let self = self else { return false }
            return await self.refreshTokens()
        }

        // 恢复上次登录态
        if let stored = TokenStore.load() {
            let expiry = Date().addingTimeInterval(stored.tokens.expiresInSeconds)
            box.write(tokens: stored.tokens, expiry: expiry)
            self.isLoggedIn = true
            self.isGuest = stored.isGuest
        }
    }

    // MARK: - 对外：登录方式

    /// 游客登录（纯净试听模式，Apple 审核要求保留）
    func guestLogin() async throws {
        let tokens: AuthTokens = try await api.post("/auth/guest")
        try persist(tokens, isGuest: true)
    }

    /// 发送短信验证码
    func sendSMSCode(phone: String) async throws {
        try validatePhone(phone)
        struct Body: Encodable { let phone: String }
        let _: EmptyPayload = try await api.post("/auth/sms/send", body: Body(phone: phone))
    }

    /// 校验短信验证码并登录
    func verifySMSCode(phone: String, code: String) async throws {
        try validatePhone(phone)
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            throw APIError.business(code: -1, message: "验证码为 6 位数字")
        }
        struct Body: Encodable { let phone: String; let code: String }
        let tokens: AuthTokens = try await api.post("/auth/sms/verify", body: Body(phone: phone, code: code))
        try persist(tokens, isGuest: false)
    }

    /// 微信登录（小程序 code 换 token；iOS 端 code 获取逻辑在 Views 阶段接入）
    func wechatLogin(code: String) async throws {
        guard !code.isEmpty else {
            throw APIError.business(code: -1, message: "微信授权码为空")
        }
        struct Body: Encodable { let code: String }
        let tokens: AuthTokens = try await api.post("/auth/wechat/login", body: Body(code: code))
        try persist(tokens, isGuest: false)
    }

    /// 登出：先调服务端吊销 refreshToken（失败也不阻塞本地清理）
    func logout() async {
        if let refreshToken = box.read().tokens?.refreshToken {
            struct Body: Encodable { let refreshToken: String }
            let _: EmptyPayload? = try? await api.post(
                "/auth/logout", body: Body(refreshToken: refreshToken), requiresAuth: true
            )
        }
        clearLocal()
    }

    /// 注销账号（Apple 审核要求）：DELETE /account，成功后清本地
    func deleteAccount() async throws {
        let _: EmptyPayload = try await api.delete("/account", requiresAuth: true)
        clearLocal()
    }

    // MARK: - 对内：刷新

    /// 刷新 token；成功返回 true。401 重试、启动恢复都走这里。
    /// 注意：refresh 本身失败（如 refreshToken 也过期）→ 清本地，要求重新登录
    func refreshTokens() async -> Bool {
        guard let refreshToken = box.read().tokens?.refreshToken else { return false }
        struct Body: Encodable { let refreshToken: String }
        do {
            let tokens: AuthTokens = try await api.post("/auth/refresh", body: Body(refreshToken: refreshToken))
            try persist(tokens, isGuest: self.isGuest)
            return true
        } catch {
            clearLocal()
            return false
        }
    }

    // MARK: - 私有

    private func persist(_ tokens: AuthTokens, isGuest: Bool) throws {
        try TokenStore.save(tokens, isGuest: isGuest)
        let expiry = Date().addingTimeInterval(tokens.expiresInSeconds)
        box.write(tokens: tokens, expiry: expiry)
        isLoggedIn = true
        self.isGuest = isGuest
    }

    private func clearLocal() {
        TokenStore.delete()
        box.write(tokens: nil, expiry: nil)
        isLoggedIn = false
        isGuest = false
    }

    private func validatePhone(_ phone: String) throws {
        let isMobile = phone.count == 11
            && phone.hasPrefix("1")
            && phone.allSatisfy(\.isNumber)
        guard isMobile else {
            throw APIError.business(code: -1, message: "请输入正确的 11 位手机号")
        }
    }
}
