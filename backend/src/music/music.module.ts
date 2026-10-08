import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { PlayEvent } from '../entities/play-event.entity';
import { Track } from '../entities/track.entity';
import { TrackSource } from '../entities/track-source.entity';
import { MusicController } from './music.controller';
import { MusicService } from './music.service';

@Module({
  imports: [TypeOrmModule.forFeature([Track, TrackSource, PlayEvent])],
  controllers: [MusicController],
  providers: [MusicService],
  exports: [MusicService],
})
export class MusicModule {}
