/**
 * 音频后台服务（headless JS 上下文）。
 *
 * 由 index.js 在顶层注册，与任何组件的生命周期无关。
 * 职责：接管 iOS 锁屏 / 控制中心 / 耳机线控 / 来电打断等系统级音频事件，
 * 保证 App 在后台、锁屏、被来电打断等场景下行为正确。
 */
import TrackPlayer, {Event} from 'react-native-track-player';

/**
 * 注意：必须使用 export default（供 index.js 以 require(...).default 引用），
 * 不要改成具名导出，否则顶层注册拿不到服务函数。
 */
export default async function PlaybackService(): Promise<void> {
  // 锁屏 / 控制中心 / 线控：播放
  TrackPlayer.addEventListener(Event.RemotePlay, () => {
    TrackPlayer.play().catch(e => console.warn('[PlaybackService] play 失败', e));
  });

  // 锁屏 / 控制中心 / 线控：暂停
  TrackPlayer.addEventListener(Event.RemotePause, () => {
    TrackPlayer.pause().catch(e =>
      console.warn('[PlaybackService] pause 失败', e),
    );
  });

  // 下一曲（线控、车机、控制中心）
  TrackPlayer.addEventListener(Event.RemoteNext, () => {
    TrackPlayer.skipToNext().catch(e =>
      console.warn('[PlaybackService] skipToNext 失败', e),
    );
  });

  // 上一曲（线控、车机、控制中心）
  TrackPlayer.addEventListener(Event.RemotePrevious, () => {
    TrackPlayer.skipToPrevious().catch(e =>
      console.warn('[PlaybackService] skipToPrevious 失败', e),
    );
  });

  // 远程进度跳转（锁屏进度条拖动）
  TrackPlayer.addEventListener(Event.RemoteSeek, event => {
    if (typeof event.position === 'number' && event.position >= 0) {
      TrackPlayer.seekTo(event.position).catch(e =>
        console.warn('[PlaybackService] seekTo 失败', e),
      );
    }
  });

  /**
   * 音频打断（Audio Ducking）：
   * - permanent=true（导航语音等长期占用）：直接暂停播放
   * - transient（通知音等短暂打断）：压低音量到 0.2，打断结束恢复 1.0
   * 说明：iOS 来电打断由系统自动挂起 AVAudioSession，通话结束后
   * 会收到 paused=false 的 RemoteDuck，本处恢复音量即可；
   * 若系统未自动恢复，用户可通过控制中心手动继续。
   */
  TrackPlayer.addEventListener(Event.RemoteDuck, event => {
    if (event.permanent) {
      TrackPlayer.pause().catch(e =>
        console.warn('[PlaybackService] duck-pause 失败', e),
      );
    } else {
      TrackPlayer.setVolume(event.paused ? 0.2 : 1.0).catch(e =>
        console.warn('[PlaybackService] setVolume 失败', e),
      );
    }
  });

  // 播放链路错误：只打日志不上报崩溃；UI 层如需切歌/提示可另行监听此事件
  TrackPlayer.addEventListener(Event.PlaybackError, event => {
    console.error(
      `[PlaybackService] 播放错误 code=${event.code} message=${event.message}`,
    );
  });
}
