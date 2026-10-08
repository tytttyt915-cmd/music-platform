/**
 * 播放器单例封装：所有 UI 只通过这里操作 TrackPlayer。
 * 保证：setup 只执行一次（并发安全）、队列操作符合“点哪首播哪首”语义、
 * 播放统计上报失败不阻塞播放、音质切换不断流（保持进度与播放状态）。
 */
import TrackPlayer, {Capability, State} from 'react-native-track-player';
import {AudioQuality, TrackInfo, getStreamUrl, reportPlay} from '../api/client';

/** UI 层播放一首歌所需的最简信息 */
export interface PlayableTrack {
  id: string;
  title: string;
  artist?: string;
  artwork?: string;
  /** 时长（秒），供锁屏/控制中心展示 */
  duration?: number;
}

/** 后端 TrackInfo → 播放器可用结构 */
export function toPlayable(t: TrackInfo): PlayableTrack {
  return {
    id: t.id,
    title: t.title,
    artist: t.artist || '未知艺人',
    artwork: t.coverUrl || undefined,
    duration: t.durationMs > 0 ? Math.round(t.durationMs / 1000) : undefined,
  };
}

let setupDone = false;
let setupPromise: Promise<void> | null = null;

/**
 * 初始化播放器（幂等）：并发调用复用同一个 Promise，避免重复 setup；
 * setup 失败时重置 Promise，允许下次重试。
 */
export function setupPlayer(): Promise<void> {
  if (setupDone) {
    return Promise.resolve();
  }
  if (!setupPromise) {
    setupPromise = (async () => {
      try {
        await TrackPlayer.setupPlayer();
      } catch (e) {
        // 播放器已初始化时 v4 会抛错，视为成功以保证幂等
        console.warn('[player] setupPlayer 返回异常，按已初始化继续', e);
      }
      // iOS：声明锁屏/控制中心可用能力；后台音频常驻由
      // Info.plist 的 UIBackgroundModes=audio 保障
      await TrackPlayer.updateOptions({
        capabilities: [
          Capability.Play,
          Capability.Pause,
          Capability.SkipToNext,
          Capability.SkipToPrevious,
          Capability.SeekTo,
        ],
        // 锁屏/控制中心进度刷新间隔（秒）
        progressUpdateEventInterval: 1,
      });
      setupDone = true;
    })().catch(e => {
      setupPromise = null;
      throw e;
    });
  }
  return setupPromise;
}

/**
 * 播放指定歌曲：先清空队列再入队，保证“点哪首播哪首”，
 * 不会把上一首的残留队列带进来。
 */
export async function playTrack(
  track: PlayableTrack,
  quality: AudioQuality = 'high',
): Promise<void> {
  await setupPlayer();
  const url = await getStreamUrl(track.id, quality);
  await TrackPlayer.reset();
  await TrackPlayer.add({
    id: track.id,
    url,
    title: track.title,
    artist: track.artist ?? '未知艺人',
    artwork: track.artwork,
    duration: track.duration,
  });
  await TrackPlayer.play();
  // 播放统计上报：失败只打日志，不阻塞播放
  reportPlay(track.id, quality).catch(e =>
    console.warn('[player] 上报播放统计失败', e),
  );
}

/**
 * 切换音质：记录当前进度与播放状态，切源后恢复，
 * 做到不断流体验；失败时抛给调用方提示。
 */
export async function switchQuality(quality: AudioQuality): Promise<void> {
  const active = await TrackPlayer.getActiveTrack();
  if (!active || active.id == null) {
    return;
  }
  const trackId = String(active.id);
  const position = await TrackPlayer.getPosition().catch(() => 0);
  const playbackState = await TrackPlayer.getPlaybackState().catch(() => ({
    state: undefined as State | undefined,
  }));
  const url = await getStreamUrl(trackId, quality);
  await TrackPlayer.reset();
  await TrackPlayer.add({...active, url});
  if (position > 1) {
    await TrackPlayer.seekTo(position).catch(() => undefined);
  }
  if (playbackState.state === State.Playing) {
    await TrackPlayer.play().catch(() => undefined);
  }
  reportPlay(trackId, quality).catch(() => undefined);
}

/** 播放 / 暂停切换 */
export async function togglePlay(): Promise<void> {
  const {state} = await TrackPlayer.getPlaybackState();
  if (state === State.Playing) {
    await TrackPlayer.pause();
  } else {
    await TrackPlayer.play();
  }
}

export async function playNext(): Promise<void> {
  await TrackPlayer.skipToNext();
}

export async function playPrevious(): Promise<void> {
  await TrackPlayer.skipToPrevious();
}

/** 跳转到指定秒数（负数按 0 处理） */
export async function seekTo(seconds: number): Promise<void> {
  await TrackPlayer.seekTo(Math.max(0, seconds));
}
