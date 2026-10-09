import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/**
 * Radio Browser 免费电台 API（无需 key）。
 * https://www.radio-browser.info/ —— 3 万+ 电台。
 * GET https://de1.api.radio-browser.info/json/stations/bytag/{tag}
 *   → [{ name, url_resolved, favicon, tags, country, bitrate, codec }]
 *
 * 多 mirror failover：de1 → de2 → nl1。
 * 失败一律返回 null/[]，绝不抛错。
 */

export interface RadioStation {
  name: string;
  url: string;
  favicon: string | null;
  tags: string[];
  country: string | null;
  bitrate: number;
  codec: string | null;
}

const MIRRORS = [
  'https://de1.api.radio-browser.info',
  'https://de2.api.radio-browser.info',
  'https://nl1.api.radio-browser.info',
];

@Injectable()
export class RadioService {
  private readonly logger = new Logger(RadioService.name);
  private readonly enabled: boolean;
  private readonly timeoutMs: number;

  constructor(private readonly config: ConfigService) {
    this.enabled =
      (this.config.get<string>('external.radio.enabled') ?? 'true').toLowerCase() ===
      'true';
    this.timeoutMs = parseInt(
      this.config.get<string>('external.radio.timeoutMs') ?? '5000',
      10,
    );
  }

  get isEnabled(): boolean {
    return this.enabled;
  }

  /**
   * 按标签搜电台（如 jazz / pop / classical / news）。
   * 只返回有可播 URL 的，按投票数排序。
   */
  async searchByTag(tag: string, limit = 30): Promise<RadioStation[]> {
    if (!this.enabled) return [];
    const t = tag.trim().toLowerCase();
    if (!t) return [];

    for (const mirror of MIRRORS) {
      const url =
        `${mirror}/json/stations/bytag/${encodeURIComponent(t)}` +
        `?order=votes&reverse=true&limit=${limit}&hidebroken=true`;
      const stations = await this.fetchStations(url);
      if (stations !== null) return stations;
      // null = 该 mirror 失败，试下一个
    }
    return [];
  }

  /**
   * 热门电台（按投票）。
   */
  async topStations(limit = 30): Promise<RadioStation[]> {
    if (!this.enabled) return [];
    for (const mirror of MIRRORS) {
      const url =
        `${mirror}/json/stations/topvote/${limit}?hidebroken=true`;
      const stations = await this.fetchStations(url);
      if (stations !== null) return stations;
    }
    return [];
  }

  private async fetchStations(url: string): Promise<RadioStation[] | null> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const res = await fetch(url, {
        headers: {
          Accept: 'application/json',
          'User-Agent': 'MusicPlatform/1.0 (radio)',
        },
        signal: controller.signal,
      });
      if (!res.ok) {
        this.logger.warn(`Radio Browser 返回 ${res.status}`);
        return null;
      }
      const data = (await res.json()) as unknown;
      if (!Array.isArray(data)) return null;
      return data
        .filter(
          (s): s is Record<string, unknown> =>
            typeof s === 'object' &&
            s !== null &&
            typeof (s as Record<string, unknown>).url_resolved === 'string' &&
            ((s as Record<string, unknown>).url_resolved as string).startsWith('http'),
        )
        .map((s) => ({
          name: String(s.name ?? '未知电台'),
          url: s.url_resolved as string,
          favicon:
            typeof s.favicon === 'string' && s.favicon ? s.favicon : null,
          tags:
            typeof s.tags === 'string'
              ? (s.tags as string).split(',').map((x) => x.trim()).filter(Boolean).slice(0, 5)
              : [],
          country: typeof s.country === 'string' && s.country ? (s.country as string) : null,
          bitrate: typeof s.bitrate === 'number' ? (s.bitrate as number) : 0,
          codec: typeof s.codec === 'string' && s.codec ? (s.codec as string) : null,
        }));
    } catch (err) {
      this.logger.warn(
        `Radio Browser 异常: ${err instanceof Error ? err.message : String(err)}`,
      );
      return null;
    } finally {
      clearTimeout(timer);
    }
  }
}
