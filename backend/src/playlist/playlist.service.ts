import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Playlist } from '../entities/playlist.entity';
import { PlaylistTrack } from '../entities/playlist-track.entity';
import { MusicService } from '../music/music.service';
import { CreatePlaylistDto } from './dto/create-playlist.dto';

@Injectable()
export class PlaylistService {
  constructor(
    @InjectRepository(Playlist)
    private readonly playlistsRepo: Repository<Playlist>,
    @InjectRepository(PlaylistTrack)
    private readonly playlistTracksRepo: Repository<PlaylistTrack>,
    private readonly musicService: MusicService,
  ) {}

  async create(ownerId: string, dto: CreatePlaylistDto): Promise<Playlist> {
    const playlist = this.playlistsRepo.create({
      ownerId,
      title: dto.title,
      coverUrl: dto.coverUrl ?? null,
      isPublic: dto.isPublic ?? true,
    });
    return this.playlistsRepo.save(playlist);
  }

  private async findPlaylistOrThrow(id: string): Promise<Playlist> {
    const playlist = await this.playlistsRepo.findOne({ where: { id } });
    if (!playlist) {
      throw new NotFoundException('歌单不存在');
    }
    return playlist;
  }

  private assertVisible(playlist: Playlist, userId: string): void {
    if (!playlist.isPublic && playlist.ownerId !== userId) {
      throw new ForbiddenException('无权查看该歌单');
    }
  }

  private assertOwner(playlist: Playlist, userId: string): void {
    if (playlist.ownerId !== userId) {
      throw new ForbiddenException('只有歌单所有者可以修改');
    }
  }

  async getById(id: string, userId: string) {
    const playlist = await this.findPlaylistOrThrow(id);
    this.assertVisible(playlist, userId);
    const items = await this.playlistTracksRepo.find({
      where: { playlistId: id },
      relations: ['track'],
      order: { position: 'ASC', addedAt: 'ASC' },
    });
    return {
      ...playlist,
      tracks: items.map((item) => ({
        ...item.track,
        position: item.position,
        addedAt: item.addedAt,
      })),
    };
  }

  async addTrack(playlistId: string, userId: string, trackId: string) {
    const playlist = await this.findPlaylistOrThrow(playlistId);
    this.assertOwner(playlist, userId);
    await this.musicService.assertTrackExists(trackId);

    const exists = await this.playlistTracksRepo.exist({
      where: { playlistId, trackId },
    });
    if (exists) {
      throw new BadRequestException('歌曲已在歌单中');
    }

    const maxPos = await this.playlistTracksRepo
      .createQueryBuilder('pt')
      .select('COALESCE(MAX(pt.position), -1)', 'maxPos')
      .where('pt.playlistId = :playlistId', { playlistId })
      .getRawOne<{ maxPos: string }>();

    const entry = this.playlistTracksRepo.create({
      playlistId,
      trackId,
      position: Number(maxPos?.maxPos ?? -1) + 1,
    });
    await this.playlistTracksRepo.save(entry);
    return { position: entry.position };
  }
}
