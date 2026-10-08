import { Global, Logger, Module, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

export const REDIS_CLIENT = 'REDIS_CLIENT';

@Global()
@Module({
  providers: [
    {
      provide: REDIS_CLIENT,
      inject: [ConfigService],
      useFactory: (config: ConfigService) => {
        const url = config.getOrThrow<string>('redis.url');
        const logger = new Logger('RedisModule');
        const client = new Redis(url, {
          maxRetriesPerRequest: 3,
          enableReadyCheck: true,
          retryStrategy: (times) => Math.min(times * 200, 3000),
        });
        client.on('error', (err) =>
          logger.error(`Redis error: ${err.message}`),
        );
        client.on('connect', () => logger.log('Redis connected'));
        return client;
      },
    },
  ],
  exports: [REDIS_CLIENT],
})
export class RedisModule implements OnModuleDestroy {
  constructor() {}
  async onModuleDestroy() {
    // 客户端由 provider 创建；此处不主动 quit，由进程退出统一关闭
  }
}
