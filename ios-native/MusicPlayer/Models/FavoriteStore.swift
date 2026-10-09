import Foundation
import Combine

/// 收藏存储 - 干净重写版
class FavoriteStore: ObservableObject {
    @Published private(set) var favoriteIds: Set<String> = []
    
    private let key = "sond.favorites"
    
    init() {
        load()
    }
    
    func isFavorite(_ track: Track) -> Bool {
        favoriteIds.contains(track.id)
    }
    
    func toggle(_ track: Track) {
        if favoriteIds.contains(track.id) {
            favoriteIds.remove(track.id)
        } else {
            favoriteIds.insert(track.id)
        }
        save()
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let ids = try? JSONDecoder().decode(Set<String>.self, from: data) {
            favoriteIds = ids
        }
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(favoriteIds) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
