#import "AppDelegate.h"

#import <React/RCTBundleURLProvider.h>

// 说明：react-native-track-player 4.x 在 iOS 侧无需任何额外原生代码。
// 原因：
// 1. 原生模块通过 React Native 新架构/TurboModule 自动注册，
//    JS 侧 index.js 顶层的 registerPlaybackService 即完成后台服务绑定；
// 2. 后台音频能力由 Info.plist 的 UIBackgroundModes=audio 声明；
// 3. 音频会话（AVAudioSession）与锁屏信息（MPNowPlayingInfoCenter）
//    均由 track-player 原生层自行管理。
// 因此本文件保持模板默认实现即可，不要画蛇添足。

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  self.moduleName = @"MusicApp";
  // You can add your custom initial props in the dictionary below.
  // They will be passed down to the ViewController used by React Native.
  self.initialProps = @{};

  return [super application:application didFinishLaunchingWithOptions:launchOptions];
}

- (NSURL *)sourceURLForBridge:(RCTBridge *)bridge
{
  return [self bundleURL];
}

- (NSURL *)bundleURL
{
#if DEBUG
  return [[RCTBundleURLProvider sharedSettings] jsBundleURLForBundleRoot:@"index"];
#else
  return [[NSBundle mainBundle] URLForResource:@"main" withExtension:@"jsbundle"];
#endif
}

@end
