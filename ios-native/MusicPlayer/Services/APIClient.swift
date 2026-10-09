import Foundation

// MARK: - APIClient
//
// 职责：
//   统一的 HTTP 客户端，整个 App 所有网络请求都走这里。
//   - Base URL：http://111.230.155.174（Nginx → NestJS），支持用户在设置里自定义覆盖
//   - 后端全局返回格式：{ code: 0, message: "ok", data: {...} }，code != 0 视为业务错误
//   - 自动注入 Authorization: Bearer <accessToken>（requiresAuth = true 的请求）
//   - 401 时触发一次 token 刷新并重试（由 AuthService 注入 onUnauthorized）
//   - 所有 URL 拼装失败、编解码失败都以 Error 抛出，禁止 force unwrap
//
// 不负责：token 的存储与刷新逻辑（那是 AuthService 的事），
//         业务接口的拼装（那是各 Service 的事）。

// MARK: - 后端地址配置

enum APIConfig {
    /// 默认后端地址（Nginx → NestJS，80 端口）
    static let defaultBase = "http://111.230.155.174"

    /// UserDefaults 里用户自定义地址的 key（设置页沿用老 App 的 key，保持兼容）
    private static let customBaseKey = "custom_api_base_url"

    /// 生效的后端地址：用户自定义优先，否则用默认
    static var platformBase: String {
        let custom = UserDefaults.standard.string(forKey: customBaseKey) ?? ""
        let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultBase : trimmed
    }
}

// MARK: - 错误类型

enum APIError: Error, LocalizedError {
    case badURL(String)
    case network(URLError)
    case http(status: Int, message: String?)
    case unauthorized
    case business(code: Int, message: String)
    case decoding(Error)
    case encoding(Error)
    case noData

    var errorDescription: String? {
        switch self {
        case .badURL(let raw): return "无法构造请求 URL：\(raw)"
        case .network(let e): return "网络错误：\(e.localizedDescription)"
        case .http(let status, let message):
            return "HTTP \(status)" + (message.map { "：\($0)" } ?? "")
        case .unauthorized: return "登录已过期，请重新登录"
        case .business(let code, let message): return "请求失败（\(code)）：\(message)"
        case .decoding(let e): return "数据解析失败：\(e.localizedDescription)"
        case .encoding(let e): return "请求编码失败：\(e.localizedDescription)"
        case .noData: return "服务器返回为空"
        }
    }
}

// MARK: - 后端信封

/// 后端全局返回格式 { code, message, data }
struct APIEnvelope<Payload: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: Payload?
}

/// data 为空对象 {} 的接口用这个占位
struct EmptyPayload: Decodable {}

// MARK: - HTTP 方法

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
}

// MARK: - APIClient

final class APIClient {
    /// 提供当前有效的 accessToken；无登录态时返回 nil
    var tokenProvider: (() -> String?)?
    /// 收到 401 时调用：返回 true 表示刷新成功，客户端会重试一次原请求
    var onUnauthorized: (() async -> Bool)?

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        session: URLSession? = nil,
        tokenProvider: (() -> String?)? = nil,
        onUnauthorized: (() async -> Bool)? = nil
    ) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = session ?? URLSession(configuration: config)
        self.tokenProvider = tokenProvider
        self.onUnauthorized = onUnauthorized
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - 便捷方法

    func get<Payload: Decodable>(
        _ path: String,
        query: [String: String] = [:],
        requiresAuth: Bool = false
    ) async throws -> Payload {
        try await request(
            .get, path, query: query,
            body: Optional<EmptyBody>.none, requiresAuth: requiresAuth
        )
    }

    /// 无 Body 的 POST（如 /auth/guest）
    func post<Payload: Decodable>(
        _ path: String,
        requiresAuth: Bool = false
    ) async throws -> Payload {
        try await request(.post, path, body: Optional<EmptyBody>.none, requiresAuth: requiresAuth)
    }

    /// 带 JSON Body 的 POST
    func post<Payload: Decodable, Body: Encodable>(
        _ path: String,
        body: Body,
        requiresAuth: Bool = false
    ) async throws -> Payload {
        try await request(.post, path, body: body, requiresAuth: requiresAuth)
    }

    func delete<Payload: Decodable>(
        _ path: String,
        requiresAuth: Bool = false
    ) async throws -> Payload {
        try await request(
            .delete, path,
            body: Optional<EmptyBody>.none, requiresAuth: requiresAuth
        )
    }

    // MARK: - 核心请求

    private func request<Payload: Decodable, Body: Encodable>(
        _ method: HTTPMethod,
        _ path: String,
        query: [String: String] = [:],
        body: Body? = nil,
        requiresAuth: Bool,
        retried: Bool = false
    ) async throws -> Payload {
        let urlRequest = try buildRequest(
            method, path, query: query, body: body, requiresAuth: requiresAuth
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError {
            throw APIError.network(urlError)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        // 401：尝试刷新 token 后重试一次
        if httpResponse.statusCode == 401, requiresAuth, !retried {
            if let onUnauthorized = onUnauthorized, await onUnauthorized() {
                return try await request(
                    method, path, query: query, body: body,
                    requiresAuth: requiresAuth, retried: true
                )
            }
            throw APIError.unauthorized
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.http(
                status: httpResponse.statusCode,
                message: serverMessage(from: data)
            )
        }

        let envelope: APIEnvelope<Payload>
        do {
            envelope = try decoder.decode(APIEnvelope<Payload>.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }

        guard envelope.code == 0 else {
            throw APIError.business(code: envelope.code, message: envelope.message)
        }
        guard let payload = envelope.data else {
            throw APIError.noData
        }
        return payload
    }

    // MARK: - 请求构造

    private func buildRequest<Body: Encodable>(
        _ method: HTTPMethod,
        _ path: String,
        query: [String: String],
        body: Body?,
        requiresAuth: Bool
    ) throws -> URLRequest {
        guard var components = URLComponents(string: APIConfig.platformBase + path) else {
            throw APIError.badURL(APIConfig.platformBase + path)
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw APIError.badURL(components.string ?? path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if requiresAuth, let token = tokenProvider?() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try encoder.encode(AnyEncodable(body))
            } catch {
                throw APIError.encoding(error)
            }
        }
        return request
    }

    /// 尝试从错误响应体里提取后端 message，提不出来就返回 nil
    private func serverMessage(from data: Data) -> String? {
        struct MessageOnly: Decodable { let message: String? }
        return (try? decoder.decode(MessageOnly.self, from: data))?.message
    }
}

// MARK: - 内部小工具

/// 空 Body 占位：让 post() 在无 body 时也能走同一条泛型路径
private struct EmptyBody: Encodable {}

/// 类型擦除的 Encodable 包装（避免泛型 Body 在 buildRequest 里被具体化）
private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) {
        self.encode = { try value.encode(to: $0) }
    }
    func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}
