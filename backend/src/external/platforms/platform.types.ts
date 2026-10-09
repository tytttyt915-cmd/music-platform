/**
 * 国内音乐平台统一数据模型。
 *
 * 设计原则：
 * - 所有平台 service 实现同一接口，便于聚合和扩展
 * - 失败一律返回 null，绝不抛错（由调用方决定降级策略）
 * - 平台曲目带 platform 标记，前端不得与本地曲目混淆
 */

export type MusicPlatform = 'netease' | 'qq' | 'kugou';

export type AudioQuality = 'standard' | 'high' | 'lossless';

/** 平台侧曲目（搜索/推荐结果） */
export interface PlatformTrack {
  platform: MusicPlatform;
  /** 平台侧歌曲 ID（网易云为数字 id，QQ 为 songmid，酷狗为 hash） */
  platformId: string;
  title: string;
  artist: string;
  album: string | null;
  coverUrl: string | null;
  durationMs: number | null;
  /** 标记为第三方结果：本地无可播音频，需走平台播放链路 */
  external: true;
}

/** 平台 service 统一接口 */
export interface IPlatformService {
  readonly platform: MusicPlatform;
  readonly isEnabled: boolean;

  /**
   * 搜索平台曲库。失败返回 null。
   */
  search(keyword: string, limit?: number): Promise<PlatformTrack[] | null>;

  /**
   * 获取可播放直链。失败返回 null。
   * @param platformId 平台侧歌曲 ID
   * @param quality 期望音质，平台不支持时自动降级
   */
  getPlayUrl(
    platformId: string,
    quality?: AudioQuality,
  ): Promise<string | null>;

  /**
   * 获取歌词（LRC 格式优先）。失败返回 null。
   */
  getLyric(platformId: string): Promise<string | null>;
}
