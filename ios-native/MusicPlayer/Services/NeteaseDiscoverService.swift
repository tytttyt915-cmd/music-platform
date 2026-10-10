import Foundation

// MARK: - NeteaseDiscoverService
//
// 职责：发现页的网易云真实内容（直连 ncm-api，不经过 NestJS 后端）。
//   - 热门歌单：/top/playlist/highquality（真实封面 coverImgUrl）
//   - 每日推荐封面：/personalized?limit=1（真实歌单封面 picUrl）
//   - 飙升榜封面：/personalized/newsong?limit=1（真实歌曲封面 picUrl）
//   - 歌单曲目：/playlist/track/all（点歌单直接播放，转 PlatformTrack 走网易云源）
//
// ncm-api 地址：http://111.230.155.174:3000（用户腾讯云，与后端同机）。
// App 已开 NSAllowsArbitraryLoads，HTTP 直连无 ATS 问题。

/// 网易云歌单（发现页 2 列卡片用）
struct NeteasePlaylist: Identifiable, Hashable {
    let id: Int64
    let name: String
    let coverURL: URL?
    /// 创建者昵称（卡片副标题"网易云 · xxx"用）
    let creator: String
}

private struct NeteasePlaylistDTO: Decodable {
    let id: Int64
    let name: String
    let coverImgUrl: String?
    let creator: CreatorDTO?
    struct CreatorDTO: Decodable { let nickname: String? }
}

private struct PlaylistListDTO: Decodable {
    let playlists: [NeteasePlaylistDTO]?
}

private struct PersonalizedItemDTO: Decodable {
    let id: Int64
    let name: String?
    let picUrl: String?
}

private struct PersonalizedDTO: Decodable {
    let result: [PersonalizedItemDTO]?
}

private struct PlaylistTrackDTO: Decodable {
    let id: Int64
    let name: String?
    let dt: Int?
    let ar: [ArtistDTO]?
    let al: AlbumDTO?
    struct ArtistDTO: Decodable { let name: String? }
    struct AlbumDTO: Decodable { let picUrl: String? }
}

private struct PlaylistTracksDTO: Decodable {
    let songs: [PlaylistTrackDTO]?
}

private struct TopListDTO: Decodable {
    let playlist: TopPlaylistDTO?
    struct TopPlaylistDTO: Decodable {
        let name: String?
        let coverImgUrl: String?
        let tracks: [PlaylistTrackDTO]?
    }
}

final class NeteaseDiscoverService {
    static let shared = NeteaseDiscoverService()

    /// ncm-api 直连地址（与后端同机，3000 端口）
    private let base = "http://111.230.155.174:3000"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - 热门歌单（真实封面）

    /// 精品歌单列表，limit 默认 8（发现页 2 列网格）
    func hotPlaylists(limit: Int = 8) async throws -> [NeteasePlaylist] {
        let dto: PlaylistListDTO = try await get(
            "/top/playlist/highquality",
            query: ["limit": "\(limit)"]
        )
        return mapPlaylists(dto.playlists)
    }

    // MARK: - 分类歌单（歌单广场用）

    /// 歌单广场的分类（对标 Beans discover.jpg 的 chips）
    enum PlaylistCategory: String, CaseIterable {
        case all = "全部"
        case recommend = "推荐歌单"
        case highquality = "精品歌单"
        case official = "官方"
        case mandarin = "华语"
        case western = "欧美"
    }

    /// 按分类取歌单（真实封面）：
    /// - 全部：/top/playlist?order=hot
    /// - 推荐歌单：/personalized（网易云官方推荐）
    /// - 精品歌单：/top/playlist/highquality
    /// - 官方：精品歌单里过滤官方创建者
    /// - 华语/欧美：/top/playlist?cat=
    func playlists(for category: PlaylistCategory, limit: Int = 30) async throws -> [NeteasePlaylist] {
        switch category {
        case .all:
            let dto: PlaylistListDTO = try await get(
                "/top/playlist",
                query: ["order": "hot", "limit": "\(limit)"]
            )
            return mapPlaylists(dto.playlists)
        case .recommend:
            let dto: PersonalizedDTO = try await get("/personalized", query: ["limit": "\(limit)"])
            return (dto.result ?? []).map { item in
                NeteasePlaylist(
                    id: item.id,
                    name: item.name ?? "推荐歌单",
                    coverURL: sizedCover(item.picUrl, size: 400),
                    creator: "网易云音乐"
                )
            }
        case .highquality:
            return try await hotPlaylists(limit: limit)
        case .official:
            // ncm-api 没有"官方"分类：精品歌单里过滤官方创建者
            let all = try await hotPlaylists(limit: 30)
            let officials = all.filter { p in
                p.creator.contains("网易云") || p.creator.contains("官方")
            }
            return officials.isEmpty ? all : officials
        case .mandarin:
            let dto: PlaylistListDTO = try await get(
                "/top/playlist",
                query: ["cat": "华语", "limit": "\(limit)"]
            )
            return mapPlaylists(dto.playlists)
        case .western:
            let dto: PlaylistListDTO = try await get(
                "/top/playlist",
                query: ["cat": "欧美", "limit": "\(limit)"]
            )
            return mapPlaylists(dto.playlists)
        }
    }

