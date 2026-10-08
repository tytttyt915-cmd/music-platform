/**
 * LRC 歌词滚动视图。
 *
 * 性能关键（防掉帧）：
 * 1. 用当前播放进度二分查找行索引，仅当行索引变化时才 setState，
 *    杜绝 progress 每秒多次回调触发的毫秒级高频重渲染；
 * 2. FlatList 固定行高 + getItemLayout，滚动定位走原生侧 scrollToIndex；
 * 3. 用 ref 保存上一次行索引，避免闭包拿到旧值导致重复 setState。
 */
import React, {useEffect, useMemo, useRef, useState} from 'react';
import {
  FlatList,
  ListRenderItemInfo,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import {useProgress} from 'react-native-track-player';

export interface LyricLine {
  timeMs: number;
  text: string;
}

/** 固定行高：与样式保持一致，供 getItemLayout 使用 */
const ROW_HEIGHT = 46;

/**
 * 解析 LRC：支持 [mm:ss.xx] / [mm:ss.xxx] / [mm:ss]；
 * 行内多个时间标签只取第一个；无文本的行丢弃；结果按时间排序。
 */
export function parseLrc(lrc: string): LyricLine[] {
  const lines: LyricLine[] = [];
  const tagRe = /\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;
  for (const rawLine of lrc.split('\n')) {
    const line = rawLine.trim();
    if (!line) {
      continue;
    }
    tagRe.lastIndex = 0;
    const m = tagRe.exec(line);
    if (!m) {
      continue;
    }
    const min = parseInt(m[1], 10);
    const sec = parseInt(m[2], 10);
    const frac = m[3] ? parseInt(m[3].padEnd(3, '0').slice(0, 3), 10) : 0;
    const timeMs = (min * 60 + sec) * 1000 + frac;
    const text = line.slice(m[0].length).trim() || line.replace(tagRe, '').trim();
    if (!text) {
      continue;
    }
    lines.push({timeMs, text});
  }
  lines.sort((a, b) => a.timeMs - b.timeMs);
  return lines;
}

/**
 * 二分查找：返回 timeMs 对应的当前行索引
 *（最后一个 timeMs <= t 的行）；无匹配返回 -1。
 */
export function findLyricIndex(lines: LyricLine[], timeMs: number): number {
  let lo = 0;
  let hi = lines.length - 1;
  let ans = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (lines[mid].timeMs <= timeMs) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}

interface Props {
  lrcText: string | null;
}

export default function LyricsView({lrcText}: Props) {
  const {position} = useProgress();
  const lines = useMemo(() => (lrcText ? parseLrc(lrcText) : []), [lrcText]);
  const [activeIndex, setActiveIndex] = useState(-1);
  // 用 ref 做“是否变化”判断，避免 effect 闭包拿到旧的 state
  const indexRef = useRef(-1);
  const listRef = useRef<FlatList<LyricLine>>(null);

  // 进度回调节流：只有行索引变化时才 setState 触发重渲染
  useEffect(() => {
    const idx = findLyricIndex(lines, position * 1000);
    if (idx !== indexRef.current) {
      indexRef.current = idx;
      setActiveIndex(idx);
    }
  }, [position, lines]);

  // 当前行变化时滚动到垂直居中
  useEffect(() => {
    if (activeIndex < 0 || lines.length === 0) {
      return;
    }
    try {
      listRef.current?.scrollToIndex({
        index: activeIndex,
        animated: true,
        viewPosition: 0.5,
      });
    } catch {
      // 行尚未布局完成时忽略，下一次行索引变化会重试
    }
  }, [activeIndex, lines.length]);

  const renderItem = ({item, index}: ListRenderItemInfo<LyricLine>) => {
    const active = index === activeIndex;
    return (
      <View style={[styles.row, active && styles.activeRow]}>
        <Text style={[styles.line, active && styles.activeLine]} numberOfLines={2}>
          {item.text}
        </Text>
      </View>
    );
  };

  if (lines.length === 0) {
    return (
      <View style={styles.empty}>
        <Text style={styles.emptyText}>暂无歌词</Text>
      </View>
    );
  }

  return (
    <FlatList
      ref={listRef}
      data={lines}
      keyExtractor={(_, i) => String(i)}
      renderItem={renderItem}
      getItemLayout={(_, index) => ({
        length: ROW_HEIGHT,
        offset: ROW_HEIGHT * index,
        index,
      })}
      initialNumToRender={15}
      maxToRenderPerBatch={20}
      windowSize={11}
      removeClippedSubviews
      showsVerticalScrollIndicator={false}
      contentContainerStyle={styles.list}
      onScrollToIndexFailed={info => {
        // 兜底：等待布局完成后重试一次
        setTimeout(() => {
          try {
            listRef.current?.scrollToIndex({
              index: info.index,
              animated: true,
              viewPosition: 0.5,
            });
          } catch {
            // 忽略
          }
        }, 300);
      }}
    />
  );
}

const styles = StyleSheet.create({
  list: {
    paddingVertical: 120,
  },
  row: {
    height: ROW_HEIGHT,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 32,
  },
  activeRow: {},
  line: {
    fontSize: 15,
    color: 'rgba(255,255,255,0.45)',
    textAlign: 'center',
    lineHeight: 22,
  },
  activeLine: {
    fontSize: 18,
    fontWeight: '700',
    color: '#fff',
  },
  empty: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  emptyText: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 15,
  },
});
