# music-platform 音乐平台

React Native 客户端 + NestJS 后端 + GitHub Actions 云端打包 IPA 的完整音乐平台。

## 目录结构

```
music-platform/
├── app/                    # React Native 0.74 客户端（react-native-track-player 音频内核）
│   ├── src/api/            # 后端 API 封装（游客/微信/短信登录、Feed、搜索、流、统计）
│   ├── src/audio/          # 播放器单例 + 后台播放服务（index.js 顶层注册）
│   ├── src/components/     # MiniPlayer / FullPlayer（黑胶动效）/ LyricsView（节流歌词）
│   ├── src/screens/        # 发现 / 搜索 / 我的（含账号注销）/ 登录
│   └── ios/                # iOS 原生配置（后台音频、隐私清单、Associated Domains）
├── backend/                # NestJS 后端（认证 / 音乐 / 预签名流 / 防刷统计 / 歌单）
├── db/init.sql             # PostgreSQL 建表 DDL
├── nginx/nginx.conf        # 流媒体网关（强制暴露 Range/206 关键头）
├── docker-compose.yml      # PostgreSQL 16 + Redis 7 + 后端 + Nginx 一键启动
└── .github/workflows/build-ipa.yml  # 零死锁云端出包流水线
```

## 快速开始

```bash
cp .env.example .env && vi .env   # 填 DB_PASSWORD / REDIS_PASSWORD / JWT_SECRET / 存储密钥
docker compose up -d --build
```

## 出包

Actions → Build IPA → Run workflow（需先在仓库 Secrets 配好
`P12_BASE64` / `P12_PASSWORD` / `MOBILEPROVISION_BASE64`，
且 `app/ios/MusicApp/Info.plist` 的 Bundle ID 与描述文件一致）。
