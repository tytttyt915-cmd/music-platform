import { Module } from '@nestjs/common';
import { NeteaseService } from './netease.service';
import {
  KgPaidSourceService,
  KwPaidSourceService,
  MgPaidSourceService,
  TxPaidSourceService,
  WyPaidSourceService,
} from './paid-source.service';
import { PlatformAggregatorService } from './platform-aggregator.service';

/**
 * 国内音乐平台模块。
 *
 * - NeteaseService：via ncm-api sidecar（http://ncm-api:3000）
 * - 付费音源（聆澜赞助版 API）：kg/kw/mg/tx/wy 五个 URL 解析服务，
 *   API Key 走环境变量 PAID_SOURCE_API_KEY，未配置时自动禁用
 * - PlatformAggregatorService：多平台聚合搜索/播放/歌词
 *
 * Phase 2 预留：QQMusicService、KugouService 实现 IPlatformService 后，
 * 在 providers/exports 里注册即可，聚合器自动纳入。
 */
@Module({
  providers: [
    NeteaseService,
    KgPaidSourceService,
    KwPaidSourceService,
    MgPaidSourceService,
    TxPaidSourceService,
    WyPaidSourceService,
    PlatformAggregatorService,
  ],
  exports: [
    NeteaseService,
    KgPaidSourceService,
    KwPaidSourceService,
    MgPaidSourceService,
    TxPaidSourceService,
    WyPaidSourceService,
    PlatformAggregatorService,
  ],
})
export class PlatformsModule {}
