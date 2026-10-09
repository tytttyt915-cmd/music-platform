import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Playlist } from '../entities/playlist.entity';
import { PlaylistTrack } from '../entities/playlist-track.entity';
import { Track } from '../entities/track.entity';
import { MusicModule } from '../music/music.module';
import { PlaylistController } from './playlist.controller';
import { PlaylistService } from './playlist.service';
import { PlaylistImportService } from './playlist-import.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([Playlist, PlaylistTrack, Track]),
    MusicModule,
  ],
  controllers: [PlaylistController],
  providers: [PlaylistService, PlaylistImportService],
})
export class PlaylistModule {}
