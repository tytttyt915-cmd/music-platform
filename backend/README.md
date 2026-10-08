# music-platform 后端

NestJS 10 + TypeORM + PostgreSQL + Redis 实现的音乐平台后端：
微信/SMS 登录、游客试听、账号注销闭环、分页音乐流、LRC 歌词、
对象存储预签名 302 推流、多码率元数据、防刷播放统计、歌单管理。

表结构以 `../db/init.sql` 为准，`synchronize: false`（运行时不碰 schema）。

## 快速开始（本地）

```bash
cd backend
cp .env.example .env        # 按需修改
npm install
npm run start:dev
```

依赖的 PostgreSQL / Redis 可用 Docker 起：

```bash
docker run -d --name pg -e POSTGRES_USER=music -e POSTGRES_PASSWORD=music_password \
  -e POSTGRES_DB=musicdb -p 5432:5432 postgres:16
docker run -d --name redis -p 6379:6379 redis:7
# 初始化表结构
psql "postgres://music:music_password@localhost:5432/musicdb" -f ../db/init.sql
```

本地 `.env` 中把 `DB_HOST=localhost`、`REDIS_URL=redis://localhost:6379` 改好即可。

## Docker（生产，配合 docker-compose）

```bash
# 在 music-platform/ 根目录
docker compose up -d --build backend
```

容器入口为编译产物 `node dist/main.js`（见 `Dockerfile` 多阶段构建），
健康检查 `GET /health`（检查 DB + Redis 连通性）。

## 环境变量

| 变量 | 说明 |
|---|---|
| `PORT` | 监听端口（默认 3000） |
| `DB_HOST/DB_PORT/DB_USERNAME/DB_PASSWORD/DB_DATABASE` | PostgreSQL 连接 |
| `REDIS_URL` | Redis 连接串 |
| `JWT_SECRET` | **必填**，生产必须强随机串，缺失则启动失败 |
| `JWT_EXPIRES_IN` / `REFRESH_TOKEN_TTL_DAYS` | access / refresh 有效期 |
| `AUTH_MOCK=true` | 微信登录走 Mock（任意 code 可登录，unionid=`mock:<code>`） |
| `SMS_MOCK=true` | 短信走 Mock（验证码固定 `123456`，打日志） |
| `WECHAT_APPID` / `WECHAT_SECRET` | `AUTH_MOCK=false` 时必填，真实调微信 code2session |
| `SMS_PROVIDER` | 真实短信通道扩展点（aliyun / tencent），见 `AuthService.sendRealSms` |
| `STORAGE_PROVIDER` | `oss` \| `cos`，缺对应 key 时启动即抛错说明 |
| `SIGNED_URL_TTL` | 预签名 URL 有效期（秒） |
| `OSS_REGION/OSS_BUCKET/OSS_ACCESS_KEY_ID/OSS_ACCESS_KEY_SECRET` | 阿里云 OSS |
| `COS_REGION/COS_BUCKET/COS_SECRET_ID/COS_SECRET_KEY` | 腾讯云 COS |

## 接口一览（响应统一为 `{code, message, data}`）

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/health` | 健康检查（db/redis） |
| POST | `/auth/wechat/login` `{code}` | 微信登录（Mock/真实 code2session） |
| POST | `/auth/sms/send` `{phone}` | 发送验证码（Mock 返回 123456） |
| POST | `/auth/sms/verify` `{phone, code}` | 校验并登录/注册，签发 token 对 |
| POST | `/auth/guest` | 纯净游客 token（未登录试听） |
| POST | `/auth/refresh` `{refreshToken}` | 轮换刷新 token 对 |
| POST | `/auth/logout` `{refreshToken}` | 吊销 refresh token（需登录） |
| DELETE | `/account` | 账号注销：软删除 + 吊销全部 token（需登录） |
| GET | `/music/feed?page=&pageSize=` | 分页音乐流（仅 online，按播放量倒序） |
| GET | `/music/search?q=&page=` | 标题/艺人 ILIKE 搜索 |
| GET | `/music/track/:id` | 歌曲详情 + 多码率列表 |
| GET | `/music/track/:id/lyrics` | LRC 歌词 |
| GET | `/music/track/:id/stream?quality=high` | **302 重定向**到预签名音频 URL |
| POST | `/music/track/:id/play` `{quality?}` | 播放统计（登录用户自然日防刷；游客只记事件） |
| POST | `/playlists` | 创建歌单（需登录） |
| GET | `/playlists/:id` | 歌单详情（含歌曲按 position 排序） |
| POST | `/playlists/:id/tracks` `{trackId}` | 向歌单追加歌曲（仅所有者） |

除标 `@Public()` 的接口外，其余均需 `Authorization: Bearer <accessToken>`。

## 类型检查

```bash
npm run typecheck   # tsc --noEmit
npm run build       # 生成 dist/
```
