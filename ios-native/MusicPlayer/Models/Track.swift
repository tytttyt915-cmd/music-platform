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

    init(id: String = UUID().uuidString,
         title: String,
         artist: String = "未知歌手",
         album: String = "未知专辑",
         duration: Double = 0,
         fileURL: URL? = nil,
         artworkURL: URL? = nil,
         onlineSongId: String? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.fileURL = fileURL
        self.artworkURL = artworkURL
        self.onlineSongId = onlineSongId
    }
    
    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }
}
