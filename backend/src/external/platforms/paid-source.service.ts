import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  AudioQuality,
  IPlatformService,
  MusicPlatform,
  PaidSourcePlatform,
  PlatformTrack,
} from './platform.types';

/**
 * 付费音源 service（聆澜音源赞助版 API）。
 *
 * 源插件：~/workspace/user/files/lx-music-source-paid-1791558865673.js（v8.9）
 * 该插件是纯 URL 解析器（LX Music 的 musicUrl action），没有搜索接口。
 * 因此 search()/getLyric() 返回 null，只实现 getPlayUrl()。
 *
 * 接口：
 * - GET {baseUrl}/music/url?source={source}&songId={songId}&quality={quality}
 * - 认证：X-API-Key 请求头（环境变量 PAID_SOURCE_API_KEY）
 * - 成功：{code: 0|200, url: "https://..."}；403 = Key 失效；429 = 限流
 *
 * 5 个 source 代号：kg（酷狗）、kw（酷我）、mg（咪咕）、tx（腾讯）、wy（网易）
 * 各平台支持的音质见 QUALITY_BY_SOURCE（取自插件 MUSIC_QUALITY）。
 *
 * 失败返回 null，绝不抛错。
 */
const API_BASE_URL = 'https://source.shiqianjiang.cn/api';

/** 各 source 支持的音质（插件 MUSIC_QUALITY 原样搬运） */
const QUALITY_BY_SOURCE: Record<PaidSourcePlatform, string[]> = {
  kg: ['128k', '320k', 'flac', 'flac24bit', 'hires', 'atmos', 'master'],
  kw: ['128k', '320k', 'flac', 'flac24bit', 'hires'],
  mg: ['128k', '320k', 'flac', 'flac24bit', 'hires'],
  tx: ['128k', '320k', 'flac', 'flac24bit', 'hires', 'atmos', 'atmos_plus', 'master'],
  wy: ['128k', '320k', 'flac', 'flac24bit', 'hires', 'atmos', 'master'],
};

/** 通用音质 → API 音质候选（按优先级，取该 source 支持的第一个） */
const QUALITY_CANDIDATES: Record<AudioQuality, string[]> = {
  standard: ['128k'],
  high: ['320k', '128k'],
  lossless: ['flac', 'flac24bit', 'hires', '320k', '128k'],
};

/** source 代号 → 中文名（日志用） */
const SOURCE_NAMES: Record<PaidSourcePlatform, string> = {
  kg: '酷狗',
  kw: '酷我',
  mg: '咪咕',
  tx: '腾讯',
  wy: '网易',
};

/**
 * 共享实现基类。5 个 source 共用同一套 HTTP 逻辑，
 * 区别只有 platform 代号和支持的音质表。
 */
abstract class PaidSourceBase implements IPlatformService {
  abstract readonly platform: PaidSourcePlatform;

  protected readonly logger: Logger;
  private readonly enabled: boolean;
  private readonly apiKey: string;
  private readonly baseUrl: string;
  private readonly timeoutMs: number;

  constructor(protected readonly config: ConfigService) {
    this.logger = new Logger(`${this.constructor.name}`);
    this.enabled =
      (
        this.config.get<string>('external.paid.enabled') ?? 'true'
      ).toLowerCase() === 'true';
    this.apiKey = this.config.get<string>('external.paid.apiKey') ?? '';
    this.baseUrl =
      this.config.get<string>('external.paid.baseUrl') ?? API_BASE_URL;
    this.timeoutMs = parseInt(
      this.config.get<string>('external.paid.timeoutMs') ?? '15000',
      10,
    );
  }

  /** 开关打开且配置了 API Key 才算启用 */
  get isEnabled(): boolean {
    return this.enabled && this.apiKey.length > 0;
  }

  /**
   * 该插件没有搜索接口（纯 musicUrl 解析器），返回 null。
   * platformId 的来源：lx-music 侧的 musicInfo.hash/songmid/id。
   */
  async search(
    _keyword: string,
    _limit?: number,
  ): Promise<PlatformTrack[] | null> {
    return null;
  }

  async getPlayUrl(
    platformId: string,
    quality: AudioQuality = 'high',
  ): Promise<string | null> {
    if (!this.isEnabled || !platformId) return null;
    const source = this.platform;

    const apiQuality = this.pickQuality(source, quality);
    if (!apiQuality) {
      this.logger.warn(
        `[${SOURCE_NAMES[source]}] 无可用音质映射（请求 ${quality}）`,
      );
      return null;
    }

    try {
      const url =
        `${this.baseUrl}/music/url` +
        `?source=${encodeURIComponent(source)}` +
        `&songId=${encodeURIComponent(platformId)}` +
        `&quality=${encodeURIComponent(apiQuality)}`;

      const body = await this.fetchJson(url);
      const code = Number(body?.code);

      if (Number.isNaN(code)) {
        throw new Error('服务端响应缺少有效业务码');
      }
      // Go 服务统一返回 200；code=0 兼容旧通道
      if (code === 0 || code === 200) {
        const playUrl = body?.url;
        if (typeof playUrl !== 'string' || playUrl.length === 0) {
          throw new Error('服务端返回成功但无音乐链接');
        }
        return playUrl;
      }
      switch (code) {
        case 403:
          throw new Error('权限不足或 Key 失效');
        case 429:
          throw new Error('请求过速，请稍后再试');
        default:
          throw new Error(
            typeof body?.message === 'string' && body.message.length > 0
              ? body.message
              : `服务端错误: ${code}`,
          );
      }
    } catch (err) {
      this.logger.warn(
        `[${SOURCE_NAMES[source]}] 播放链接失败(${platformId}/${apiQuality}): ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
      return null;
    }
  }

  /** 该插件没有歌词接口，返回 null */
  async getLyric(_platformId: string): Promise<string | null> {
    return null;
  }

  /** 从该 source 支持的音质里挑第一个候选 */
  private pickQuality(
    source: PaidSourcePlatform,
    quality: AudioQuality,
  ): string | null {
    const supported = QUALITY_BY_SOURCE[source];
    const candidates = QUALITY_CANDIDATES[quality] ?? QUALITY_CANDIDATES.high;
    return candidates.find((q) => supported.includes(q)) ?? null;
  }

  /** 带超时的 JSON GET。非 2xx / 非 JSON / 超时一律抛错，由调用方捕获。 */
  private async fetchJson(url: string): Promise<any> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const res = await fetch(url, {
        signal: controller.signal,
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': this.apiKey,
          'User-Agent': 'music-platform/1.0',
        },
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

@Injectable()
export class KgPaidSourceService extends PaidSourceBase {
  readonly platform: PaidSourcePlatform = 'kg';
  constructor(config: ConfigService) {
    super(config);
  }
}

@Injectable()
export class KwPaidSourceService extends PaidSourceBase {
  readonly platform: PaidSourcePlatform = 'kw';
  constructor(config: ConfigService) {
    super(config);
  }
}

@Injectable()
export class MgPaidSourceService extends PaidSourceBase {
  readonly platform: PaidSourcePlatform = 'mg';
  constructor(config: ConfigService) {
    super(config);
  }
}

@Injectable()
export class TxPaidSourceService extends PaidSourceBase {
  readonly platform: PaidSourcePlatform = 'tx';
  constructor(config: ConfigService) {
    super(config);
  }
}

@Injectable()
export class WyPaidSourceService extends PaidSourceBase {
  readonly platform: PaidSourcePlatform = 'wy';
  constructor(config: ConfigService) {
    super(config);
  }
}
