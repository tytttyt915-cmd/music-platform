import {
  BadRequestException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Redis } from 'ioredis';
import { Repository } from 'typeorm';
import { REDIS_CLIENT } from '../redis/redis.module';
import { StorageService } from '../storage/storage.service';
import { PlayEvent } from '../entities/play-event.entity';
import { Track, TRACK_STATUS_ONLINE } from '../entities/track.entity';
import { TrackSource } from '../entities/track-source.entity';
import {
  PredictionService,
  TrackPrediction,
} from '../prediction/prediction.service';
import { LyricsOvhService } from '../external/lyrics-ovh.service';
import { ITunesService, ITunesTrack } from '../external/itunes.service';
import {
  MusicBrainzRelease,
  MusicBrainzService,
} from '../external/musicbrainz.service';

export interface PageResult<T> {
  list: T[];
  total: number;
  page: number;
  pageSize: number;
}

const PLAY_KEY = (userId: string, trackId: string, day: string) =>
  `play:${userId}:${trackId}:${day}`;

@Injectable()
export class MusicService {
  private readonly logger = new Logger(MusicService.name);

  constructor(
    @InjectRepository(Track)
    private readonly tracksRepo: Repository<Track>,
    @InjectRepository(TrackSource)
    private readonly sourcesRepo: Repository<TrackSource>,
    @InjectRepository(PlayEvent)
    private readonly playEventsRepo: Repository<PlayEvent>,
    @Inject(REDIS_CLIENT)
    private readonly redis: Redis,
    private readonly storage: StorageService,
    private readonly prediction: PredictionService,
    private readonly lyricsOvh: LyricsOvhService,
    private readonly itunes: ITunesService,
    private readonly musicbrainz: MusicBrainzService,
  ) {}

  // ---------------- 分页音乐流 ----------------

  async feed(
    page: number,
    pageSize: number,
    sort: 'trending' | 'plays' = 'trending',
  ): Promise<PageResult<Track>> {
    if (sort === 'trending' && this.prediction.isEnabled) {
      try {
        return await this.trendingFeed(page, pageSize);
      } catch (err) {
        this.logger.warn(
          `热度预测 feed 失败，回退到 playCount 排序: ${
            err instanceof Error ? err.message : String(err)
          }`,
        );
      }
    }
    return this.playsFeed(page, pageSize);
  }

  /** 传统按累计播放量排序（预测不可用时的降级）。 */
  private async playsFeed(
    page: number,
    pageSize: number,
  ): Promise<PageResult<Track>> {
    const [list, total] = await this.tracksRepo.findAndCount({
      where: { status: TRACK_STATUS_ONLINE },
      order: { playCount: 'DESC', id: 'ASC' },
      skip: (page - 1) * pageSize,
      take: pageSize,
    });
    return { list, total, page, pageSize };
  }

