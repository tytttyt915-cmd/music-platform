/**
 * 应用根组件：
 * - 底部 Tab 导航（发现 / 搜索 / 我的），每个 Tab 页底部挂载常驻 MiniPlayer
 * - 启动时初始化音频内核；无 token 时自动创建游客身份（纯净试听，Guideline 5.1.1）
 * - 全局错误边界：渲染崩溃时展示兜底页而非白屏
 */
import React, {useEffect, useState} from 'react';
import {ActivityIndicator, StyleSheet, Text, View} from 'react-native';
import {NavigationContainer} from '@react-navigation/native';
import {createBottomTabNavigator} from '@react-navigation/bottom-tabs';
import {SafeAreaProvider} from 'react-native-safe-area-context';
import {setupPlayer} from './src/audio/player';
import {getStoredToken, guestLogin} from './src/api/client';
import HomeScreen from './src/screens/HomeScreen';
import SearchScreen from './src/screens/SearchScreen';
import SettingsScreen from './src/screens/SettingsScreen';
import MiniPlayer from './src/components/MiniPlayer';

const Tab = createBottomTabNavigator();

/** 全局错误边界：捕获渲染期异常，展示兜底页 */
class ErrorBoundary extends React.Component<
  {children: React.ReactNode},
  {error: Error | null}
> {
  state: {error: Error | null} = {error: null};

  static getDerivedStateFromError(error: Error) {
    return {error};
  }

  componentDidCatch(error: Error) {
    console.error('[ErrorBoundary] 捕获到渲染异常', error);
  }

  render() {
    if (this.state.error) {
      return (
        <View style={styles.crash}>
          <Text style={styles.crashTitle}>应用出现异常</Text>
          <Text style={styles.crashMsg}>{this.state.error.message}</Text>
          <Text style={styles.crashHint}>
            请重启应用；若持续出现请联系技术支持
          </Text>
        </View>
      );
    }
    return this.props.children;
  }
}

/**
 * 为每个 Tab 页底部挂载常驻 MiniPlayer。
 * MiniPlayer 无播放记录时返回 null，不占布局，因此可放心常驻。
 */
function withPlayerBar<P extends object>(
  Screen: React.ComponentType<P>,
): React.ComponentType<P> {
  return function ScreenWithPlayerBar(props: P) {
    return (
      <View style={styles.screen}>
        <Screen {...props} />
        <MiniPlayer />
      </View>
    );
  };
}

const HomeWithBar = withPlayerBar(HomeScreen);
const SearchWithBar = withPlayerBar(SearchScreen);
const SettingsWithBar = withPlayerBar(SettingsScreen);

export default function App() {
  const [ready, setReady] = useState(false);
  const [bootError, setBootError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        // 1. 初始化音频内核（幂等，失败可重试）
        await setupPlayer();
        // 2. 游客兜底：无 token 时自动创建游客身份，保证纯净试听
        const token = await getStoredToken();
        if (!token) {
          await guestLogin();
        }
      } catch (e) {
        console.error('[App] 启动初始化失败', e);
        if (!cancelled) {
          setBootError('初始化失败，请检查网络后重启应用');
        }
      } finally {
        if (!cancelled) {
          setReady(true);
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  if (!ready) {
    return (
      <View style={styles.loading}>
        <ActivityIndicator size="large" color="#ff5c7a" />
        {bootError && <Text style={styles.bootError}>{bootError}</Text>}
      </View>
    );
  }

  return (
    <ErrorBoundary>
      <SafeAreaProvider>
        <NavigationContainer>
          <Tab.Navigator
            screenOptions={{
              headerShown: false,
              tabBarActiveTintColor: '#ff5c7a',
              tabBarInactiveTintColor: 'rgba(255,255,255,0.5)',
              tabBarStyle: {
                backgroundColor: '#0a0a0f',
                borderTopColor: 'rgba(255,255,255,0.08)',
              },
            }}>
            <Tab.Screen
              name="Home"
              component={HomeWithBar}
              options={{title: '发现'}}
            />
            <Tab.Screen
              name="Search"
              component={SearchWithBar}
              options={{title: '搜索'}}
            />
            <Tab.Screen
              name="Settings"
              component={SettingsWithBar}
              options={{title: '我的'}}
            />
          </Tab.Navigator>
        </NavigationContainer>
      </SafeAreaProvider>
    </ErrorBoundary>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: '#0a0a0f',
  },
  loading: {
    flex: 1,
    backgroundColor: '#0a0a0f',
    justifyContent: 'center',
    alignItems: 'center',
  },
  bootError: {
    color: '#ff5c7a',
    fontSize: 14,
    marginTop: 16,
    paddingHorizontal: 32,
    textAlign: 'center',
  },
  crash: {
    flex: 1,
    backgroundColor: '#0a0a0f',
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 32,
  },
  crashTitle: {
    color: '#fff',
    fontSize: 20,
    fontWeight: '700',
  },
  crashMsg: {
    color: 'rgba(255,255,255,0.6)',
    fontSize: 14,
    marginTop: 12,
    textAlign: 'center',
  },
  crashHint: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 13,
    marginTop: 8,
    textAlign: 'center',
  },
});
