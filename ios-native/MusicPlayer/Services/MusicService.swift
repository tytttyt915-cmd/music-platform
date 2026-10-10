import Combine
import Foundation

// MARK: - MusicService
//
// 职责：
//   在线曲库的业务接口层，替代老 App 的网易云网关（含多音源聚合；
//   评论/排行/歌手等 12 个无数据源接口已全部删除）。
//   对接新后端 NestJS：http://111.230.155.174
//   - 搜索 /music/search、推荐 /music/feed、详情 /music/track/:id
//   - 歌词 /music/track/:id/lyrics（LRC 文本，复用老 parseLRC）
//   - 播放 /music/track/:id/stream → 302 到 COS 预签名 URL。
//     注意：预签名 URL 有过期时间，禁止缓存，每次播放前重新取。
//     该接口是公开的（@Public），AVPlayer 可直接拿 URL 播放，原生跟随 302。
//   - 播放统计 POST /music/track/:id/play（需登录，每次播放必须上报，防刷）
//   - 歌单：创建 /playlists、详情 /playlists/:id、加歌 /playlists/:id/tracks
//
// id 类型：全站 String（UUID v4），后端用 ParseUUIDPipe 强校验。
// 后端字段 quirks（如 playCount 是字符串）隔离在下方私有 DTO 里，
// 对外只暴露 Models/OnlineModels.swift 的干净模型。

@MainActor
final class MusicService: ObservableObject {
    static let shared = MusicService()

    private let api: APIClient

    init(api: APIClient? = nil) {
        // 默认走 AuthService 的带认证 client（401 自动刷新）
        self.api = api ?? AuthService.shared.api
    }

    // MARK: - 搜索与推荐

