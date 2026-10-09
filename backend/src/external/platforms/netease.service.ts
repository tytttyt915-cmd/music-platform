import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  AudioQuality,
  IPlatformService,
  MusicPlatform,
  PlatformTrack,
} from './platform.types';

/**
 * 网易云音乐 service（via ncm-api sidecar）。
 *
 * ncm-api 部署：docker run -d -p 3001:3000 moefurina/ncm-api:latest
 * 接口文档：https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced
 *
 * 用到的接口：
 * - GET /cloudsearch?keywords=..&type=1&limit=..  搜索单曲
 * - GET /song/url/v1?id=..&level=..              播放链接
 * - GET /lyric?id=..                            歌词
 *
 * 注意：
 * - 云服务器需传 realIP（国内 IP）避免 460 cheating
 * - Enhanced 版默认开启解灰（ENABLE_GENERAL_UNBLOCK=true）
 * - 失败返回 null，绝不抛错
 */
@Injectable()
export class NeteaseService implements IPlatformService {
  readonly platform: MusicPlatform = 'netease';
  private readonly logger = new Logger(NeteaseService.name);
  private readonly enabled: boolean;
  private readonly baseUrl: string;
  private readonly realIp: string;
  private readonly timeoutMs: number;
  private readonly maxResults: number;

  constructor(private readonly config: ConfigService) {
    this.enabled =
      (
        this.config.get<string>('external.netease.enabled') ?? 'true'
      ).toLowerCase() === 'true';
    this.baseUrl =
      this.config.get<string>('external.netease.baseUrl') ??
      'http://ncm-api:3001';
    this.realIp =
      this.config.get<string>('external.netease.realIp') ?? '116.25.146.177';
    this.timeoutMs = parseInt(
      this.config.get<string>('external.netease.timeoutMs') ?? '8000',
      10,
    );
    this.maxResults = parseInt(
      this.config.get<string>('external.netease.maxResults') ?? '10',
      10,
    );
  }

  get isEnabled(): boolean {
    return this.enabled;
  }

  async search(keyword: string, limit?: number): Promise<PlatformTrack[] | null> {
    if (!this.enabled || !keyword.trim()) return null;
    const n = Math.min(limit ?? this.maxResults, 30);

    try {
      const url =
        `${this.baseUrl}/cloudsearch` +
        `?keywords=${encodeURIComponent(keyword)}` +
        `&type=1&limit=${n}` +
        `&realIP=${encodeURIComponent(this.realIp)}` +
        `&timestamp=${Date.now()}`;

      const res = await this.fetchJson(url);
      const songs = res?.result?.songs;
      if (!Array.isArray(songs) || songs.length === 0) return null;

      return songs.map((s: any): PlatformTrack => ({
        platform: 'netease',
        platformId: String(s.id),
        title: String(s.name ?? ''),
        artist: Array.isArray(s.ar)
          ? s.ar.map((a: any) => a?.name).filter(Boolean).join('、')
          : '',
        album: s.al?.name ? String(s.al.name) : null,
        coverUrl: s.al?.picUrl ? String(s.al.picUrl) : null,
        durationMs:
          typeof s.dt === 'number' && s.dt > 0 ? s.dt : null,
        external: true as const,
      }));
    } catch (err) {
      this.logger.warn(
        `网易云搜索失败: ${err instanceof Error ? err.message : String(err)}`,
      );
      return null;
    }
  }

  async getPlayUrl(
    platformId: string,
    quality: AudioQuality = 'high',
  ): Promise<string | null> {
    if (!this.enabled || !platformId) return null;

    // ncm-api level: standard(128k) / higher(192k) / exhigh(320k) / lossless(无损)
    const level =
      quality === 'lossless'
        ? 'lossless'
        : quality === 'standard'
          ? 'standard'
          : 'exhigh';

    try {
      const url =
        `${this.baseUrl}/song/url/v1` +
        `?id=${encodeURIComponent(platformId)}` +
        `&level=${level}` +
        `&realIP=${encodeURIComponent(this.realIp)}` +
        `&timestamp=${Date.now()}`;

      const res = await this.fetchJson(url);
      const data = res?.data;
      if (!Array.isArray(data) || data.length === 0) return null;

      const item = data[0];
      const playUrl = item?.url;
      if (typeof playUrl !== 'string' || playUrl.length === 0) {
        // 可能是 VIP/无版权，ncm-api 解灰失败时 url 为空
        this.logger.warn(`网易云歌曲 ${platformId} 无可用播放链接`);
        return null;
      }
      return playUrl;
    } catch (err) {
      this.logger.warn(
        `网易云播放链接失败: ${err instanceof Error ? err.message : String(err)}`,
      );
      return null;
    }
  }

  async getLyric(platformId: string): Promise<string | null> {
    if (!this.enabled || !platformId) return null;

    try {
      const url =
        `${this.baseUrl}/lyric` +
        `?id=${encodeURIComponent(platformId)}` +
        `&realIP=${encodeURIComponent(this.realIp)}` +
        `&timestamp=${Date.now()}`;

      const res = await this.fetchJson(url);
      const lyric = res?.lrc?.lyric;
      if (typeof lyric !== 'string' || lyric.trim().length === 0) return null;
      return lyric;
    } catch (err) {
      this.logger.warn(
        `网易云歌词失败: ${err instanceof Error ? err.message : String(err)}`,
      );
      return null;
    }
  }

  /** 带超时的 JSON GET。非 2xx / 非 JSON / 超时一律抛错，由调用方捕获。 */
  private async fetchJson(url: string): Promise<any> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const res = await fetch(url, {
        signal: controller.signal,
        headers: { 'User-Agent': 'music-platform/1.0' },
      });
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }
      return await res.json();
    } finally {
      clearTimeout(timer);
    }
  }
}
