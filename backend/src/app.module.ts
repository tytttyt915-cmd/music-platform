import { MiddlewareConsumer, Module, NestModule } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR, APP_PIPE } from '@nestjs/core';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ValidationPipe } from '@nestjs/common';
import configuration from './config/configuration';
import { AllExceptionsFilter } from './common/filters/all-exceptions.filter';
import { ResponseInterceptor } from './common/interceptors/response.interceptor';
import { RequestLoggerMiddleware } from './common/middleware/request-logger.middleware';
import { JwtAuthGuard } from './auth/guards/jwt-auth.guard';
import { RedisModule } from './redis/redis.module';
import { StorageModule } from './storage/storage.module';
import { HealthModule } from './health/health.module';
import { AuthModule } from './auth/auth.module';
import { AccountModule } from './account/account.module';
import { MusicModule } from './music/music.module';
import { PlaylistModule } from './playlist/playlist.module';
import { PredictionModule } from './prediction/prediction.module';
import { User } from './entities/user.entity';
import { Track } from './entities/track.entity';
import { TrackSource } from './entities/track-source.entity';
import { Playlist } from './entities/playlist.entity';
import { PlaylistTrack } from './entities/playlist-track.entity';
import { PlayEvent } from './entities/play-event.entity';
import { RefreshToken } from './entities/refresh-token.entity';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      load: [configuration],
      // .env 仅用于本地开发；Docker/K8s 场景以环境变量注入为准
      envFilePath: ['.env', '.env.local'],
    }),
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        type: 'postgres',
        host: config.get<string>('database.host'),
        port: config.get<number>('database.port'),
        username: config.get<string>('database.username'),
        password: config.get<string>('database.password'),
        database: config.get<string>('database.database'),
        entities: [
          User,
          Track,
          TrackSource,
          Playlist,
          PlaylistTrack,
          PlayEvent,
          RefreshToken,
        ],
        // 表结构以 db/init.sql 为准，运行时绝不同步 schema
        synchronize: false,
        logging: config.get<string>('nodeEnv') === 'development' ? ['error'] : false,
      }),
    }),
    RedisModule,
    StorageModule,
    HealthModule,
    AuthModule,
    AccountModule,
    PredictionModule,
    MusicModule,
    PlaylistModule,
  ],
  providers: [
    {
      provide: APP_PIPE,
      useFactory: () =>
        new ValidationPipe({
          whitelist: true,
          transform: true,
          transformOptions: { enableImplicitConversion: true },
          forbidNonWhitelisted: false,
        }),
    },
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_INTERCEPTOR, useClass: ResponseInterceptor },
    { provide: APP_FILTER, useClass: AllExceptionsFilter },
  ],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(RequestLoggerMiddleware).forRoutes('*');
  }
}
