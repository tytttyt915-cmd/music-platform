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

// MARK: - 未来飙升榜（TimesFM 智能预测）

/// 飙升榜单首：歌曲 + 预测信息
struct TrendingSong: Identifiable, Hashable {
    let song: OnlineSong
    /// 未来 7 天预测播放量；降级时为 nil
    let predicted7d: Int?
    /// 趋势：(预测7天 - 最近7天实际)/最近7天实际；nil = 未知
    let trendPct: Double?
    /// 是否走了 TimesFM 真预测
    let isPredicted: Bool

    var id: String { song.id }

    /// 上升幅度文案，如 "↑35%"；不上升返回 nil
    var risingText: String? {
        guard let p = trendPct, p > 0.1 else { return nil }
        return "↑\(Int((p * 100).rounded()))%"
    }

    static func == (lhs: TrendingSong, rhs: TrendingSong) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// 飙升榜结果
struct TrendingFutureResult {
    let items: [TrendingSong]
    let total: Int
    let page: Int
    let pageSize: Int
    /// true = 后端降级为按播放量排序（TimesFM 不可用）
    let fallback: Bool

    var hasMore: Bool {
        items.count + (page - 1) * pageSize < total
    }
}

// MARK: - 歌单导入（一键搬家）

/// 歌单导入搬家报告
struct PlaylistImportReport {
    let playlistId: String
    let playlistName: String
    let total: Int
    let matched: Int
    let unmatched: [ImportUnmatchedSong]

    var matchedRate: Double {
        total > 0 ? Double(matched) / Double(total) : 0
    }
}

struct ImportUnmatchedSong: Identifiable, Hashable {
    let title: String
    let artist: String
    var id: String { "\(title)-\(artist)" }
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
    /// netease | qq | kugou | kg | kw | mg | tx | wy
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
        case "kugou", "kg": return "酷狗"
        case "kw": return "酷我"
        case "mg": return "咪咕"
        case "tx": return "腾讯"
        case "wy": return "网易"
        default: return platform
        }
    }
}

/// 平台歌曲（网易云/QQ/酷狗/付费音源经后端聚合）：不可下载/收藏，仅在线播
struct PlatformTrack: Identifiable, Hashable {
    /// 付费音源平台：kg=酷狗 kw=酷我 mg=咪咕 tx=腾讯 wy=网易（需后端配置 PAID_SOURCE_API_KEY）
    static let paidPlatforms: Set<String> = ["kg", "kw", "mg", "tx", "wy"]

    /// netease | qq | kugou | kg | kw | mg | tx | wy
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

    var isPaidPlatform: Bool { Self.paidPlatforms.contains(platform) }

    static func displayName(for platform: String) -> String {
        switch platform {
        case "netease": return "网易云"
        case "qq": return "QQ音乐"
        case "kugou", "kg": return "酷狗"
        case "kw": return "酷我"
        case "mg": return "咪咕"
        case "tx": return "腾讯"
        case "wy": return "网易"
        default: return platform
        }
    }

    var platformDisplayName: String { Self.displayName(for: platform) }
}

/// 搜索结果：本地 + 平台分组
struct SearchResult {
    var local: [OnlineSong]
    var platforms: [PlatformTrack]
    var hasMore: Bool
    /// 后端启用的平台（platformEnabled）：含付费平台，仅后端配置 Key 时出现
    var enabledPlatforms: [String] = []

    /// 已启用的付费平台（用于"换源"菜单）
    var enabledPaidPlatforms: [String] {
        enabledPlatforms.filter { PlatformTrack.paidPlatforms.contains($0) }
    }
}
