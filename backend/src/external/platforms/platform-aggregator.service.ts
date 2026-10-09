import { Injectable, Logger } from '@nestjs/common';
import { NeteaseService } from './netease.service';
import {
  KgPaidSourceService,
  KwPaidSourceService,
  MgPaidSourceService,
  TxPaidSourceService,
  WyPaidSourceService,
} from './paid-source.service';
import {
  AudioQuality,
  IPlatformService,
  MusicPlatform,
  PlatformTrack,
} from './platform.types';

/**
 * 多平台聚合器：并行调用所有启用的平台，合并结果。
 *
 * 容错：任一平台失败（null/抛错）不影响其他平台和主流程。
 */
@Injectable()
export class PlatformAggregatorService {
  private readonly logger = new Logger(PlatformAggregatorService.name);
  private readonly services: IPlatformService[];

  constructor(
    private readonly netease: NeteaseService,
    private readonly kg: KgPaidSourceService,
    private readonly kw: KwPaidSourceService,
    private readonly mg: MgPaidSourceService,
    private readonly tx: TxPaidSourceService,
    private readonly wy: WyPaidSourceService,
  ) {
    // Phase 2 在此追加 qqmusic、kugou
    // 付费音源（kg/kw/mg/tx/wy）：纯 URL 解析，无搜索接口；
    // 未配置 PAID_SOURCE_API_KEY 时自动禁用，不影响聚合
    this.services = [netease, kg, kw, mg, tx, wy];
  }

  /** 启用的平台列表（供健康检查/前端展示） */
  get enabledPlatforms(): MusicPlatform[] {
    return this.services.filter((s) => s.isEnabled).map((s) => s.platform);
  }

  /**
   * 聚合搜索：并行查所有启用平台，按平台顺序合并。
   * 每个平台内部已做截断；总条数由调用方控制。
   */
  async searchAll(
    keyword: string,
    perPlatformLimit = 10,
  ): Promise<PlatformTrack[]> {
    const enabled = this.services.filter((s) => s.isEnabled);
    if (enabled.length === 0) return [];

    const results = await Promise.all(
      enabled.map(async (s) => {
        try {
          return (await s.search(keyword, perPlatformLimit)) ?? [];
        } catch (err) {
          this.logger.warn(
            `平台 ${s.platform} 搜索异常: ${
              err instanceof Error ? err.message : String(err)
            }`,
          );
          return [];
        }
      }),
    );

    return results.flat();
  }

  /**
   * 按平台获取播放直链。
   */
  async getPlayUrl(
    platform: MusicPlatform,
    platformId: string,
    quality: AudioQuality = 'high',
  ): Promise<string | null> {
    const svc = this.services.find(
      (s) => s.platform === platform && s.isEnabled,
    );
    if (!svc) {
      this.logger.warn(`平台 ${platform} 未启用或不存在`);
      return null;
    }
    try {
      return await svc.getPlayUrl(platformId, quality);
    } catch (err) {
      this.logger.warn(
        `平台 ${platform} 播放链接异常: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
      return null;
    }
  }

  /**
   * 按平台获取歌词。
   */
  async getLyric(
    platform: MusicPlatform,
    platformId: string,
  ): Promise<string | null> {
    const svc = this.services.find(
      (s) => s.platform === platform && s.isEnabled,
    );
    if (!svc) return null;
    try {
      return await svc.getLyric(platformId);
    } catch (err) {
      this.logger.warn(
        `平台 ${platform} 歌词异常: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
      return null;
    }
  }
}
