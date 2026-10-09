import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Post,
} from '@nestjs/common';
import {
  AuthUser,
  CurrentUser,
} from '../common/decorators/current-user.decorator';
import { AddTrackDto } from './dto/add-track.dto';
import { CreatePlaylistDto } from './dto/create-playlist.dto';
import { PlaylistService } from './playlist.service';
import { PlaylistImportService } from './playlist-import.service';

@Controller('playlists')
export class PlaylistController {
  constructor(
    private readonly playlistService: PlaylistService,
    private readonly importService: PlaylistImportService,
  ) {}

  @Post()
  @HttpCode(201)
  create(@CurrentUser() user: AuthUser, @Body() dto: CreatePlaylistDto) {
    return this.playlistService.create(user.id, dto);
  }

  /**
   * 歌单导入：粘贴网易云/QQ 音乐歌单链接，一键搬家。
   * 杀手级拉新功能，竞品没有跨平台搬家。
   */
  @Post('import')
  @HttpCode(201)
  importFromUrl(
    @CurrentUser() user: AuthUser,
    @Body() body: { url?: string },
  ) {
    return this.importService.importFromUrl(user.id, body?.url ?? '');
  }

  @Get(':id')
  getOne(
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @CurrentUser() user: AuthUser,
  ) {
    return this.playlistService.getById(id, user.id);
  }

  @Post(':id/tracks')
  @HttpCode(201)
  addTrack(
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @CurrentUser() user: AuthUser,
    @Body() dto: AddTrackDto,
  ) {
    return this.playlistService.addTrack(id, user.id, dto.trackId);
  }
}
