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
  ) {}

  // ---------------- 分页音乐流 ----------------

  async feed(page: number, pageSize: number): Promise<PageResult<Track>> {
    const [list, total] = await this.tracksRepo.findAndCount({
      where: { status: TRACK_STATUS_ONLINE },
      order: { playCount: 'DESC', id: 'ASC' },
      skip: (page - 1) * pageSize,
      take: pageSize,
    });
    return { list, total, page, pageSize };
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
    return { list, total, page, pageSize };
  }

  // ---------------- 歌曲详情 / 歌词 ----------------

  async getTrack(id: string) {
    const track = await this.tracksRepo.findOne({
      where: { id, status: TRACK_STATUS_ONLINE },
      relations: ['sources'],
    });
    if (!track) {
      throw new NotFoundException('歌曲不存在或已下线');
    }
    return track;
  }

  async getLyrics(id: string) {
    const track = await this.tracksRepo.findOne({
      where: { id, status: TRACK_STATUS_ONLINE },
      select: ['id', 'lrcText', 'lrcSynced'],
    });
    if (!track) {
      throw new NotFoundException('歌曲不存在或已下线');
    }
    return { lrcText: track.lrcText, lrcSynced: track.lrcSynced };
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
