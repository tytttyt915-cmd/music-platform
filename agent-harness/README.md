# music-cli — 音乐平台后端 harness

CLI-Anything 风格的命令行工具，把音乐平台 NestJS 后端的 17 个接口封装成
AI Agent 可直接调用的 CLI 命令。所有命令输出 JSON。

## 安装

```bash
cd ~/workspace/music-platform/agent-harness
pip install -e .
# 依赖：click、requests（Python 3.10+）
```

## 快速上手

```bash
# 1. 健康检查
python3 -m music_cli health --pretty

# 2. 游客登录（token 自动保存）
python3 -m music_cli guest-login --pretty

# 3. 搜歌 / 拿详情
python3 -m music_cli search "夜航星" --pretty
python3 -m music_cli track <uuid> --pretty

# 4. 取播放链接（302 跳转，每次现取）
python3 -m music_cli stream <uuid> --quality high --pretty

# 5. 上报播放（需登录）
python3 -m music_cli play <uuid> --pretty
```

## 目录结构

```
agent-harness/
├── README.md            # 本文件
├── SKILL.md             # Agent 技能描述（cli-anything 规范）
├── setup.py             # pip 安装
└── music_cli/
    ├── __init__.py
    ├── __main__.py      # python3 -m music_cli 入口
    └── music_cli.py     # Click 命令实现
```

## 设计要点

- **信封解析**：后端返回 `{code, message, data}`，`code != 0` 时转为中文友好错误。
- **token 管理**：`~/.music_cli_token`（0600），`--token` 可覆盖，`logout`/`delete-account` 自动清除。
- **UUID 校验**：track/playlist id 先做 UUIDv4 校验，前端报错更友好（后端 `ParseUUIDPipe` 同样强校验）。
- **stream 302**：不跟随跳转，直接返回 `Location`（COS 预签名 URL，有过期时间）。

## 接口覆盖（16/17）

| # | 接口 | 命令 |
|---|---|---|
| 1 | GET /health | `health` |
| 2 | POST /auth/guest | `guest-login` |
| 3 | POST /auth/sms/send | `sms-send` |
| 4 | POST /auth/sms/verify | `sms-verify` |
| 5 | POST /auth/refresh | （预留，未暴露） |
| 6 | POST /auth/logout | `logout` |
| 7 | GET /music/feed | `feed` |
| 8 | GET /music/search | `search` |
| 9 | GET /music/track/:id | `track` |
| 10 | GET /music/track/:id/lyrics | `lyrics` |
| 11 | GET /music/track/:id/stream | `stream` |
| 12 | POST /music/track/:id/play | `play` |
| 13 | POST /playlists | `playlist create` |
| 14 | GET /playlists/:id | `playlist detail` |
| 15 | POST /playlists/:id/tracks | `playlist add` |
| 16 | （后端暂无歌单列表） | `playlist list` → 友好提示 |
| 17 | DELETE /account | `delete-account` |
