/**
 * 搜索页：搜索框 + 结果列表，点击即播放。
 * 空查询不发请求；搜索失败展示错误并可重试。
 */
import React, {useRef, useState} from 'react';
import {
  ActivityIndicator,
  FlatList,
  Image,
  ListRenderItemInfo,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import {ApiError, TrackInfo, searchTracks} from '../api/client';
import {playTrack, toPlayable} from '../audio/player';

export default function SearchScreen() {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<TrackInfo[]>([]);
  const [searched, setSearched] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // 搜索中的请求序号：只采用最新一次的结果，避免乱序覆盖
  const reqSeq = useRef(0);

  const doSearch = async () => {
    const q = query.trim();
    if (!q) {
      return;
    }
    const seq = ++reqSeq.current;
    setLoading(true);
    setError(null);
    try {
      const res = await searchTracks(q, 1, 20);
      if (seq !== reqSeq.current) {
        return; // 已被更新的搜索取代，丢弃
      }
      setResults(res.list);
      setSearched(true);
    } catch (e) {
      if (seq !== reqSeq.current) {
        return;
      }
      setError(e instanceof ApiError ? e.message : '搜索失败，请重试');
    } finally {
      if (seq === reqSeq.current) {
        setLoading(false);
      }
    }
  };

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
    </Pressable>
  );

  return (
    <View style={styles.container}>
      <Text style={styles.header}>搜索</Text>
      <View style={styles.searchRow}>
        <TextInput
          style={styles.input}
          placeholder="搜索歌曲 / 艺人"
          placeholderTextColor="rgba(255,255,255,0.35)"
          value={query}
          onChangeText={setQuery}
          onSubmitEditing={doSearch}
          returnKeyType="search"
          clearButtonMode="while-editing"
        />
        <Pressable style={styles.searchBtn} onPress={doSearch}>
          <Text style={styles.searchBtnText}>搜索</Text>
        </Pressable>
      </View>

      {loading && (
        <ActivityIndicator size="large" color="#fff" style={styles.loading} />
      )}
      {error && (
        <Pressable style={styles.errorBar} onPress={doSearch}>
          <Text style={styles.errorText}>{error}（点击重试）</Text>
        </Pressable>
      )}
      {!loading && !error && searched && results.length === 0 && (
        <Text style={styles.empty}>没有找到相关歌曲，换个关键词试试</Text>
      )}
      {!loading && !error && !searched && (
        <Text style={styles.empty}>输入关键词，探索全网音乐</Text>
      )}

      <FlatList
        data={results}
        keyExtractor={item => item.id}
        renderItem={renderItem}
        keyboardShouldPersistTaps="handled"
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
    marginBottom: 12,
  },
  searchRow: {
    flexDirection: 'row',
    paddingHorizontal: 16,
    marginBottom: 8,
  },
  input: {
    flex: 1,
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 10,
    color: '#fff',
    fontSize: 15,
  },
  searchBtn: {
    marginLeft: 10,
    backgroundColor: '#ff5c7a',
    borderRadius: 10,
    paddingHorizontal: 18,
    justifyContent: 'center',
  },
  searchBtnText: {
    color: '#fff',
    fontSize: 15,
    fontWeight: '600',
  },
  loading: {
    marginTop: 60,
  },
  errorBar: {
    backgroundColor: 'rgba(255,92,122,0.12)',
    marginHorizontal: 16,
    marginTop: 12,
    padding: 10,
    borderRadius: 8,
  },
  errorText: {
    color: '#ff5c7a',
    fontSize: 13,
    textAlign: 'center',
  },
  empty: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 14,
    textAlign: 'center',
    marginTop: 60,
    paddingHorizontal: 32,
  },
  item: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 10,
  },
  cover: {
    width: 48,
    height: 48,
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
});
