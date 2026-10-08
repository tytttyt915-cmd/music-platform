/**
 * 发现页：分页音乐 Feed 流（封面 / 标题 / 艺人 / 播放数），点击即播放。
 * 上拉加载更多、下拉刷新；loadingRef 防止 onEndReached 重复触发。
 */
import React, {useCallback, useEffect, useRef, useState} from 'react';
import {
  ActivityIndicator,
  FlatList,
  Image,
  ListRenderItemInfo,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import {ApiError, PageResult, TrackInfo, getFeed} from '../api/client';
import {playTrack, toPlayable} from '../audio/player';

const PAGE_SIZE = 20;

/** 播放数格式化：12345 → 1.2万 */
function formatPlayCount(raw: string): string {
  const n = Number(raw);
  if (!Number.isFinite(n)) {
    return raw;
  }
  if (n >= 10000) {
    return `${(n / 10000).toFixed(1)}万`;
  }
  return String(n);
}

export default function HomeScreen() {
  const [tracks, setTracks] = useState<TrackInfo[]>([]);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // 防止 onEndReached 在一次加载完成前被重复触发
  const loadingRef = useRef(false);

  const load = useCallback(async (p: number, replace: boolean) => {
    if (loadingRef.current) {
      return;
    }
    loadingRef.current = true;
    if (replace) {
      setRefreshing(true);
    } else {
      setLoadingMore(true);
    }
    setError(null);
    try {
      const res: PageResult<TrackInfo> = await getFeed(p, PAGE_SIZE);
      setTracks(prev => (replace ? res.list : [...prev, ...res.list]));
      setPage(p);
      setHasMore(res.page * res.pageSize < res.total);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : '加载失败，请下拉重试');
    } finally {
      loadingRef.current = false;
      setLoadingMore(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    load(1, true);
  }, [load]);

  const onPlay = async (t: TrackInfo) => {
    try {
      await playTrack(toPlayable(t), 'high');
    } catch (e) {
      setError(e instanceof ApiError ? e.message : '播放失败，请稍后重试');
    }
  };

  const renderItem = ({item}: ListRenderItemInfo<TrackInfo>) => (
    <Pressable style={styles.item} onPress={() => onPlay(item)}>
      {item.coverUrl ? (
        <Image source={{uri: item.coverUrl}} style={styles.cover} />
      ) : (
        <View style={[styles.cover, styles.coverPlaceholder]} />
      )}
      <View style={styles.meta}>
        <Text style={styles.title} numberOfLines={1}>
          {item.title}
        </Text>
        <Text style={styles.artist} numberOfLines={1}>
          {item.artist}
        </Text>
      </View>
      <Text style={styles.count}>▶ {formatPlayCount(item.playCount)}</Text>
    </Pressable>
  );

  return (
    <View style={styles.container}>
      <Text style={styles.header}>发现音乐</Text>
      {error && (
        <Pressable style={styles.errorBar} onPress={() => load(1, true)}>
          <Text style={styles.errorText}>{error}（点击重试）</Text>
        </Pressable>
      )}
      <FlatList
        data={tracks}
        keyExtractor={item => item.id}
        renderItem={renderItem}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={() => load(1, true)}
            tintColor="#fff"
          />
        }
        onEndReached={() => {
          if (hasMore && !loadingRef.current) {
            load(page + 1, false);
          }
        }}
        onEndReachedThreshold={0.4}
        ListFooterComponent={
          loadingMore ? (
            <ActivityIndicator
              size="small"
              color="#fff"
              style={styles.footerLoading}
            />
          ) : !hasMore && tracks.length > 0 ? (
            <Text style={styles.footerEnd}>— 到底啦 —</Text>
          ) : null
        }
        ListEmptyComponent={
          !refreshing && !error ? (
            <Text style={styles.empty}>暂无推荐，去搜索喜欢的音乐吧</Text>
          ) : null
        }
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0a0a0f',
    paddingTop: 56,
  },
  header: {
    color: '#fff',
    fontSize: 24,
    fontWeight: '800',
    paddingHorizontal: 16,
    marginBottom: 8,
  },
  errorBar: {
    backgroundColor: 'rgba(255,92,122,0.12)',
    marginHorizontal: 16,
    marginBottom: 8,
    padding: 10,
    borderRadius: 8,
  },
  errorText: {
    color: '#ff5c7a',
    fontSize: 13,
    textAlign: 'center',
  },
  item: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 10,
  },
  cover: {
    width: 52,
    height: 52,
    borderRadius: 8,
    backgroundColor: '#23232e',
  },
  coverPlaceholder: {},
  meta: {
    flex: 1,
    marginLeft: 12,
  },
  title: {
    color: '#fff',
    fontSize: 15,
    fontWeight: '600',
  },
  artist: {
    color: 'rgba(255,255,255,0.55)',
    fontSize: 13,
    marginTop: 4,
  },
  count: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 12,
  },
  footerLoading: {
    paddingVertical: 16,
  },
  footerEnd: {
    color: 'rgba(255,255,255,0.3)',
    fontSize: 12,
    textAlign: 'center',
    paddingVertical: 16,
  },
  empty: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 14,
    textAlign: 'center',
    marginTop: 80,
  },
});
