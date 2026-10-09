import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/**
 * Lyrics.ovh 免费歌词 API（无需 key）。
 * GET https://api.lyrics.ovh/v1/{artist}/{title} → { lyrics: string }
 * 找不到时返回 404 { error: "..." }。
 *
 * 失败（超时/网络/404/非法响应）一律返回 null，由调用方降级，
 * 绝不抛错，保证不影响主流程。
 */
@Injectable()
export class LyricsOvhService {
  private readonly logger = new Logger(LyricsOvhService.name);
  private readonly enabled: boolean;
  private readonly baseUrl: string;
  private readonly timeoutMs: number;

  constructor(private readonly config: ConfigService) {
    this.enabled =
      (
        this.config.get<string>('external.lyricsOvh.enabled') ?? 'true'
      ).toLowerCase() === 'true';
    this.baseUrl =
      this.config.get<string>('external.lyricsOvh.baseUrl') ??
      'https://api.lyrics.ovh';
    this.timeoutMs = parseInt(
      this.config.get<string>('external.lyricsOvh.timeoutMs') ?? '5000',
      10,
    );
  }

  get isEnabled(): boolean {
    return this.enabled;
  }

  /**
   * 按 艺人/歌名 查歌词。返回纯文本歌词；查不到或失败返回 null。
   */
  async fetchLyrics(artist: string, title: string): Promise<string | null> {
    if (!this.enabled) return null;
    const a = artist.trim();
    const t = title.trim();
    if (!a || !t) return null;

    const url =
      `${this.baseUrl}/v1/${encodeURIComponent(a)}/${encodeURIComponent(t)}`;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const res = await fetch(url, {
        headers: { Accept: 'application/json' },
        signal: controller.signal,
      });
      if (!res.ok) {
        // 404 = 没这首歌的词；其他 4xx/5xx 记一条 warn
        if (res.status !== 404) {
          this.logger.warn(`Lyrics.ovh 返回 ${res.status}（${a} - ${t}）`);
        }
        return null;
      }
      const data = (await res.json()) as { lyrics?: unknown };
      if (typeof data.lyrics !== 'string' || data.lyrics.trim().length === 0) {
        return null;
      }
      return data.lyrics;
    } catch (err) {
      const reason =
        err instanceof Error && err.name === 'AbortError'
          ? `超时(${this.timeoutMs}ms)`
          : err instanceof Error
            ? err.message
            : String(err);
      this.logger.warn(`Lyrics.ovh 调用失败(${reason})：${a} - ${t}`);
      return null;
    } finally {
      clearTimeout(timer);
    }
  }
}
