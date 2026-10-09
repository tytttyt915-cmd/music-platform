import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export interface MusicBrainzRelease {
  /** MusicBrainz recording id */
  mbid: string;
  title: string;
  artist: string;
  release: string | null;
  releaseDate: string | null;
  lengthMs: number | null;
}

/**
 * MusicBrainz 音乐元数据（无需 key，但官方要求带 User-Agent）。
 * GET https://musicbrainz.org/ws/2/recording/?query=...&fmt=json&limit=5
 *
 * 只做"元数据补全"用：封面缺失时可拿 release 信息去找 Cover Art Archive。
 * 失败返回 null，绝不抛错。
 */
@Injectable()
export class MusicBrainzService {
  private readonly logger = new Logger(MusicBrainzService.name);
  private readonly enabled: boolean;
  private readonly baseUrl: string;
  private readonly userAgent: string;
  private readonly timeoutMs: number;

  constructor(private readonly config: ConfigService) {
    this.enabled =
      (
        this.config.get<string>('external.musicbrainz.enabled') ?? 'true'
      ).toLowerCase() === 'true';
    this.baseUrl =
      this.config.get<string>('external.musicbrainz.baseUrl') ??
      'https://musicbrainz.org';
    this.userAgent =
      this.config.get<string>('external.musicbrainz.userAgent') ??
      'music-platform/1.0 (https://github.com/tytttyt915-cmd/music-platform)';
    this.timeoutMs = parseInt(
      this.config.get<string>('external.musicbrainz.timeoutMs') ?? '5000',
      10,
    );
  }

  get isEnabled(): boolean {
    return this.enabled;
  }

  /**
   * 按 艺人/歌名 查 recording。返回候选列表（按官方 score 排序）；失败返回 null。
   */
  async searchRecordings(
    artist: string,
    title: string,
    limit = 5,
  ): Promise<MusicBrainzRelease[] | null> {
    if (!this.enabled) return null;
    const q = `recording:"${title.trim()}" AND artist:"${artist.trim()}"`;
    if (!title.trim() || !artist.trim()) return null;

    const params = new URLSearchParams({
      query: q,
      fmt: 'json',
      limit: String(Math.min(Math.max(limit, 1), 10)),
    });
    const url = `${this.baseUrl}/ws/2/recording/?${params.toString()}`;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const res = await fetch(url, {
        headers: {
          Accept: 'application/json',
          'User-Agent': this.userAgent,
        },
        signal: controller.signal,
      });
      if (!res.ok) {
        this.logger.warn(`MusicBrainz 返回 ${res.status}`);
        return null;
      }
      const data = (await res.json()) as {
        recordings?: Array<{
          id?: unknown;
          title?: unknown;
          score?: unknown;
          length?: unknown;
          releases?: Array<{
            title?: unknown;
            date?: unknown;
          }>;
          'artist-credit'?: Array<{ name?: unknown }>;
        }>;
      };
      if (!Array.isArray(data.recordings)) return null;
      return data.recordings
        .filter((r) => typeof r.id === 'string')
        .map((r) => {
          const credits = Array.isArray(r['artist-credit'])
            ? r['artist-credit']
            : [];
          const artistName = credits
            .map((c) => (typeof c.name === 'string' ? c.name : ''))
            .filter((s) => s.length > 0)
            .join(', ');
          const firstRelease = Array.isArray(r.releases) ? r.releases[0] : null;
          return {
            mbid: r.id as string,
            title: typeof r.title === 'string' ? r.title : title.trim(),
            artist: artistName || artist.trim(),
            release:
              firstRelease && typeof firstRelease.title === 'string'
                ? firstRelease.title
                : null,
            releaseDate:
              firstRelease && typeof firstRelease.date === 'string'
                ? firstRelease.date
                : null,
            lengthMs:
              typeof r.length === 'number' && Number.isFinite(r.length)
                ? Math.round(r.length)
                : null,
          };
        });
    } catch (err) {
      const reason =
        err instanceof Error && err.name === 'AbortError'
          ? `超时(${this.timeoutMs}ms)`
          : err instanceof Error
            ? err.message
            : String(err);
      this.logger.warn(`MusicBrainz 调用失败(${reason})`);
      return null;
    } finally {
      clearTimeout(timer);
    }
  }
}