    private func mapPlaylists(_ dtos: [NeteasePlaylistDTO]?) -> [NeteasePlaylist] {
        (dtos ?? []).map { p in
            NeteasePlaylist(
                id: p.id,
                name: p.name,
                coverURL: sizedCover(p.coverImgUrl, size: 400),
                creator: p.creator?.nickname ?? "网易云音乐"
            )
        }
    }

    // MARK: - 大卡片封面（真实图片）

    /// 每日推荐卡片封面：取推荐歌单首张真实封面
    func dailyCoverURL() async throws -> URL? {
        let dto: PersonalizedDTO = try await get("/personalized", query: ["limit": "1"])
        return sizedCover(dto.result?.first?.picUrl, size: 600)
    }

    /// 未来飙升榜卡片封面：取新歌首单真实封面
    func trendingCoverURL() async throws -> URL? {
        let dto: PersonalizedDTO = try await get("/personalized/newsong", query: ["limit": "1"])
        return sizedCover(dto.result?.first?.picUrl, size: 600)
    }

    // MARK: - 歌单曲目（点卡片直接播放）

    /// 歌单全部曲目 → 转 PlatformTrack（platform=netease，走后端 /music/platform/netease/stream 302 直链）
    func playlistTracks(id: Int64, limit: Int = 50) async throws -> [PlatformTrack] {
        let dto: PlaylistTracksDTO = try await get(
            "/playlist/track/all",
            query: ["id": "\(id)", "limit": "\(limit)"]
        )
        return mapTracks(dto.songs)
    }

    // MARK: - 相似歌曲（私人漫游用，[Beans#7]）

    /// /simi/song：根据歌曲 id 取相似歌曲（免登录）。
    /// 私人漫游的"漫游"就靠它：当前歌曲 → 相似歌曲 → 下一首的相似歌曲……
    func similarSongs(id: String, limit: Int = 10) async throws -> [PlatformTrack] {
        let dto: PlaylistTracksDTO = try await get(
            "/simi/song",
            query: ["id": id, "limit": "\(limit)"]
        )
        return mapTracks(dto.songs)
    }

    // MARK: - 排行榜（[Beans#7] 顺序即推荐）

    /// 榜单曲目：idx 1=热歌榜，2=新歌榜，4=飙升榜（ncm-api 经典索引）。
    func chartSongs(idx: Int, limit: Int = 20) async throws -> [PlatformTrack] {
        let dto: TopListDTO = try await get(
            "/top/list",
            query: ["idx": "\(idx)"]
        )
        return Array(mapTracks(dto.playlist?.tracks).prefix(limit))
    }

    /// 榜单元信息（名字 + 封面，排行榜卡片用）
    func chartInfo(idx: Int) async throws -> (name: String, coverURL: URL?) {
        let dto: TopListDTO = try await get(
            "/top/list",
            query: ["idx": "\(idx)"]
        )
        return (
            name: dto.playlist?.name ?? "榜单",
            coverURL: sizedCover(dto.playlist?.coverImgUrl, size: 400)
        )
    }

    /// 网易云歌曲 DTO → PlatformTrack（歌单/相似/榜单共用）
    private func mapTracks(_ songs: [PlaylistTrackDTO]?) -> [PlatformTrack] {
        (songs ?? []).compactMap { s in
            let artist = (s.ar ?? []).compactMap { $0.name }.joined(separator: "/")
            guard !artist.isEmpty || !(s.name?.isEmpty ?? true) else { return nil }
            return PlatformTrack(
                platform: "netease",
                platformId: "\(s.id)",
                title: s.name ?? "未知歌曲",
                artist: artist.isEmpty ? "未知歌手" : artist,
                album: "",
                coverURL: sizedCover(s.al?.picUrl, size: 300),
                duration: Double(s.dt ?? 0) / 1000.0
            )
        }
    }

    // MARK: - 私有

    /// 网易云封面裁剪参数：?param=400y400，保证列表图体积
    private func sizedCover(_ raw: String?, size: Int) -> URL? {
        guard var raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") {
            // p3.music.126.net 等域名 http 可用（App 已放行明文 HTTP）
        } else if raw.hasPrefix("https://") {
            // 保持 https
        } else {
            return nil
        }
        if !raw.contains("param=") {
            raw += "?param=\(size)y\(size)"
        }
        return URL(string: raw)
    }

    private func get<T: Decodable>(_ path: String, query: [String: String]) async throws -> T {
        var components = URLComponents(string: base + path)
        components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
