/**
 * 常驻底部迷你播放栏：封面 / 标题 / 艺人 / 播放暂停按钮 / 顶部细进度条。
 * 无播放记录时返回 null，不占任何布局。点击任意处打开全屏播放器。
 */
import React, {useState} from 'react';
import {Image, Pressable, StyleSheet, Text, View} from 'react-native';
import TrackPlayer, {
  State,
  useActiveTrack,
  usePlaybackState,
  useProgress,
} from 'react-native-track-player';
import FullPlayer from './FullPlayer';

export default function MiniPlayer() {
  const track = useActiveTrack();
  const playback = usePlaybackState();
  const {position, duration} = useProgress();
  const [fullVisible, setFullVisible] = useState(false);

  // 无播放记录时不渲染，保持页面布局干净
  if (!track) {
    return null;
  }

  const playing = playback.state === State.Playing;
  const progress = duration > 0 ? Math.min(1, position / duration) : 0;

  const onToggle = async () => {
    try {
      if (playing) {
        await TrackPlayer.pause();
      } else {
        await TrackPlayer.play();
      }
    } catch (e) {
      console.warn('[MiniPlayer] 切换播放失败', e);
    }
  };

  return (
    <>
      <Pressable style={styles.bar} onPress={() => setFullVisible(true)}>
        {/* 顶部细进度条 */}
        <View style={styles.progressTrack}>
          <View style={[styles.progressFill, {width: `${progress * 100}%`}]} />
        </View>
        <View style={styles.row}>
          {track.artwork ? (
            <Image source={{uri: track.artwork}} style={styles.cover} />
          ) : (
            <View style={[styles.cover, styles.coverPlaceholder]} />
          )}
          <View style={styles.meta}>
            <Text style={styles.title} numberOfLines={1}>
              {track.title ?? '未知标题'}
            </Text>
            <Text style={styles.artist} numberOfLines={1}>
              {track.artist ?? '未知艺人'}
            </Text>
          </View>
          <Pressable
            style={styles.playBtn}
            hitSlop={12}
            onPress={e => {
              // 阻止冒泡，避免点播放按钮时误打开全屏播放器
              e.stopPropagation();
              onToggle();
            }}>
            <Text style={styles.playIcon}>{playing ? '❚❚' : '▶'}</Text>
          </Pressable>
        </View>
      </Pressable>
      <FullPlayer visible={fullVisible} onClose={() => setFullVisible(false)} />
    </>
  );
}

const styles = StyleSheet.create({
  bar: {
    backgroundColor: '#14141c',
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: 'rgba(255,255,255,0.1)',
  },
  progressTrack: {
    height: 2,
    backgroundColor: 'rgba(255,255,255,0.12)',
  },
  progressFill: {
    height: 2,
    backgroundColor: '#ff5c7a',
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  cover: {
    width: 44,
    height: 44,
    borderRadius: 6,
    backgroundColor: '#23232e',
  },
  coverPlaceholder: {},
  meta: {
    flex: 1,
    marginLeft: 10,
  },
  title: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  artist: {
    color: 'rgba(255,255,255,0.55)',
    fontSize: 12,
    marginTop: 2,
  },
  playBtn: {
    width: 40,
    height: 40,
    justifyContent: 'center',
    alignItems: 'center',
  },
  playIcon: {
    color: '#fff',
    fontSize: 20,
  },
});
