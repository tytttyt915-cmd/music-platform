import { Module } from '@nestjs/common';
import { NeteaseService } from './netease.service';
import { PlatformAggregatorService } from './platform-aggregator.service';

/**
 * 国内音乐平台模块（Phase 1：网易云）。
 *
 * - NeteaseService：via ncm-api sidecar（http://ncm-api:3000）
 * - PlatformAggregatorService：多平台聚合搜索/播放/歌词
 *
 * Phase 2 预留：QQMusicService、KugouService 实现 IPlatformService 后，
 * 在 providers/exports 里注册即可，聚合器自动纳入。
 */
@Module({
  providers: [NeteaseService, PlatformAggregatorService],
  exports: [NeteaseService, PlatformAggregatorService],
})
export class PlatformsModule {}
