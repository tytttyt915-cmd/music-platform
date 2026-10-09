import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  Req,
  Res,
} from '@nestjs/common';
import { Request, Response } from 'express';
import { Public } from '../common/decorators/public.decorator';
import {
  AuthUser,
  CurrentUser,
} from '../common/decorators/current-user.decorator';
import { FeedQueryDto, SearchQueryDto } from './dto/music-query.dto';
import { StreamQueryDto } from './dto/stream-query.dto';
import { MusicService } from './music.service';

@Controller('music')
export class MusicController {
  constructor(private readonly musicService: MusicService) {}

  @Public()
  @Get('feed')
  feed(@Query() query: FeedQueryDto) {
    return this.musicService.feed(query.page, query.pageSize, query.sort);
  }

  @Public()
  @Get('search')
  search(@Query() query: SearchQueryDto) {
    return this.musicService.search(query.q.trim(), query.page, query.pageSize);
  }

  @Public()
  @Get('track/:id')
  track(@Param('id', new ParseUUIDPipe({ version: '4' })) id: string) {
    return this.musicService.getTrack(id);
  }

  @Public()
  @Get('track/:id/lyrics')
  lyrics(@Param('id', new ParseUUIDPipe({ version: '4' })) id: string) {
    return this.musicService.getLyrics(id);
  }

  /** 单首歌未来 7 天热度预测（TimesFM；不可用时降级）。 */
  @Public()
  @Get('track/:id/predict')
  predict(@Param('id', new ParseUUIDPipe({ version: '4' })) id: string) {
    return this.musicService.predictTrack(id);
  }

  /**
   * 流媒体入口：查多码率元数据 → 生成预签名 URL → 302 重定向。
   * 实际音频字节由对象存储（经 Nginx/CDN）直接下发，支持 Range 206。
   */
  @Public()
  @Get('track/:id/stream')
  async stream(
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @Query() query: StreamQueryDto,
    @Res() res: Response,
  ) {
    const { url } = await this.musicService.getStreamRedirect(
      id,
      query.quality,
    );
    res.redirect(302, url);
  }

  /** 播放统计（防刷）：登录用户自然日去重计数；游客仅记录事件 */
  @Post('track/:id/play')
  @HttpCode(200)
  play(
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @CurrentUser() user: AuthUser,
    @Req() req: Request,
    @Body() body: { quality?: string },
  ) {
    const userId = user.isGuest ? null : user.id;
    const ip =
      (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() ||
      req.ip ||
      null;
    const userAgent = (req.headers['user-agent'] as string) || null;
    return this.musicService.recordPlay(
      userId,
      id,
      typeof body?.quality === 'string' ? body.quality : null,
      ip,
      userAgent,
    );
  }
}
