import Foundation
import Combine

/// 用户资料 - 干净重写版
class UserProfile: ObservableObject {
    @Published var nickname: String = "未登录用户" {
        didSet { save() }
    }
    @Published var avatarData: Data? {
        didSet { save() }
    }
    
    private let key = "sond.profile"
    
    init() {
        load()
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            nickname = saved.nickname
            avatarData = saved.avatarData
        }
    }
    
    private func save() {
        let saved = Saved(nickname: nickname, avatarData: avatarData)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    private struct Saved: Codable {
        let nickname: String
        let avatarData: Data?
    }
}
