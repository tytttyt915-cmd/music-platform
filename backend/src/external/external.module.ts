import { Module } from '@nestjs/common';
import { LyricsOvhService } from './lyrics-ovh.service';
import { MusicBrainzService } from './musicbrainz.service';
import { ITunesService } from './itunes.service';

/**
 * 第三方免费音乐 API（全都不用 key）：
 * - Lyrics.ovh：歌词补全
 * - MusicBrainz：元数据补全
 * - iTunes Search：搜索补充
 *
 * 所有服务失败一律返回 null、记 warn、绝不抛错，
 * 保证外部 API 挂了也不影响主流程。
 */
@Module({
  providers: [LyricsOvhService, MusicBrainzService, ITunesService],
  exports: [LyricsOvhService, MusicBrainzService, ITunesService],
})
export class ExternalModule {}
