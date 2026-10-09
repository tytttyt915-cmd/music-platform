import Foundation

// MARK: - OnlineModels
//
// 职责：
//   定义"在线曲库"相关的领域模型（与新后端 NestJS 的数据结构对应）。
//   - OnlineSong.id 是 String（UUID v4），不再是网易云时代的 Int
//   - 所有后端字段差异都隔离在 MusicService 的 DTO 映射里，
//     这里只保留干净的业务模型，Views 只依赖这些类型
//   - 纯本地的 Track 模型在 Models/Track.swift，不动

/// 在线歌曲
struct OnlineSong: Identifiable, Hashable {
    /// 后端 UUID v4
    let id: String
    let title: String
    let artist: String
    let album: String
    let coverURL: URL?
    /// 时长（秒）
    let duration: Double
    let playCount: Int

    static func == (lhs: OnlineSong, rhs: OnlineSong) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// 歌单
struct OnlinePlaylist: Identifiable, Hashable {
    /// 后端 UUID v4
    let id: String
    let title: String
    let coverURL: URL?
    let creator: String
    let trackCount: Int
    let description: String

    static func == (lhs: OnlinePlaylist, rhs: OnlinePlaylist) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// 歌单详情：歌单信息 + 歌曲列表
struct PlaylistDetail {
    let playlist: OnlinePlaylist
    let songs: [OnlineSong]
}

/// 歌词行（LRC 解析结果，格式与后端无关，沿用老实现）
struct LyricLine: Identifiable {
    let id = UUID()
    let time: Double
    let text: String
}

/// 分页结果（后端 feed/search 的 { list, total, page, pageSize }）
struct PagedResult<Item> {
    let items: [Item]
    let total: Int
    let page: Int
    let pageSize: Int

    var hasMore: Bool {
        items.count + (page - 1) * pageSize < total
    }
}

/// 音质：后端 stream/play 接口的 quality 参数
/// 后端 StreamQueryDto：standard | high | lossless | hires，默认 high
enum StreamQuality: String, CaseIterable, Identifiable {
    case standard
    case high
    case lossless
    case hires

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "标准"
        case .high: return "高清"
        case .lossless: return "无损"
        case .hires: return "Hi-Res"
        }
    }
}

/// 手动换源：可用源
struct TrackSources: Equatable {
    var preferredSource: String
    var local: [LocalSourceQuality]
    var platforms: [PlatformSource]
}

struct LocalSourceQuality: Equatable, Hashable {
    let quality: String
    let bitrateKbps: Int
}

struct PlatformSource: Equatable, Identifiable, Hashable {
    /// netease | qq | kugou
    let platform: String
    let platformId: String
    let title: String
    let artist: String
    let durationMs: Int?

    var id: String { platform }

    var displayName: String {
        switch platform {
        case "netease": return "网易云"
        case "qq": return "QQ 音乐"
        case "kugou": return "酷狗"
        default: return platform
        }
    }
}

/// 平台歌曲（网易云/QQ/酷狗经后端聚合）：不可下载/收藏，仅在线播
struct PlatformTrack: Identifiable, Hashable {
    /// netease | qq | kugou
    let platform: String
    let platformId: String
    let title: String
    let artist: String
    let album: String
    let coverURL: URL?
    /// 时长（秒）
    let duration: Double

    var id: String { "\(platform):\(platformId)" }

    static func == (lhs: PlatformTrack, rhs: PlatformTrack) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var platformDisplayName: String {
        switch platform {
        case "netease": return "网易云"
        case "qq": return "QQ音乐"
        case "kugou": return "酷狗"
        default: return platform
        }
    }
}

/// 搜索结果：本地 + 平台分组
struct SearchResult {
    var local: [OnlineSong]
    var platforms: [PlatformTrack]
    var hasMore: Bool
}
