/**
 * 应用入口。
 *
 * 关键约束：音频后台服务必须在这里的顶层直接注册，
 * 禁止写进任何组件的生命周期（useEffect / componentDidMount 等）。
 * 原因：iOS 杀后台 / 锁屏 / 耳机线控等系统级音频事件需要一个与 UI
 * 无关的 headless JS 上下文来接管，写进组件会导致后台被挂起后事件丢失。
 */
import {AppRegistry} from 'react-native';
// 实验：注释掉 track-player，看是否还闪退（测试 NSAllowsLocalNetworking 是否为其所需）
// import TrackPlayer from 'react-native-track-player';
import App from './App';
import {name as appName} from './app.json';

// 顶层注册后台播放服务（headless），与组件树无关
// TrackPlayer.registerPlaybackService(() =>
//   require('./src/audio/playbackService').default,
// );

AppRegistry.registerComponent(appName, () => App);
