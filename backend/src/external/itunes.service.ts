import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export interface ITunesTrack {
  /** 标记为第三方补充结果：本地无可播音频 */
  external: true;
  source: 'itunes';
  title: string;
  artist: string;
  album: string | null;
  coverUrl: string | null;
  durationMs: number | null;
  /** 30 秒试听（Apple 官方提供，可直接播） */
  previewUrl: string | null;
  /** iTunes 链接 */
  trackViewUrl: string | null;
}

/**
 * iTunes Search API（无需 key，Apple 官方）。
 * GET https://itunes.apple.com/search?term=...&media=music&entity=song
 *
 * 用于 /music/search 的补充结果：本地库没有时，给用户看看 Apple 音乐库里有啥。
 * 返回的条目带 external: true 标记，前端不得当作可播曲目处理。
 * 失败返回 null，绝不抛错。
 */
@Injectable()
export class ITunesService {
  private readonly logger = new Logger(ITunesService.name);
  private readonly enabled: boolean;
  private readonly baseUrl: string;
  private readonly country: string;
  private readonly timeoutMs: number;
  private readonly maxResults: number;

  constructor(private readonly config: ConfigService) {
    this.enabled =
      (
        this.config.get<string>('external.itunes.enabled') ?? 'true'
      ).toLowerCase() === 'true';
    this.baseUrl =
      this.config.get<string>('external.itunes.baseUrl') ??
      'https://itunes.apple.com';
    this.country = this.config.get<string>('external.itunes.country') ?? 'CN';
    this.timeoutMs = parseInt(
      this.config.get<string>('external.itunes.timeoutMs') ?? '5000',
      10,
    );
    this.maxResults = parseInt(
      this.config.get<string>('external.itunes.maxResults') ?? '5',
      10,
    );
  }

  get isEnabled(): boolean {
    return this.enabled;
  }

  /**
   * 搜索 Apple 音乐库。返回补充条目；失败/无结果返回 null。
   */
  async search(q: string): Promise<ITunesTrack[] | null> {
    if (!this.enabled) return null;
    const term = q.trim();
    if (!term) return null;

    const params = new URLSearchParams({
      term,
      media: 'music',
      entity: 'song',
      limit: String(Math.min(Math.max(this.maxResults, 1), 10)),
      country: this.country,
      lang: 'zh_cn',
    });
    const url = `${this.baseUrl}/search?${params.toString()}`;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const res = await fetch(url, {
        headers: { Accept: 'application/json' },
        signal: controller.signal,
      });
      if (!res.ok) {
        this.logger.warn(`iTunes Search 返回 ${res.status}`);
        return null;
      }
      const data = (await res.json()) as {
        resultCount?: unknown;
        results?: Array<{
          trackName?: unknown;
          artistName?: unknown;
          collectionName?: unknown;
          artworkUrl100?: unknown;
          trackTimeMillis?: unknown;
          previewUrl?: unknown;
          trackViewUrl?: unknown;
        }>;
      };
      if (!Array.isArray(data.results) || data.results.length === 0) {
        return null;
      }
      const list: ITunesTrack[] = [];
      for (const r of data.results) {
        if (typeof r.trackName !== 'string' || r.trackName.trim() === '') {
          continue;
        }
        list.push({
          external: true,
          source: 'itunes',
          title: r.trackName,
          artist:
            typeof r.artistName === 'string' && r.artistName.trim() !== ''
              ? r.artistName
              : '未知艺人',
          album:
            typeof r.collectionName === 'string' ? r.collectionName : null,
          coverUrl:
            typeof r.artworkUrl100 === 'string'
              ? r.artworkUrl100.replace('100x100bb', '300x300bb')
              : null,
          durationMs:
            typeof r.trackTimeMillis === 'number' &&
            Number.isFinite(r.trackTimeMillis)
              ? Math.round(r.trackTimeMillis)
              : null,
          previewUrl:
            typeof r.previewUrl === 'string' ? r.previewUrl : null,
          trackViewUrl:
            typeof r.trackViewUrl === 'string' ? r.trackViewUrl : null,
        });
      }
      return list.length > 0 ? list : null;
    } catch (err) {
      const reason =
        err instanceof Error && err.name === 'AbortError'
          ? `超时(${this.timeoutMs}ms)`
          : err instanceof Error
            ? err.message
            : String(err);
      this.logger.warn(`iTunes Search 调用失败(${reason})：${term}`);
      return null;
    } finally {
      clearTimeout(timer);
    }
  }
}
