import { Injectable, Logger, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { execFile } from 'child_process';
import { promisify } from 'util';
import { join } from 'path';
import { Playlist } from '../entities/playlist.entity';
import { PlaylistTrack } from '../entities/playlist-track.entity';
import { Track, TRACK_STATUS_ONLINE } from '../entities/track.entity';
import { MusicService } from '../music/music.service';

const execFileAsync = promisify(execFile);

interface ImportedSong {
  platform: string;
  platform_id: string;
  title: string;
  artist: string;
}

interface ImportResult {
  playlistId: string;
  playlistName: string;
  total: number;
  matched: number;
  unmatched: { title: string; artist: string }[];
}

/**
 * 歌单导入（杀手级拉新功能）：粘贴网易云/QQ 音乐歌单链接，一键"搬家"。
 *
 * 流程：
 *   1. 调 Python 爬虫（Scrapling）抓歌单元数据 → JSON
 *   2. 建本地歌单
 *   3. 逐首在本地库搜索匹配（标题+歌手），命中的加入歌单
 *   4. 未命中的返回列表（用户可手动搜）
 *
 * 只爬公开元数据，不碰音频。竞品（lx-music/Beans-Music）都没有跨平台搬家。
 */
@Injectable()
export class PlaylistImportService {
  private readonly logger = new Logger(PlaylistImportService.name);

  constructor(
    @InjectRepository(Playlist)
    private readonly playlistsRepo: Repository<Playlist>,
    @InjectRepository(PlaylistTrack)
    private readonly playlistTracksRepo: Repository<PlaylistTrack>,
    @InjectRepository(Track)
    private readonly tracksRepo: Repository<Track>,
    private readonly musicService: MusicService,
  ) {}

  async importFromUrl(
    ownerId: string,
    url: string,
  ): Promise<ImportResult> {
    const trimmed = (url || '').trim();
    if (
      !trimmed.includes('music.163.com') &&
      !trimmed.includes('y.qq.com')
    ) {
      throw new BadRequestException('仅支持网易云 (music.163.com) / QQ 音乐 (y.qq.com) 歌单链接');
    }

    // 1. 爬虫抓取
    const songs = await this.crawlPlaylist(trimmed);
    if (songs.songs.length === 0) {
      throw new BadRequestException('歌单为空或抓取失败');
    }

    // 2. 建歌单
    const playlist = await this.playlistsRepo.save(
      this.playlistsRepo.create({
        ownerId,
        title: songs.name,
        isPublic: false,
      }),
    );

    // 3. 逐首匹配本地库
    const unmatched: { title: string; artist: string }[] = [];
    let matched = 0;
    let position = 0;
    for (const song of songs.songs) {
      const trackId = await this.matchLocalTrack(song.title, song.artist);
      if (trackId) {
        try {
          await this.playlistTracksRepo.save(
            this.playlistTracksRepo.create({
              playlistId: playlist.id,
              trackId,
              position: position++,
            }),
          );
          matched++;
        } catch {
          /* 重复添加跳过 */
        }
      } else {
        unmatched.push({ title: song.title, artist: song.artist });
      }
    }

    return {
      playlistId: playlist.id,
      playlistName: songs.name,
      total: songs.songs.length,
      matched,
      unmatched: unmatched.slice(0, 50),
    };
  }

  /**
   * 调 Python 爬虫。脚本在 backend/scripts/playlist-import.py。
   */
  private async crawlPlaylist(
    url: string,
  ): Promise<{ name: string; songs: ImportedSong[] }> {
    const script = join(__dirname, '..', '..', 'scripts', 'playlist-import.py');
    try {
      const { stdout } = await execFileAsync(
        'python3',
        [script, url],
        { timeout: 60000, maxBuffer: 16 * 1024 * 1024 },
      );
      // 脚本输出 "OK: N 首 → playlist_xxx.json"，JSON 写在同目录
      const m = stdout.match(/→\s*(\S+\.json)/);
      if (!m) {
        throw new Error('爬虫输出解析失败');
      }
      const jsonPath = join(join(__dirname, '..', '..', 'scripts'), m[1]);
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const data = require(jsonPath) as {
        name: string;
        songs: ImportedSong[];
      };
      return { name: data.name, songs: data.songs || [] };
    } catch (err) {
      this.logger.warn(
        `歌单爬虫失败: ${err instanceof Error ? err.message : String(err)}`,
      );
      throw new BadRequestException('歌单抓取失败（链接无效或被反爬）');
    }
  }

  /**
   * 本地库匹配：标题归一化精确匹配优先，否则模糊搜第一首。
   */
  private async matchLocalTrack(
    title: string,
    artist: string,
  ): Promise<string | null> {
    const t = title.trim();
    if (!t) return null;
    // 精确匹配（标题+歌手）
    const exact = await this.tracksRepo
      .createQueryBuilder('track')
      .where('track.status = :status', { status: TRACK_STATUS_ONLINE })
      .andWhere('LOWER(track.title) = LOWER(:title)', { title: t })
      .andWhere('LOWER(track.artist) LIKE LOWER(:artist)', {
        artist: `%${artist.trim()}%`,
      })
      .select('track.id')
      .getOne();
    if (exact) return exact.id;
    // 模糊：用现有搜索接口取第一首
    try {
      const result = await this.musicService.search(`${t} ${artist}`.trim(), 1, 5);
      const items = (result as unknown as { list?: { id: string }[] }).list;
      if (Array.isArray(items) && items.length > 0) return items[0].id;
    } catch {
      /* 搜索失败 */
    }
    return null;
  }
}
