import { Inject, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Redis } from 'ioredis';
import { Repository } from 'typeorm';
import { PlayEvent } from '../entities/play-event.entity';
import { REDIS_CLIENT } from '../redis/redis.module';

export interface TrackPrediction {
  trackId: string;
  /** 未来 7 天预测播放量（forecast 求和，四舍五入） */
  predicted7d: number;
  /** 逐日预测值 */
  forecast: number[];
  /** 参与预测的历史天数 */
  historyDays: number;
  /** 是否走了降级（TimesFM 不可用） */
  fallback: boolean;
  /** 预测耗时 ms（TimesFM 实测） */
  inferenceMs: number | null;
}

interface TimesFmResponse {
  forecast: number[];
  quantiles?: Record<string, number[]>;
  interval_80?: { lower: number[]; upper: number[] };
  inference_ms?: number;
}

const HISTORY_DAYS = 30;
const HORIZON = 7;
const MIN_HISTORY_POINTS = 7;
const CACHE_KEY_PREFIX = 'pred:v1:';

@Injectable()
export class PredictionService {
  private readonly logger = new Logger(PredictionService.name);
  private readonly enabled: boolean;
  private readonly timesfmUrl: string;
  private readonly cacheTtlSec: number;
  private readonly candidateLimit: number;
  private readonly requestTimeoutMs: number;

  constructor(
    private readonly config: ConfigService,
    @InjectRepository(PlayEvent)
    private readonly playEventsRepo: Repository<PlayEvent>,
    @Inject(REDIS_CLIENT) private readonly redis: Redis,
  ) {
    this.enabled =
      (this.config.get<string>('prediction.enabled') ?? 'true').toLowerCase() ===
      'true';
    this.timesfmUrl =
      this.config.get<string>('prediction.timesfmUrl') ??
      'http://127.0.0.1:8100';
    this.cacheTtlSec = parseInt(
      this.config.get<string>('prediction.cacheTtlSec') ?? '3600',
      10,
    );
    this.candidateLimit = parseInt(
      this.config.get<string>('prediction.candidateLimit') ?? '300',
      10,
    );
    this.requestTimeoutMs = parseInt(
      this.config.get<string>('prediction.requestTimeoutMs') ?? '15000',
      10,
    );
  }

  get isEnabled(): boolean {
    return this.enabled;
  }

  get maxCandidates(): number {
    return this.candidateLimit;
  }

  /**
   * 取某歌曲最近 N 天的日播放量（按天聚合，缺失补 0）。
   * 返回从旧到新的数组，长度固定为 days。
   */
  async getDailyHistory(
    trackId: string,
    days: number = HISTORY_DAYS,
  ): Promise<number[]> {
    const rows: Array<{ day: string; cnt: string }> =
      await this.playEventsRepo.query(
        `
        SELECT to_char(date_trunc('day', created_at), 'YYYY-MM-DD') AS day,
               COUNT(*) AS cnt
        FROM play_events
        WHERE track_id = $1
          AND created_at >= NOW() - ($2 || ' days')::interval
        GROUP BY 1
        ORDER BY 1
        `,
        [trackId, String(days)],
      );
    const byDay = new Map<string, number>();
    for (const r of rows) {
      byDay.set(r.day, parseInt(r.cnt, 10) || 0);
    }
    const out: number[] = [];
    const today = new Date();
    for (let i = days - 1; i >= 0; i--) {
      const d = new Date(today);
      d.setUTCDate(d.getUTCDate() - i);
      const key = d.toISOString().slice(0, 10);
      out.push(byDay.get(key) ?? 0);
    }
    return out;
  }

