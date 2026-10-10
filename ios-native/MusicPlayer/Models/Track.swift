import Foundation

// Views 适配（2026-10-09）：onlineSongId 由 Int 改为 String（后端 UUID v4）
/// 音乐曲目模型 - 干净重写版
struct Track: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var fileURL: URL?
    var artworkURL: URL?
    var onlineSongId: String?
    /// 平台直链（网易云/QQ/酷狗经后端 302）：有值时直接播，不走 onlineSongId 解析
    var platformStreamURL: URL?
    /// 平台名（netease/qq/kugou），用于展示角标
    var platform: String?
    /// 平台歌曲 ID（网易云等）：私人漫游取相似歌曲用
    var platformId: String?

    init(id: String = UUID().uuidString,
         title: String,
         artist: String = "未知歌手",
         album: String = "未知专辑",
         duration: Double = 0,
         fileURL: URL? = nil,
         artworkURL: URL? = nil,
         onlineSongId: String? = nil,
         platformStreamURL: URL? = nil,
         platform: String? = nil,
         platformId: String? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.fileURL = fileURL
        self.artworkURL = artworkURL
        self.onlineSongId = onlineSongId
        self.platformStreamURL = platformStreamURL
        self.platform = platform
        self.platformId = platformId
    }
    
    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }
}
