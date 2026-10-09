---
name: "cli-anything-music"
description: >-
  Command-line interface for the Music Platform backend (NestJS 10).
  Health check, guest/SMS auth, music feed/search/track/lyrics/stream,
  play-count reporting, playlist management, and account deletion.
  All commands output JSON for agent consumption.
---

# cli-anything-music

音乐平台后端（NestJS 10 + PostgreSQL + Redis）的 CLI-Anything 风格 harness。
覆盖后端 17 个接口中的 16 个（歌单列表后端暂无对应接口）。

## Installation

```bash
cd ~/workspace/music-platform/agent-harness
pip install -e .
# 或直接用：python3 -m music_cli --help
```

**Prerequisites:**
- Python 3.10+
- `pip install click requests`

## Usage

```bash
# 健康检查（公开）
python3 -m music_cli health

# 游客登录（token 自动保存到 ~/.music_cli_token）
python3 -m music_cli guest-login

# 短信登录
python3 -m music_cli sms-send 13800000000
python3 -m music_cli sms-verify 13800000000 123456

# 音乐（公开接口，无需登录）
python3 -m music_cli feed --page 1 --page-size 10
python3 -m music_cli search "夜航星"
python3 -m music_cli track <uuid>
python3 -m music_cli lyrics <uuid>
python3 -m music_cli stream <uuid> --quality high

# 播放统计上报（需登录）
python3 -m music_cli play <uuid>

# 歌单（需登录）
python3 -m music_cli playlist create --name "我的歌单"
python3 -m music_cli playlist detail <uuid>
python3 -m music_cli playlist add <playlist-uuid> <track-uuid>

# 账号
python3 -m music_cli logout
python3 -m music_cli delete-account --yes
```

## Global Options

| Option | Default | 说明 |
|---|---|---|
| `--base-url` | `http://111.230.155.174` | 后端地址 |
| `--token` | （自动读 `~/.music_cli_token`） | Bearer token |
| `--pretty` | off | 格式化 JSON 输出 |

## Command List

| 命令 | 接口 | 需登录 |
|---|---|---|
| `health` | GET /health | 否 |
| `guest-login` | POST /auth/guest | 否 |
| `sms-send <phone>` | POST /auth/sms/send | 否 |
| `sms-verify <phone> <code>` | POST /auth/sms/verify | 否 |
| `logout` | POST /auth/logout | 是 |
| `delete-account --yes` | DELETE /account | 是 |
| `feed` | GET /music/feed | 否 |
| `search <keyword>` | GET /music/search | 否 |
| `track <uuid>` | GET /music/track/:id | 否 |
| `lyrics <uuid>` | GET /music/track/:id/lyrics | 否 |
| `stream <uuid>` | GET /music/track/:id/stream | 否 |
| `play <uuid>` | POST /music/track/:id/play | 是 |
| `playlist create` | POST /playlists | 是 |
| `playlist detail <uuid>` | GET /playlists/:id | 是 |
| `playlist add <pid> <tid>` | POST /playlists/:id/tracks | 是 |
| `playlist list` | （后端暂无） | — |

## Notes

- 所有 track/playlist id 必须为 UUIDv4（后端 `ParseUUIDPipe` 强校验），非法 id 会中文提示。
- `stream` 返回 302 跳转的 COS 预签名 URL（有过期时间），每次播放现取，不要缓存。
- 输出统一为 JSON：`{"ok": true, "data": ...}` 或 `{"ok": false, "error": "...", "hint": "..."}`。
- token 存 `~/.music_cli_token`（0600 权限），不硬编码。
