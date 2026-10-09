import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Post,
  Put,
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
   * 手动换源：可用源列表（本地码率 + 各平台最佳匹配）。
   * lx-music 手动换源的服务端版。
   */
  @Public()
  @Get('track/:id/sources')
  sources(@Param('id', new ParseUUIDPipe({ version: '4' })) id: string) {
    return this.musicService.getAvailableSources(id);
  }

  /**
   * 手动换源：锁定首选源。source: auto | local | netease | qq | kugou。
   * 锁定后播放走该源，失效自动降级本地（不断播）。
   */
  @Public()
  @Put('track/:id/preferred-source')
  @HttpCode(200)
  setPreferredSource(
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @Body() body: { source?: string },
  ) {
    return this.musicService.setPreferredSource(id, body?.source ?? 'auto');
  }

  /**
   * 电台：tag 为空返回热门电台。?tag=jazz&limit=30。
   */
  @Public()
  @Get('radio')
  radio(@Query('tag') tag?: string, @Query('limit') limit?: string) {
    const n = limit ? parseInt(limit, 10) : 30;
    return this.musicService.getRadioStations(tag, Number.isNaN(n) ? 30 : n);
  }

  /**
   * 波形：100 点 0~1，用于前端波形进度条。
   * 服务端 ffmpeg 预计算（namida 端侧解码的零耗电版），无缓存时实时算。
   */
  @Public()
  @Get('track/:id/waveform')
  waveform(@Param('id', new ParseUUIDPipe({ version: '4' })) id: string) {
    return this.musicService.getWaveform(id);
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

  /**
   * 国内平台歌曲播放：302 重定向到平台真实直链。
   * 前端从搜索结果取 platform + platformId 调用。
   * 不代理流量，省服务器带宽。
   */
  @Public()
  @Get('platform/:platform/stream')
  async platformStream(
    @Param('platform') platform: string,
    @Query('id') platformId: string,
    @Query('quality') quality: string,
    @Res() res: Response,
  ) {
    if (!['netease', 'qq', 'kugou'].includes(platform)) {
      res.status(400).json({ code: 400, message: '不支持的平台' });
      return;
    }
    if (!platformId) {
      res.status(400).json({ code: 400, message: '缺少歌曲 ID' });
      return;
    }
    const q =
      quality === 'lossless' || quality === 'standard' ? quality : 'high';
    const url = await this.musicService.getPlatformPlayUrl(
      platform as 'netease' | 'qq' | 'kugou',
      platformId,
      q as 'standard' | 'high' | 'lossless',
    );
    if (!url) {
      res.status(404).json({ code: 404, message: '无可用播放链接（可能需 VIP）' });
      return;
    }
    res.redirect(302, url);
  }

  /**
   * 国内平台歌曲歌词。
   */
  @Public()
  @Get('platform/:platform/lyrics')
  async platformLyrics(
    @Param('platform') platform: string,
    @Query('id') platformId: string,
  ) {
    if (!['netease', 'qq', 'kugou'].includes(platform) || !platformId) {
      return { code: 400, message: '参数错误' };
    }
    const lyric = await this.musicService.getPlatformLyric(
      platform as 'netease' | 'qq' | 'kugou',
      platformId,
    );
    return { code: 0, message: 'ok', data: { lyric, platform } };
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