    /// 搜索歌曲
    func search(keyword: String, page: Int = 1, pageSize: Int = 30) async throws -> PagedResult<OnlineSong> {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.business(code: -1, message: "搜索关键词不能为空")
        }
        let dto: TrackPageDTO = try await api.get(
            "/music/search",
            query: ["q": trimmed, "page": "\(page)", "pageSize": "\(pageSize)"]
        )
        return dto.toPagedResult()
    }

    /// 搜索歌曲（本地 + 平台分组）。后端把三类结果合并在一个 list 里，
    /// 靠 platform / source 字段区分：有 platform=平台歌，有 source=itunes试听，
    /// 都没有=本地曲库。
    func searchWithPlatforms(keyword: String, page: Int = 1, pageSize: Int = 30) async throws -> SearchResult {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.business(code: -1, message: "搜索关键词不能为空")
        }
        let dto: SearchPageDTO = try await api.get(
            "/music/search",
            query: ["q": trimmed, "page": "\(page)", "pageSize": "\(pageSize)"]
        )
        return dto.toSearchResult()
    }

    /// 平台歌曲播放地址：后端 302 到真实直链，AVPlayer 原生跟随
    func platformStreamURL(platform: String, platformId: String, quality: StreamQuality = .high) throws -> URL {
        var components = URLComponents(
            string: APIConfig.platformBase + "/music/platform/\(platform)/stream"
        )
        components?.queryItems = [
            URLQueryItem(name: "id", value: platformId),
            URLQueryItem(name: "quality", value: quality.rawValue),
        ]
        guard let url = components?.url else {
            throw APIError.badURL("/music/platform/\(platform)/stream")
        }
        return url
    }

    /// 发现页推荐（自有曲库歌曲列表）
    func feed(page: Int = 1, pageSize: Int = 20) async throws -> PagedResult<OnlineSong> {
        let dto: TrackPageDTO = try await api.get(
            "/music/feed",
            query: ["page": "\(page)", "pageSize": "\(pageSize)"]
        )
        return dto.toPagedResult()
    }

    // MARK: - 未来飙升榜（TimesFM 智能预测）

    /// 未来飙升榜：后端用 TimesFM 预测 7 天后热度，按 0.7 分位数排序。
    /// TimesFM 不可用时后端降级为按播放量排序（fallback=true），App 照常展示。
    func trendingFuture(page: Int = 1, pageSize: Int = 20) async throws -> TrendingFutureResult {
        let dto: TrendingFutureDTO = try await api.get(
            "/music/trending-future",
            query: ["page": "\(page)", "pageSize": "\(pageSize)"]
        )
        return dto.toResult()
    }

    // MARK: - 歌单导入（一键搬家）

    /// 歌单导入：粘贴网易云/ QQ 音乐歌单链接，后端爬取 + 本地匹配 + 建单。
    /// 返回搬家报告（命中/未命中列表）。需要登录（游客 token 亦可）。
    func importPlaylist(url: String) async throws -> PlaylistImportReport {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.business(code: -1, message: "请粘贴歌单链接")
        }
        struct Body: Encodable { let url: String }
        let dto: PlaylistImportDTO = try await api.post(
            "/playlists/import",
            body: Body(url: trimmed),
            requiresAuth: true
        )
        return dto.toReport()
    }

    // MARK: - 歌曲详情与歌词

    /// 歌曲详情
    func trackDetail(id: String) async throws -> OnlineSong {
        try validateUUID(id)
        let dto: TrackDTO = try await api.get("/music/track/\(id)")
        return dto.toModel()
    }

    /// 歌词（LRC）。无歌词时返回空数组，不抛错
    func lyrics(id: String) async throws -> [LyricLine] {
        try validateUUID(id)
        let dto: LyricsDTO = try await api.get("/music/track/\(id)/lyrics")
        guard let lrc = dto.lrcText, !lrc.isEmpty else { return [] }
        return Self.parseLRC(lrc)
    }

    // MARK: - 播放

    /// 播放地址：直接返回 /stream 的 URL，AVPlayer 原生跟随 302。
    /// 禁止缓存返回值（预签名 URL 会过期），每次播放前重新调用。
    func streamURL(id: String, quality: StreamQuality = .high) throws -> URL {
        try validateUUID(id)
        var components = URLComponents(
            string: APIConfig.platformBase + "/music/track/\(id)/stream"
        )
        components?.queryItems = [URLQueryItem(name: "quality", value: quality.rawValue)]
        guard let url = components?.url else {
            throw APIError.badURL("/music/track/\(id)/stream")
        }
        return url
    }

    /// 播放统计上报：每次实际开始播放后调用一次（后端做自然日去重防刷）
    func reportPlay(id: String, quality: StreamQuality = .high) async throws {
        try validateUUID(id)
        struct Body: Encodable { let quality: String }
        let _: EmptyPayload = try await api.post(
            "/music/track/\(id)/play",
            body: Body(quality: quality.rawValue),
            requiresAuth: true
        )
    }

    // MARK: - 手动换源

    /// 可用源列表（本地码率 + 各平台最佳匹配）
    func availableSources(id: String) async throws -> TrackSources {
        try validateUUID(id)
        let dto: TrackSourcesDTO = try await api.get("/music/track/\(id)/sources")
        return dto.toModel()
    }

    /// 锁定首选源：auto | local | netease | qq | kugou
    func setPreferredSource(id: String, source: String) async throws {
        try validateUUID(id)
        struct Body: Encodable { let source: String }
        let _: EmptyPayload = try await api.put(
            "/music/track/\(id)/preferred-source",
            body: Body(source: source)
        )
    }

    /// 波形 100 点 0~1（服务端预计算）
    func waveform(id: String) async throws -> [Float] {
        try validateUUID(id)
        let peaks: [Double] = try await api.get("/music/track/\(id)/waveform")
        return peaks.map { Float($0) }
    }

    // MARK: - 电台

    /// 电台列表（Radio Browser）。tag 为空返回热门。
    func radioStations(tag: String? = nil, limit: Int = 30) async throws -> [RadioStationItem] {
        var query: [String: String] = ["limit": String(limit)]
        if let tag = tag, !tag.isEmpty {
            query["tag"] = tag
        }
        let dto: [RadioStationDTO] = try await api.get("/music/radio", query: query)
        return dto.map { $0.toModel() }
    }

    // MARK: - 歌单

    /// 创建歌单
    func createPlaylist(
        title: String,
        coverURL: String? = nil,
        isPublic: Bool = false
    ) async throws -> OnlinePlaylist {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.business(code: -1, message: "歌单标题不能为空")
        }
        struct Body: Encodable {
            let title: String
            let coverUrl: String?
            let isPublic: Bool
        }
        let dto: PlaylistDTO = try await api.post(
            "/playlists",
            body: Body(title: trimmed, coverUrl: coverURL, isPublic: isPublic),
            requiresAuth: true
        )
        return dto.toModel(trackCount: 0)
    }

    /// 歌单详情（含歌曲列表）
    func playlistDetail(id: String) async throws -> PlaylistDetail {
        try validateUUID(id)
        let dto: PlaylistDetailDTO = try await api.get("/playlists/\(id)", requiresAuth: true)
        return dto.toModel()
    }

    /// 歌单加歌
    func addTrack(playlistID: String, trackID: String) async throws {
        try validateUUID(playlistID)
        try validateUUID(trackID)
        struct Body: Encodable { let trackId: String }
        let _: EmptyPayload = try await api.post(
            "/playlists/\(playlistID)/tracks",
            body: Body(trackId: trackID),
            requiresAuth: true
        )
    }

    // MARK: - LRC 解析（沿用老实现，格式通用）

    static func parseLRC(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        // [mm:ss.xx] 文本，支持一行多个时间标签
        let pattern = #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for rawLine in lrc.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let range = NSRange(line.startIndex..., in: line)
            let matches = regex.matches(in: line, range: range)
            guard !matches.isEmpty else { continue }

            // 去掉所有时间标签，剩下的是歌词文本
            let text = regex.stringByReplacingMatches(
                in: line, range: range, withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            for match in matches {
                func group(_ i: Int) -> String? {
                    let r = match.range(at: i)
                    guard r.location != NSNotFound,
                          let swiftRange = Range(r, in: line) else { return nil }
                    return String(line[swiftRange])
                }
                guard let minStr = group(1), let secStr = group(2),
                      let minutes = Double(minStr), let seconds = Double(secStr) else { continue }
                var time = minutes * 60 + seconds
                if let fracStr = group(3), let frac = Double(fracStr) {
                    // 2 位是百分秒，3 位是毫秒
                    time += fracStr.count == 3 ? frac / 1000 : frac / 100
                }
                lines.append(LyricLine(time: time, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    // MARK: - 私有

    /// 后端对 :id 用 ParseUUIDPipe(version 4) 强校验，前端先拦一道，报错更友好
    private func validateUUID(_ id: String) throws {
        guard UUID(uuidString: id) != nil else {
            throw APIError.business(code: -1, message: "非法的歌曲 ID：\(id)")
        }
    }
}

// MARK: - 后端 DTO（私有，字段 quirks 隔离在这里）

/// 后端 Track：注意 playCount 在 DB 是 bigint，序列化为字符串
private struct TrackDTO: Decodable {
    let id: String
    let title: String
    let artist: String?
    let coverUrl: String?
    let durationMs: Int?
    let playCount: String?
    let status: String?

    func toModel() -> OnlineSong {
        let playCountInt = playCount.flatMap(Int.init) ?? 0
        let artistName: String = {
            guard let name = artist, !name.isEmpty else { return "未知歌手" }
            return name
        }()
        return OnlineSong(
            id: id,
            title: title,
            artist: artistName,
            album: "",
            coverURL: coverUrl.flatMap(URL.init(string:)),
            duration: Double(durationMs ?? 0) / 1000.0,
            playCount: playCountInt
        )
    }
}

private struct TrackPageDTO: Decodable {
    let list: [TrackDTO]
    let total: Int
    let page: Int
    let pageSize: Int

    func toPagedResult() -> PagedResult<OnlineSong> {
        PagedResult(
            items: list.map { $0.toModel() },
            total: total, page: page, pageSize: pageSize
        )
    }
}

private struct LyricsDTO: Decodable {
    let lrcText: String?
    let lrcSynced: Bool?
}

private struct PlaylistDTO: Decodable {
    let id: String
    let title: String
    let coverUrl: String?
    let isPublic: Bool?

    func toModel(trackCount: Int) -> OnlinePlaylist {
        OnlinePlaylist(
            id: id,
            title: title,
            coverURL: coverUrl.flatMap(URL.init(string:)),
            creator: "",
            trackCount: trackCount,
            description: ""
        )
    }
}

private struct PlaylistDetailDTO: Decodable {
    let id: String
    let title: String
    let coverUrl: String?
    let isPublic: Bool?
    let tracks: [TrackDTO]?

    func toModel() -> PlaylistDetail {
        let songs = (tracks ?? []).map { $0.toModel() }
        return PlaylistDetail(
            playlist: PlaylistDTO(
                id: id, title: title, coverUrl: coverUrl, isPublic: isPublic
            ).toModel(trackCount: songs.count),
            songs: songs
        )
    }
}

private struct TrackSourcesDTO: Decodable {
    let preferredSource: String?
    let local: [LocalSourceDTO]?
    let platforms: [PlatformSourceDTO]?

    func toModel() -> TrackSources {
        TrackSources(
            preferredSource: preferredSource ?? "auto",
            local: (local ?? []).map { LocalSourceQuality(quality: $0.quality, bitrateKbps: $0.bitrateKbps) },
            platforms: (platforms ?? []).map { $0.toModel() }
        )
    }
}

private struct LocalSourceDTO: Decodable {
    let quality: String
    let bitrateKbps: Int
}

private struct PlatformSourceDTO: Decodable {
    let platform: String
    let platformId: String
    let title: String
    let artist: String
    let durationMs: Int?

    func toModel() -> PlatformSource {
        PlatformSource(
            platform: platform,
            platformId: platformId,
            title: title,
            artist: artist,
            durationMs: durationMs
        )
    }
}

/// 未来飙升榜响应
private struct TrendingFutureDTO: Decodable {
    let list: [TrackDTO]
    let total: Int
    let page: Int
    let pageSize: Int
    let predictions: [String: FuturePredictionDTO]?
    let fallback: Bool?

    func toResult() -> TrendingFutureResult {
        let items = list.map { dto -> TrendingSong in
            let pred = predictions?[dto.id]
            return TrendingSong(
                song: dto.toModel(),
                predicted7d: pred?.predicted7d,
                trendPct: pred?.trendPct,
                isPredicted: pred?.isPredicted ?? false
            )
        }
        return TrendingFutureResult(
            items: items,
            total: total,
            page: page,
            pageSize: pageSize,
            fallback: fallback ?? true
        )
    }
}

private struct FuturePredictionDTO: Decodable {
    let predicted7d: Int?
    let trendPct: Double?
    let isPredicted: Bool?
}

/// 歌单导入搬家报告响应
private struct PlaylistImportDTO: Decodable {
    let playlistId: String
    let playlistName: String
    let total: Int
    let matched: Int
    let unmatched: [ImportUnmatchedDTO]?

    func toReport() -> PlaylistImportReport {
        PlaylistImportReport(
            playlistId: playlistId,
            playlistName: playlistName,
            total: total,
            matched: matched,
            unmatched: (unmatched ?? []).map {
                ImportUnmatchedSong(title: $0.title, artist: $0.artist)
            }
        )
    }
}

private struct ImportUnmatchedDTO: Decodable {
    let title: String
    let artist: String
}

private struct RadioStationDTO: Decodable {
    let name: String
    let url: String
    let favicon: String?
    let tags: [String]?
    let country: String?
    let bitrate: Int?
    let codec: String?

    func toModel() -> RadioStationItem {
        RadioStationItem(
            name: name,
            url: url,
            favicon: favicon.flatMap(URL.init(string:)),
            tags: tags ?? [],
            country: country,
            bitrate: bitrate ?? 0
        )
    }
}

/// 搜索响应：list 里混了三类（本地/平台/iTunes），靠字段区分
private struct SearchPageDTO: Decodable {
    let list: [SearchItemDTO]
    let total: Int
    let page: Int
    let pageSize: Int
    /// 后端启用的平台（含付费平台 kg/kw/mg/tx/wy，仅配置 Key 时出现）
    let platformEnabled: [String]?

    func toSearchResult() -> SearchResult {
        var local: [OnlineSong] = []
        var platforms: [PlatformTrack] = []
        for item in list {
            if let p = item.toPlatformTrack() {
                platforms.append(p)
            } else if let s = item.toOnlineSong() {
                local.append(s)
            }
            // iTunes 试听（source=itunes）暂不展示
        }
        let hasMore = list.count >= pageSize
        return SearchResult(
            local: local,
            platforms: platforms,
            hasMore: hasMore,
            enabledPlatforms: platformEnabled ?? []
        )
    }
}

private struct SearchItemDTO: Decodable {
    // 本地
    let id: String?
    let playCount: String?
    // 平台
    let platform: String?
    let platformId: String?
    let external: Bool?
    // iTunes
    let source: String?
    let previewUrl: String?
    // 通用
    let title: String?
    let artist: String?
    let album: String?
    let coverUrl: String?
    let durationMs: Int?

    /// 平台歌：有 platform 字段
    func toPlatformTrack() -> PlatformTrack? {
        guard let platform = platform, let platformId = platformId,
              let title = title, !title.isEmpty else { return nil }
        return PlatformTrack(
            platform: platform,
            platformId: platformId,
            title: title,
            artist: artist ?? "未知歌手",
            album: album ?? "",
            coverURL: coverUrl.flatMap(URL.init(string:)),
            duration: Double(durationMs ?? 0) / 1000.0
        )
    }

    /// 本地歌：有 UUID id 且无 platform/source 标记
    func toOnlineSong() -> OnlineSong? {
        guard let id = id, !id.isEmpty,
              platform == nil, source == nil,
              let title = title, !title.isEmpty else { return nil }
        let playCountInt = playCount.flatMap(Int.init) ?? 0
        let artistName: String = {
            guard let a = artist, !a.isEmpty else { return "未知歌手" }
            return a
        }()
        return OnlineSong(
            id: id,
            title: title,
            artist: artistName,
            album: album ?? "",
            coverURL: coverUrl.flatMap(URL.init(string:)),
            duration: Double(durationMs ?? 0) / 1000.0,
            playCount: playCountInt
        )
    }
}