  /**
   * 热度预测排序：取候选集 → TimesFM 批量预测未来 7 天 →
   * 按 predicted7d 降序（预测失败的按 playCount），内存分页。
   */
  private async trendingFeed(
    page: number,
    pageSize: number,
  ): Promise<PageResult<Track>> {
    const candidates = await this.tracksRepo.find({
      where: { status: TRACK_STATUS_ONLINE },
      order: { playCount: 'DESC', id: 'ASC' },
      take: this.prediction.maxCandidates,
    });
    const total = await this.tracksRepo.count({
      where: { status: TRACK_STATUS_ONLINE },
    });
    if (candidates.length === 0) {
      return { list: [], total, page, pageSize };
    }
    const preds = await this.prediction.predictBatch(
      candidates.map((t) => t.id),
    );
    const scored = candidates.map((t) => {
      const p = preds.get(t.id);
      return {
        track: t,
        // 预测成功用 predicted7d；失败/无历史用累计 playCount 降级
        score:
          p && !p.fallback
            ? p.predicted7d
            : parseInt(t.playCount ?? '0', 10) || 0,
        predicted: p?.predicted7d ?? null,
      };
    });
    scored.sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      return a.track.id.localeCompare(b.track.id);
    });
    const start = (page - 1) * pageSize;
    const list = scored
      .slice(start, start + pageSize)
      .map((s) => s.track);
    return { list, total, page, pageSize };
  }

  /** 单首歌热度预测（供 /music/track/:id/predict）。 */
  async predictTrack(id: string): Promise<{
    trackId: string;
    title: string;
    prediction: TrackPrediction | null;
    fallbackReason: string | null;
  }> {
    const track = await this.tracksRepo.findOne({
      where: { id, status: TRACK_STATUS_ONLINE },
      select: ['id', 'title'],
    });
    if (!track) {
      throw new NotFoundException('歌曲不存在或已下线');
    }
    const prediction = await this.prediction.predictTrack(id);
    return {
      trackId: id,
      title: track.title,
      prediction,
      fallbackReason: prediction
        ? null
        : '无有效播放历史或预测服务不可用，已降级',
    };
  }

  // ---------------- 搜索 ----------------

  async search(q: string, page: number, pageSize: number) {
    const qb = this.tracksRepo
      .createQueryBuilder('t')
      .where('t.status = :status', { status: TRACK_STATUS_ONLINE });
    if (q) {
      // 转义 LIKE 通配符，防止注入式模糊匹配
      const escaped = q.replace(/[\\%_]/g, (m) => `\\${m}`);
      qb.andWhere('(t.title ILIKE :q ESCAPE \'\\\' OR t.artist ILIKE :q ESCAPE \'\\\')', {
        q: `%${escaped}%`,
      });
    }
    qb.orderBy('t.play_count', 'DESC').addOrderBy('t.id', 'ASC');
    const total = await qb.getCount();
    const list = await qb
      .skip((page - 1) * pageSize)
      .take(pageSize)
      .getMany();

    // 第三方补充：本地库命中不足时，用 iTunes Search 补几条（标记 external，不可播）
    let external: ITunesTrack[] = [];
    if (q) {
      try {
        const results = await this.itunes.search(q);
        external = results ?? [];
      } catch (err) {
        // 服务本身已保证不抛错；这里是最后一道保险
        this.logger.warn(
          `iTunes 补充搜索异常: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }
    const merged: Array<Track | ITunesTrack> = [...list, ...external];
    return {
      list: merged,
      total: total + external.length,
      localTotal: total,
      externalTotal: external.length,
      page,
      pageSize,
    };
  }

  // ---------------- 歌曲详情 / 歌词 ----------------

  /**
   * 歌曲详情。专辑/封面缺失时，用 MusicBrainz 免费 API 做元数据补全
   * （只补在返回体里，不写库，避免污染本地数据）。
   */
  async getTrack(id: string) {
    const track = await this.tracksRepo.findOne({
      where: { id, status: TRACK_STATUS_ONLINE },
      relations: ['sources'],
    });
    if (!track) {
      throw new NotFoundException('歌曲不存在或已下线');
    }

    let externalMetadata: MusicBrainzRelease | null = null;
    if (!track.album) {
      try {
        const candidates = await this.musicbrainz.searchRecordings(
          track.artist,
          track.title,
          1,
        );
        externalMetadata = candidates && candidates.length > 0 ? candidates[0] : null;
      } catch (err) {
        // 服务本身已保证不抛错；这里是最后一道保险
        this.logger.warn(
          `MusicBrainz 补元数据异常: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }
    return { ...track, externalMetadata };
  }

  /**
   * 歌词：先查库；库里没有则调 Lyrics.ovh 免费 API 补，
   * 拿到后回写数据库（lrcSynced=false，纯文本非同步歌词），下次直接命中。
   */
  async getLyrics(id: string) {
    const track = await this.tracksRepo.findOne({
      where: { id, status: TRACK_STATUS_ONLINE },
      select: ['id', 'title', 'artist', 'lrcText', 'lrcSynced'],
    });
    if (!track) {
      throw new NotFoundException('歌曲不存在或已下线');
    }
    if (track.lrcText && track.lrcText.trim().length > 0) {
      return { lrcText: track.lrcText, lrcSynced: track.lrcSynced, source: 'db' as const };
    }

    let lyrics: string | null = null;
    try {
      lyrics = await this.lyricsOvh.fetchLyrics(track.artist, track.title);
    } catch (err) {
      // 服务本身已保证不抛错；这里是最后一道保险
      this.logger.warn(
        `Lyrics.ovh 补歌词异常: ${err instanceof Error ? err.message : String(err)}`,
      );
    }

    if (lyrics) {
      try {
        await this.tracksRepo.update(
          { id },
          { lrcText: lyrics, lrcSynced: false },
        );
      } catch (err) {
        this.logger.warn(
          `歌词回写失败(不影响返回): ${err instanceof Error ? err.message : String(err)}`,
        );
      }
      return { lrcText: lyrics, lrcSynced: false, source: 'lyrics.ovh' as const };
    }
    return { lrcText: null, lrcSynced: false, source: null };
  }

  // ---------------- 流媒体：预签名 302 ----------------

  async getStreamRedirect(id: string, quality: string) {
    const track = await this.tracksRepo.findOne({
      where: { id, status: TRACK_STATUS_ONLINE },
      select: ['id'],
    });
    if (!track) {
      throw new NotFoundException('歌曲不存在或已下线');
    }
    const source = await this.sourcesRepo.findOne({
      where: { trackId: id, quality },
    });
    if (!source) {
      throw new NotFoundException(`该歌曲暂无 ${quality} 码率`);
    }
    const url = await this.storage.signGetUrl(source.storageKey);
    return {
      url,
      quality: source.quality,
      bitrateKbps: source.bitrateKbps,
      fileSizeBytes: source.fileSizeBytes ? Number(source.fileSizeBytes) : null,
    };
  }

  // ---------------- 播放统计（防刷） ----------------

  /**
   * 防刷策略：
   *  1. Redis SETNX play:{userId}:{trackId}:{yyyyMMdd} EX 86400 —— 同一登录用户自然日内只计一次
   *  2. play_events 表函数唯一索引 uq_play_events_daily 兜底并发竞态（23505 冲突即视为重复）
   *  3. 成功后 tracks.play_count +1
   *  游客（userId 为空）：只记录事件，不计入 play_count
   */
  async recordPlay(
    userId: string | null,
    trackId: string,
    quality: string | null,
    ip: string | null,
    userAgent: string | null,
  ): Promise<{ counted: boolean; reason: string }> {
    const track = await this.tracksRepo.findOne({
      where: { id: trackId, status: TRACK_STATUS_ONLINE },
      select: ['id'],
    });
    if (!track) {
      throw new NotFoundException('歌曲不存在或已下线');
    }

    if (!userId) {
      await this.playEventsRepo.insert({
        userId: null,
        trackId,
        quality,
        ip,
        userAgent,
      });
      return { counted: false, reason: 'guest_not_counted' };
    }

    // UTC 自然日，保证多实例/多时区一致
    const day = new Date().toISOString().slice(0, 10);
    const key = PLAY_KEY(userId, trackId, day);
    const acquired = await this.redis.set(key, '1', 'EX', 86400, 'NX');
    if (acquired !== 'OK') {
      return { counted: false, reason: 'duplicate_today' };
    }

    try {
      await this.playEventsRepo.insert({
        userId,
        trackId,
        quality,
        ip,
        userAgent,
      });
    } catch (err) {
      // 并发竞态兜底：唯一索引冲突说明当日已计数
      if ((err as { code?: string })?.code === '23505') {
        return { counted: false, reason: 'duplicate_today' };
      }
      throw err;
    }

    await this.tracksRepo.increment({ id: trackId }, 'playCount', 1);
    return { counted: true, reason: 'counted' };
  }

  async assertTrackExists(trackId: string): Promise<void> {
    const exists = await this.tracksRepo.exist({
      where: { id: trackId, status: TRACK_STATUS_ONLINE },
    });
    if (!exists) {
      throw new BadRequestException('歌曲不存在或已下线');
    }
  }
}
