import { Controller, Get, Inject, Logger } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { Redis } from 'ioredis';
import { REDIS_CLIENT } from '../redis/redis.module';
import { Public } from '../common/decorators/public.decorator';

@Controller('health')
export class HealthController {
  private readonly logger = new Logger(HealthController.name);

  constructor(
    private readonly dataSource: DataSource,
    @Inject(REDIS_CLIENT) private readonly redis: Redis,
  ) {}

  @Public()
  @Get()
  async check() {
    const checks: Record<string, boolean> = { db: false, redis: false };

    try {
      await this.dataSource.query('SELECT 1');
      checks.db = true;
    } catch (err) {
      this.logger.error(`DB 健康检查失败: ${String(err)}`);
    }

    try {
      const pong = await this.redis.ping();
      checks.redis = pong === 'PONG';
    } catch (err) {
      this.logger.error(`Redis 健康检查失败: ${String(err)}`);
    }

    return {
      status: checks.db && checks.redis ? 'ok' : 'degraded',
      checks,
      time: new Date().toISOString(),
    };
  }
}
