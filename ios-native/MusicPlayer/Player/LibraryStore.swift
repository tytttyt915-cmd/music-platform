import Foundation
import Combine

/// 本地音乐库 - 干净重写版
class LibraryStore: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    
    init() {
        load()
    }
    
    func refresh() {
        scan()
    }
    
    func scan() {
        // 扫描本地音乐文件
        // 实际实现需要访问文件系统
        // 这里先从 UserDefaults 加载已保存的
        load()
    }
    
    func add(_ track: Track) {
        if !tracks.contains(where: { $0.id == track.id }) {
            tracks.append(track)
            save()
        }
    }
    
    func remove(_ track: Track) {
        tracks.removeAll { $0.id == track.id }
        save()
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: "sond.library"),
           let saved = try? JSONDecoder().decode([Track].self, from: data) {
            tracks = saved
        }
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(tracks) {
            UserDefaults.standard.set(data, forKey: "sond.library")
        }
    }
}
