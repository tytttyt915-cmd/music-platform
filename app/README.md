# MusicApp（音乐平台客户端）

React Native 0.74 裸工程 + `react-native-track-player` 4.x 音频内核，
对接 Phase 1 的 NestJS 音乐网关（PostgreSQL + Redis + Nginx 流媒体）。

## 目录结构

```
app/
├── index.js # 入口：顶层注册音频后台服务（禁止写进组件生命周期）
├── App.tsx # 底部 Tab（发现/搜索/我的）+ 启动初始化 + 错误边界
├── src/
│ ├── api/
│ │ ├── config.ts # API_URL 网关地址
│ │ └── client.ts # 鉴权 fetch 封装 + 全部后端接口（游客/微信/短信/音乐/注销）
│ ├── audio/
│ │ ├── playbackService.ts# 后台 headless 服务：锁屏/线控/来电打断/ducking
│ │ └── player.ts # 播放器单例：setup / 播放 / 音质切换 / 上下曲 / 跳转
│ ├── components/
│ │ ├── MiniPlayer.tsx # 常驻底部迷你播放栏
│ │ ├── FullPlayer.tsx # 全屏播放器：黑胶旋转 + Slider + 音质 + 歌词页签
│ │ └── LyricsView.tsx # LRC 歌词：二分查找行索引，仅行变化时 setState
│ └── screens/
│ ├── HomeScreen.tsx # 发现页：分页 Feed
│ ├── SearchScreen.tsx # 搜索页
│ ├── SettingsScreen.tsx# 我的页：账号状态 + 注销账号（Apple 5.1.1(v)）
│ └── AuthScreen.tsx # 登录页：微信（Mock 联调）+ 手机号验证码
└── ios/
├── Podfile # use_frameworks!:linkage =>:static（已显式声明）
└── MusicApp/
├── Info.plist # UIBackgroundModes=audio / 微信 Scheme 占位
├── PrivacyInfo.xcprivacy # 隐私清单（Tracking=false，4 项 API 原因）
├── MusicApp.entitlements # associated-domains（Universal Links）
└── AppDelegate.mm # track-player 4.x 无需额外原生代码（见注释）
```

## Linux 云端宿主可做的事

```bash
cd ~/workspace/music-platform/app

# 安装依赖（注意 --no-bin-links，见下）
npm ci --no-audit --no-fund --no-bin-links

# 类型检查（必须零错误）
node node_modules/typescript/bin/tsc --noEmit

# 启动 Metro（iOS 真机调试见下）
node node_modules/react-native/cli.js start
```

> **环境说明**：本沙箱的 overlay 文件系统限制了 `chown` 系统调用，
> `npm install` 在链接 bin 文件时会报 `EPERM: chown` 失败，
> 因此安装必须加 `--no-bin-links`。macOS CI（Phase 4）无此限制，
> 用普通 `npm ci` 即可。

## iOS 真机调试路线

- 本工程是**裸 RN 工程**，`npx expo start --tunnel` 的方案**不适用**
（Expo tunnel 只服务于 Expo 托管/开发构建，本工程无 Expo）。
- iOS 真机调试走 **Phase 4 GitHub Actions 流水线**：
macOS runner 上 `pod install` → 注入你的证书与描述文件 →
`xcodebuild archive/export` → 产物 `.ipa` 进 Artifacts（可选推送蒲公英），
真机用 OTA/蒲公英链接安装。
- JS 层逻辑可用上面 Metro 打 bundle 的方式先验证
（`index.bundle?platform=ios` 能 200 即说明全部 import 可解析）。

## 首次配置清单（Phase 4 出包前必须完成）

| # | 配置项 | 位置 | 说明 |
|---|--------|------|------|
| 1 | `API_URL` | `src/api/config.ts` | 后端网关公网地址，如 `https://music.example.com/audio`（当前为 `http://YOUR_SERVER_IP/audio` 占位） |
| 2 | 微信 AppID | `ios/MusicApp/Info.plist`（`wx0000000000`） | 替换为真实微信 AppID；同时在 `AuthScreen.tsx` 接入微信原生 SDK（当前走后端 Mock 联调通道） |
| 3 | 关联域名 | `ios/MusicApp/MusicApp.entitlements`（`applinks:music.example.com`） | 替换为真实域名，并在该域名部署 `apple-app-site-association` |
| 4 | Bundle ID | `ios/MusicApp.xcodeproj/project.pbxproj`（当前 `com.example.musicapp`） | 必须与你的 `.mobileprovision` 描述文件中的 App ID 完全一致；Phase 4 流水线会校验 |
| 5 | GitHub Secrets | 仓库 Settings → Secrets | `P12_BASE64`、`P12_PASSWORD`、`MOBILEPROVISION_BASE64`（Phase 4 待你确认后配置） |

## 合规要点（已内置）

- Apple IAP（Guideline 3.1.1）：iOS 端无任何微信/支付宝支付通道，VIP/付费能力预留 StoreKit 2 接入点。
- 纯净游客试听（Guideline 5.1.1）：启动无 token 自动 `POST /auth/guest` 建游客身份。
- 账号注销闭环（Guideline 5.1.1(v)）：「我的」页→ 二次确认 →
`DELETE /account` → 清本地登录态 → 自动重建游客身份。
- 音频走后端 302 签名直链（OSS/COS 经 Nginx），支持 HTTP Range 206；
响应头 `Content-Range / Accept-Ranges / Content-Length / ETag` 由 `nginx.conf` 强制暴露。