  /** 调 TimesFM /predict，失败返回 null（调用方降级）。 */
  private async callTimesFm(
    history: number[],
    horizon: number = HORIZON,
  ): Promise<TimesFmResponse | null> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.requestTimeoutMs);
    try {
      const res = await fetch(`${this.timesfmUrl}/predict`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ history, horizon }),
        signal: controller.signal,
      });
      if (!res.ok) {
        this.logger.warn(
          `TimesFM /predict 返回 ${res.status}，走降级`,
        );
        return null;
      }
      const data = (await res.json()) as TimesFmResponse;
      if (!Array.isArray(data.forecast) || data.forecast.length === 0) {
        this.logger.warn('TimesFM 返回 forecast 非法，走降级');
        return null;
      }
      return data;
    } catch (err) {
      const reason =
        err instanceof Error && err.name === 'AbortError'
          ? `超时(${this.requestTimeoutMs}ms)`
          : err instanceof Error
            ? err.message
            : String(err);
      this.logger.warn(`TimesFM 调用失败(${reason})，走降级`);
      return null;
    } finally {
      clearTimeout(timer);
    }
  }

  /**
   * 预测单首歌未来 7 天热度。
   * 成功走 TimesFM；历史不足/服务不可用返回 fallback 结果（predicted7d=null 由调用方用 playCount）。
   */
  async predictTrack(trackId: string): Promise<TrackPrediction | null> {
    if (!this.enabled) return null;
    const cacheKey = `${CACHE_KEY_PREFIX}${trackId}`;
    try {
      const cached = await this.redis.get(cacheKey);
      if (cached) {
        return JSON.parse(cached) as TrackPrediction;
      }
    } catch (err) {
      this.logger.warn(
        `读预测缓存失败: ${err instanceof Error ? err.message : String(err)}`,
      );
    }

    const history = await this.getDailyHistory(trackId);
    const total = history.reduce((a, b) => a + b, 0);
    if (total <= 0) {
      // 从未被播放过：无意义预测，直接降级
      return null;
    }
    // TimesFM 要求至少 7 个点；不足时前置补 0
    const padded =
      history.length >= MIN_HISTORY_POINTS
        ? history.slice(-32) // 模型 max_context=32
        : [...new Array(MIN_HISTORY_POINTS - history.length).fill(0), ...history];

    const resp = await this.callTimesFm(padded, HORIZON);
    if (!resp) return null;

    const forecast = resp.forecast.map((v) =>
      Math.max(0, Math.round(v * 100) / 100),
    );
    const predicted7d = Math.round(forecast.reduce((a, b) => a + b, 0));
    const result: TrackPrediction = {
      trackId,
      predicted7d,
      forecast,
      historyDays: history.length,
      fallback: false,
      inferenceMs:
        typeof resp.inference_ms === 'number'
          ? Math.round(resp.inference_ms * 10) / 10
          : null,
    };
    try {
      await this.redis.set(
        cacheKey,
        JSON.stringify(result),
        'EX',
        this.cacheTtlSec,
      );
    } catch (err) {
      this.logger.warn(
        `写预测缓存失败: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
    return result;
  }

  /**
   * 批量预测（并发受限）。返回 trackId -> TrackPrediction|null 的映射。
   */
  async predictBatch(
    trackIds: string[],
    concurrency = 4,
  ): Promise<Map<string, TrackPrediction | null>> {
    const result = new Map<string, TrackPrediction | null>();
    const queue = [...trackIds];
    const workers = new Array(Math.min(concurrency, queue.length))
      .fill(0)
      .map(async () => {
        while (queue.length > 0) {
          const id = queue.shift()!;
          try {
            result.set(id, await this.predictTrack(id));
          } catch (err) {
            this.logger.warn(
              `预测 ${id} 异常: ${err instanceof Error ? err.message : String(err)}`,
            );
            result.set(id, null);
          }
        }
      });
    await Promise.all(workers);
    return result;
  }

  /** 清掉某首歌的预测缓存（播放量大涨后可手动刷新）。 */
  async invalidate(trackId: string): Promise<void> {
    try {
      await this.redis.del(`${CACHE_KEY_PREFIX}${trackId}`);
    } catch (err) {
      this.logger.warn(
        `清预测缓存失败: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
  }
}
