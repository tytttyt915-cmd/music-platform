import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import helmet from 'helmet';
import { AppModule } from './app.module';

async function bootstrap() {
  const logger = new Logger('Bootstrap');
  const app = await NestFactory.create(AppModule, {
    logger: ['log', 'error', 'warn'],
  });

  // 安全头
  app.use(helmet());

  // CORS：Web 端播放器需要读取流媒体响应头（Range 断点续传）
  app.enableCors({
    origin: true,
    credentials: true,
    exposedHeaders: [
      'Content-Range',
      'Accept-Ranges',
      'Content-Length',
      'ETag',
      'Content-Type',
    ],
  });

  // 优雅关闭：关闭 HTTP 连接、TypeORM 连接池、Redis 客户端
  app.enableShutdownHooks();

  const port = Number(process.env.PORT ?? 3000);
  await app.listen(port, '0.0.0.0');
  logger.log(`music-platform backend listening on :${port}`);
}

bootstrap().catch((err) => {
  // eslint-disable-next-line no-console
  console.error('Bootstrap failed:', err);
  process.exit(1);
});
