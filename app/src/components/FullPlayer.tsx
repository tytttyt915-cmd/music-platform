/**
 * 全屏播放器（Modal）：
 * - 沉浸式黑胶唱片旋转动效：播放时 Animated.loop 无限旋转，暂停时停止
 * - useProgress 驱动 Slider 进度条，拖动松手后跳转
 * - 上一曲 / 播放暂停 / 下一曲
 * - 音质切换（标准 / 高清 / 无损）：重新取流并不断流切换（保持进度）
 * - 歌词页签：懒加载 LRC 并切换到 LyricsView
 */
import React, {useEffect, useMemo, useRef, useState} from 'react';
import {
  ActivityIndicator,
  Animated,
  Easing,
  Image,
  Modal,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import SliderRaw, {SliderProps} from '@react-native-community/slider';
// 注意：@react-native-community/slider 5.x 的类型声明把组件写成了
// 返回 ReactNode 的普通函数，在 @types/react 18 下不能直接作为 JSX 使用；
// 此处做一次类型适配（仅类型层，运行时无任何影响）。
const Slider = SliderRaw as unknown as React.ComponentType<SliderProps>;
import {
  State,
  useActiveTrack,
  usePlaybackState,
  useProgress,
} from 'react-native-track-player';
import {AudioQuality, getLyrics} from '../api/client';
import {
  playNext,
  playPrevious,
  seekTo,
  switchQuality,
  togglePlay,
} from '../audio/player';
import LyricsView from './LyricsView';

const QUALITIES: {key: AudioQuality; label: string}[] = [
  {key: 'standard', label: '标准'},
  {key: 'high', label: '高清'},
  {key: 'lossless', label: '无损'},
];

type Tab = 'vinyl' | 'lyrics';

interface Props {
  visible: boolean;
  onClose: () => void;
}

/** 秒 → mm:ss */
function fmt(sec: number): string {
  const s = Math.max(0, Math.floor(sec || 0));
  const m = Math.floor(s / 60);
  return `${m}:${String(s % 60).padStart(2, '0')}`;
}

export default function FullPlayer({visible, onClose}: Props) {
  const track = useActiveTrack();
  const playback = usePlaybackState();
  const {position, duration} = useProgress();
  const [tab, setTab] = useState<Tab>('vinyl');
  const [lrcText, setLrcText] = useState<string | null>(null);
  const [lyricsLoading, setLyricsLoading] = useState(false);
  const [switching, setSwitching] = useState(false);
  const [currentQuality, setCurrentQuality] = useState<AudioQuality>('high');

  const playing = playback.state === State.Playing;

  // 黑胶旋转：0→1 插值为 0→360deg；播放时启动无限循环，暂停时停止
  const spin = useRef(new Animated.Value(0)).current;
  const rotate = useMemo(
    () =>
      spin.interpolate({
        inputRange: [0, 1],
        outputRange: ['0deg', '360deg'],
      }),
    [spin],
  );
  useEffect(() => {
    const loop = Animated.loop(
      Animated.timing(spin, {
        toValue: 1,
        duration: 18000,
        easing: Easing.linear,
        useNativeDriver: true,
      }),
    );
    if (playing) {
      loop.start();
    } else {
      loop.stop();
    }
    return () => loop.stop();
  }, [playing, spin]);

  // 切到歌词页签时懒加载歌词；组件卸载/切歌时取消，避免 setState 到已卸载组件
  useEffect(() => {
    if (tab !== 'lyrics' || !track?.id) {
      return;
    }
    let cancelled = false;
    setLyricsLoading(true);
    getLyrics(String(track.id))
      .then(r => {
        if (!cancelled) {
          setLrcText(r.lrcText);
        }
      })
      .catch(e => {
        if (!cancelled) {
          console.warn('[FullPlayer] 歌词加载失败', e);
          setLrcText(null);
        }
      })
      .finally(() => {
        if (!cancelled) {
          setLyricsLoading(false);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [tab, track?.id]);

  const onSeekComplete = async (value: number) => {
    try {
      await seekTo(value);
    } catch (e) {
      console.warn('[FullPlayer] 跳转失败', e);
    }
  };

  const onQualityChange = async (q: AudioQuality) => {
    if (q === currentQuality || switching) {
      return;
    }
    setSwitching(true);
    try {
      await switchQuality(q);
      setCurrentQuality(q);
    } catch (e) {
      console.warn('[FullPlayer] 切换音质失败', e);
    } finally {
      setSwitching(false);
    }
  };

  const onControl = async (fn: () => Promise<void>, name: string) => {
    try {
      await fn();
    } catch (e) {
      console.warn(`[FullPlayer] ${name}失败`, e);
    }
  };

  return (
    <Modal
      visible={visible}
      animationType="slide"
      onRequestClose={onClose}
      statusBarTranslucent>
      <View style={styles.container}>
        {/* 顶栏：关闭 + 页签 */}
        <View style={styles.header}>
          <Pressable onPress={onClose} hitSlop={16} style={styles.closeBtn}>
            <Text style={styles.closeText}>﹀</Text>
          </Pressable>
          <View style={styles.tabs}>
            {(
              [
                {key: 'vinyl', label: '唱片'},
                {key: 'lyrics', label: '歌词'},
              ] as {key: Tab; label: string}[]
            ).map(t => (
              <Pressable
                key={t.key}
                onPress={() => setTab(t.key)}
                style={[styles.tab, tab === t.key && styles.tabActive]}>
                <Text
                  style={[
                    styles.tabText,
                    tab === t.key && styles.tabTextActive,
                  ]}>
                  {t.label}
                </Text>
              </Pressable>
            ))}
          </View>
          <View style={styles.closeBtn} />
        </View>

        {tab === 'vinyl' ? (
          <>
            {/* 黑胶唱片 */}
            <View style={styles.vinylWrap}>
              <Animated.View style={[styles.vinyl, {transform: [{rotate}]}]}>
                {track?.artwork ? (
                  <Image
                    source={{uri: track.artwork}}
                    style={styles.vinylArt}
                  />
                ) : (
                  <View style={styles.vinylArt} />
                )}
                <View style={styles.vinylHole} />
              </Animated.View>
            </View>

            <Text style={styles.title} numberOfLines={1}>
              {track?.title ?? '未知标题'}
            </Text>
            <Text style={styles.artist} numberOfLines={1}>
              {track?.artist ?? '未知艺人'}
            </Text>

            {/* 进度条 */}
            <View style={styles.sliderRow}>
              <Text style={styles.time}>{fmt(position)}</Text>
              <Slider
                style={styles.slider}
                minimumValue={0}
                maximumValue={Math.max(1, duration)}
                value={position}
                onSlidingComplete={onSeekComplete}
                minimumTrackTintColor="#ff5c7a"
                maximumTrackTintColor="rgba(255,255,255,0.25)"
                thumbTintColor="#fff"
              />
              <Text style={styles.time}>{fmt(duration)}</Text>
            </View>

            {/* 播放控制 */}
            <View style={styles.controls}>
              <Pressable
                hitSlop={16}
                onPress={() => onControl(playPrevious, '上一曲')}>
                <Text style={styles.ctrlIcon}>⏮</Text>
              </Pressable>
              <Pressable
                hitSlop={16}
                style={styles.playWrap}
                onPress={() => onControl(togglePlay, '播放/暂停')}>
                <Text style={styles.playIcon}>{playing ? '❚❚' : '▶'}</Text>
              </Pressable>
              <Pressable
                hitSlop={16}
                onPress={() => onControl(playNext, '下一曲')}>
                <Text style={styles.ctrlIcon}>⏭</Text>
              </Pressable>
            </View>

            {/* 音质切换 */}
            <View style={styles.qualityRow}>
              {QUALITIES.map(q => (
                <Pressable
                  key={q.key}
                  onPress={() => onQualityChange(q.key)}
                  style={[
                    styles.qBtn,
                    currentQuality === q.key && styles.qBtnActive,
                  ]}>
                  <Text
                    style={[
                      styles.qText,
                      currentQuality === q.key && styles.qTextActive,
                    ]}>
                    {q.label}
                  </Text>
                </Pressable>
              ))}
              {switching && (
                <ActivityIndicator
                  size="small"
                  color="#fff"
                  style={styles.qLoading}
                />
              )}
            </View>
          </>
        ) : (
          <View style={styles.lyricsWrap}>
            {lyricsLoading ? (
              <View style={styles.lyricsLoading}>
                <ActivityIndicator size="large" color="#fff" />
              </View>
            ) : (
              <LyricsView lrcText={lrcText} />
            )}
          </View>
        )}
      </View>
    </Modal>
  );
}

const VINYL_SIZE = 280;

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0a0a0f',
    paddingTop: 48,
    paddingHorizontal: 24,
    paddingBottom: 40,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  closeBtn: {
    width: 44,
    height: 44,
    justifyContent: 'center',
    alignItems: 'center',
  },
  closeText: {
    color: '#fff',
    fontSize: 24,
  },
  tabs: {
    flexDirection: 'row',
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderRadius: 20,
    padding: 3,
  },
  tab: {
    paddingHorizontal: 18,
    paddingVertical: 7,
    borderRadius: 17,
  },
  tabActive: {
    backgroundColor: 'rgba(255,255,255,0.16)',
  },
  tabText: {
    color: 'rgba(255,255,255,0.55)',
    fontSize: 13,
  },
  tabTextActive: {
    color: '#fff',
    fontWeight: '600',
  },
  vinylWrap: {
    alignItems: 'center',
    marginTop: 36,
  },
  vinyl: {
    width: VINYL_SIZE,
    height: VINYL_SIZE,
    borderRadius: VINYL_SIZE / 2,
    backgroundColor: '#101016',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  vinylArt: {
    width: VINYL_SIZE * 0.52,
    height: VINYL_SIZE * 0.52,
    borderRadius: (VINYL_SIZE * 0.52) / 2,
    backgroundColor: '#23232e',
  },
  vinylHole: {
    position: 'absolute',
    width: 14,
    height: 14,
    borderRadius: 7,
    backgroundColor: '#0a0a0f',
    borderWidth: 2,
    borderColor: 'rgba(255,255,255,0.35)',
  },
  title: {
    color: '#fff',
    fontSize: 22,
    fontWeight: '700',
    textAlign: 'center',
    marginTop: 32,
  },
  artist: {
    color: 'rgba(255,255,255,0.55)',
    fontSize: 15,
    textAlign: 'center',
    marginTop: 8,
  },
  sliderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 28,
  },
  time: {
    color: 'rgba(255,255,255,0.55)',
    fontSize: 12,
    width: 40,
    textAlign: 'center',
    fontVariant: ['tabular-nums'],
  },
  slider: {
    flex: 1,
    height: 32,
  },
  controls: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 12,
  },
  ctrlIcon: {
    color: '#fff',
    fontSize: 30,
    marginHorizontal: 28,
  },
  playWrap: {
    width: 72,
    height: 72,
    borderRadius: 36,
    backgroundColor: '#ff5c7a',
    justifyContent: 'center',
    alignItems: 'center',
  },
  playIcon: {
    color: '#fff',
    fontSize: 28,
  },
  qualityRow: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    marginTop: 28,
  },
  qBtn: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.2)',
    marginHorizontal: 6,
  },
  qBtnActive: {
    borderColor: '#ff5c7a',
    backgroundColor: 'rgba(255,92,122,0.15)',
  },
  qText: {
    color: 'rgba(255,255,255,0.6)',
    fontSize: 13,
  },
  qTextActive: {
    color: '#ff5c7a',
    fontWeight: '600',
  },
  qLoading: {
    marginLeft: 8,
  },
  lyricsWrap: {
    flex: 1,
    marginTop: 16,
  },
  lyricsLoading: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
});
