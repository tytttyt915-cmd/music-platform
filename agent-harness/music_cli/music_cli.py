#!/usr/bin/env python3
"""music-cli — 音乐平台后端（NestJS 10）的 CLI-Anything 风格 harness。

覆盖后端 17 个接口中的 16 个（歌单列表后端暂无对应接口）。

用法示例:
    python3 -m music_cli health
    python3 -m music_cli guest-login
    python3 -m music_cli search "夜航星"
    python3 -m music_cli feed --page 1 --page-size 10
    python3 -m music_cli track <uuid>
    python3 -m music_cli stream <uuid> --quality high
    python3 -m music_cli play <uuid>
    python3 -m music_cli playlist create --name "我的歌单"
    python3 -m music_cli playlist add <playlist-uuid> <track-uuid>

所有命令默认输出 JSON（便于 Agent 解析），加 --pretty 可读性输出。
token 自动存 ~/.music_cli_token，下次自动使用。
"""

import json
import os
import sys
import uuid

import click
import requests

TOKEN_FILE = os.path.expanduser("~/.music_cli_token")
DEFAULT_BASE_URL = "http://111.230.155.174"
TIMEOUT = 15


# ---------- 基础工具 ----------

def load_token() -> str | None:
    """从 ~/.music_cli_token 读取保存的 token。"""
    try:
        with open(TOKEN_FILE, "r", encoding="utf-8") as f:
            t = f.read().strip()
            return t or None
    except OSError:
        return None


def save_token(token: str) -> None:
    """保存 token 到 ~/.music_cli_token（0600 权限）。"""
    with open(TOKEN_FILE, "w", encoding="utf-8") as f:
        f.write(token)
    try:
        os.chmod(TOKEN_FILE, 0o600)
    except OSError:
        pass


def clear_token() -> None:
    try:
        os.remove(TOKEN_FILE)
    except OSError:
        pass


def emit(data, pretty: bool) -> None:
    """统一输出 JSON。"""
    if pretty:
        click.echo(json.dumps(data, indent=2, ensure_ascii=False))
    else:
        click.echo(json.dumps(data, ensure_ascii=False))


def fail(message: str, pretty: bool, hint: str = "") -> None:
    out = {"ok": False, "error": message}
    if hint:
        out["hint"] = hint
    emit(out, pretty)
    sys.exit(1)


def check_uuid(value: str, pretty: bool) -> str:
    """后端 track/playlist id 必须是 UUIDv4。"""
    try:
        u = uuid.UUID(value, version=4)
        if str(u) != value.lower():
            raise ValueError
        return value
    except ValueError:
        fail(f"ID 格式错误：{value} 不是合法的 UUIDv4", pretty,
             hint="先用 search/feed 拿到歌曲的 id（UUID 格式）再试")


class Api:
    """薄封装：处理 base-url、Bearer、信封 {code,message,data}。"""

    def __init__(self, base_url: str, token: str | None, pretty: bool):
        self.base = base_url.rstrip("/")
        self.token = token
        self.pretty = pretty
        self.session = requests.Session()
        self.session.headers["User-Agent"] = "music-cli/1.0"

    def _headers(self) -> dict:
        h = {"Content-Type": "application/json"}
        if self.token:
            h["Authorization"] = f"Bearer {self.token}"
        return h

    def request(self, method: str, path: str, *, params=None, body=None,
                allow_redirects=True):
        url = self.base + path
        try:
            resp = self.session.request(
                method, url, params=params, json=body,
                headers=self._headers(), timeout=TIMEOUT,
                allow_redirects=allow_redirects,
            )
        except requests.ConnectionError:
            fail(f"连接失败：{self.base} 不可达", self.pretty,
                 hint="检查服务器是否运行、防火墙是否放行 80 端口")
        except requests.Timeout:
            fail(f"请求超时（{TIMEOUT}s）：{method} {path}", self.pretty)
        except requests.RequestException as e:
            fail(f"网络错误：{e}", self.pretty)

        # stream 接口返回 302（不跟随则手动取 Location）
        if resp.status_code in (301, 302) and not allow_redirects:
            return {"redirect": resp.headers.get("Location")}

        if resp.status_code == 401:
            fail("未授权（401）：token 无效或已过期", self.pretty,
                 hint="重新运行 guest-login 或 sms-verify 获取新 token")
        if resp.status_code == 400:
            try:
                detail = resp.json()
            except ValueError:
                detail = resp.text[:200]
            fail(f"请求参数错误（400）：{detail}", self.pretty)
        if resp.status_code >= 500:
            fail(f"服务器错误（{resp.status_code}）", self.pretty,
                 hint="后端可能出问题了，稍后重试或看服务器日志")

        try:
            payload = resp.json()
        except ValueError:
            fail(f"服务器返回了非 JSON（{resp.status_code}）", self.pretty)

        # 信封 {code, message, data}
        if isinstance(payload, dict) and "code" in payload:
            if payload.get("code") != 0:
                fail(f"业务错误：{payload.get('message')}", self.pretty)
            return payload.get("data")
        return payload


# ---------- CLI 主体 ----------

@click.group()
@click.option("--base-url", default=DEFAULT_BASE_URL, show_default=True,
              help="后端地址")
@click.option("--token", default=None, help="Bearer token（不填则用保存的）")
@click.option("--pretty/--no-pretty", default=False, help="格式化 JSON 输出")
@click.pass_context
def cli(ctx, base_url, token, pretty):
    """music-cli：音乐平台后端的命令行 harness。"""
    ctx.ensure_object(dict)
    tok = token or load_token()
    ctx.obj["api"] = Api(base_url, tok, pretty)
    ctx.obj["pretty"] = pretty
    ctx.obj["has_token"] = bool(tok)


def _api(ctx) -> Api:
    return ctx.obj["api"]


def _pretty(ctx) -> bool:
    return ctx.obj["pretty"]


def _need_token(ctx):
    if not ctx.obj["has_token"]:
        fail("此命令需要登录", _pretty(ctx),
             hint="先运行 guest-login（游客）或 sms-verify（手机）获取 token")


# ---------- 健康检查 ----------

@cli.command()
@click.pass_context
def health(ctx):
    """检查后端健康状态（DB + Redis）。"""
    data = _api(ctx).request("GET", "/health")
    emit({"ok": True, "data": data}, _pretty(ctx))


# ---------- 认证 ----------

@cli.command(name="guest-login")
@click.pass_context
def guest_login(ctx):
    """游客登录（无需手机号），token 自动保存。"""
    api = _api(ctx)
    data = api.request("POST", "/auth/guest")
    if isinstance(data, dict) and data.get("accessToken"):
        save_token(data["accessToken"])
    emit({"ok": True, "data": data,
          "note": "accessToken 已保存到 ~/.music_cli_token"}, _pretty(ctx))


@cli.command(name="sms-send")
@click.argument("phone")
@click.pass_context
def sms_send(ctx, phone):
    """发送短信验证码。AUTH_MOCK=true 时验证码为 123456。"""
    if len(phone) != 11 or not phone.isdigit():
        fail("手机号必须是 11 位数字", _pretty(ctx))
    data = _api(ctx).request("POST", "/auth/sms/send", body={"phone": phone})
    emit({"ok": True, "data": data}, _pretty(ctx))


@cli.command(name="sms-verify")
@click.argument("phone")
@click.argument("code")
@click.pass_context
def sms_verify(ctx, phone, code):
    """校验短信验证码并登录，token 自动保存。"""
    data = _api(ctx).request(
        "POST", "/auth/sms/verify", body={"phone": phone, "code": code})
    if isinstance(data, dict) and data.get("accessToken"):
        save_token(data["accessToken"])
    emit({"ok": True, "data": data,
          "note": "accessToken 已保存到 ~/.music_cli_token"}, _pretty(ctx))


@cli.command()
@click.option("--refresh-token", default=None, help="refreshToken（不填则只清本地）")
@click.pass_context
def logout(ctx, refresh_token):
    """登出（吊销 refreshToken 并清除本地 token）。"""
    _need_token(ctx)
    api = _api(ctx)
    if refresh_token:
        try:
            api.request("POST", "/auth/logout",
                        body={"refreshToken": refresh_token})
        except SystemExit:
            pass  # 登出失败也不阻塞本地清理
    clear_token()
    emit({"ok": True, "message": "已登出，本地 token 已清除"}, _pretty(ctx))


@cli.command(name="delete-account")
@click.option("--yes", is_flag=True, help="确认注销（不可恢复）")
@click.pass_context
def delete_account(ctx, yes):
    """注销账号（软删除 + 吊销全部 token，Apple 审核要求）。"""
    _need_token(ctx)
    if not yes:
        fail("注销账号不可恢复，请加 --yes 确认", _pretty(ctx))
    data = _api(ctx).request("DELETE", "/account")
    clear_token()
    emit({"ok": True, "data": data, "message": "账号已注销"}, _pretty(ctx))


# ---------- 音乐 ----------

@cli.command()
@click.option("--page", default=1, show_default=True, type=int)
@click.option("--page-size", default=10, show_default=True, type=int)
@click.pass_context
def feed(ctx, page, page_size):
    """推荐 feed（公开接口）。"""
    data = _api(ctx).request(
        "GET", "/music/feed", params={"page": page, "pageSize": page_size})
    emit({"ok": True, "data": data}, _pretty(ctx))


@cli.command()
@click.argument("keyword")
@click.option("--page", default=1, show_default=True, type=int)
@click.option("--page-size", default=10, show_default=True, type=int)
@click.pass_context
def search(ctx, keyword, page, page_size):
    """搜索歌曲（公开接口）。"""
    keyword = keyword.strip()
    if not keyword:
        fail("搜索关键词不能为空", _pretty(ctx))
    data = _api(ctx).request(
        "GET", "/music/search",
        params={"q": keyword, "page": page, "pageSize": page_size})
    emit({"ok": True, "data": data}, _pretty(ctx))


@cli.command()
@click.argument("track_id")
@click.pass_context
def track(ctx, track_id):
    """歌曲详情（公开接口，id 必须为 UUIDv4）。"""
    check_uuid(track_id, _pretty(ctx))
    data = _api(ctx).request("GET", f"/music/track/{track_id}")
    emit({"ok": True, "data": data}, _pretty(ctx))


@cli.command()
@click.argument("track_id")
@click.pass_context
def lyrics(ctx, track_id):
    """歌词（公开接口，id 必须为 UUIDv4）。"""
    check_uuid(track_id, _pretty(ctx))
    data = _api(ctx).request("GET", f"/music/track/{track_id}/lyrics")
    emit({"ok": True, "data": data}, _pretty(ctx))


@cli.command()
@click.argument("track_id")
@click.option("--quality", default="standard",
              type=click.Choice(["standard", "high", "lossless", "hires"]),
              show_default=True, help="音质档")
@click.pass_context
def stream(ctx, track_id, quality):
    """取播放链接（302 跳转到 COS 预签名 URL，有过期时间，每次现取）。"""
    check_uuid(track_id, _pretty(ctx))
    result = _api(ctx).request(
        "GET", f"/music/track/{track_id}/stream",
        params={"quality": quality}, allow_redirects=False)
    emit({"ok": True, "quality": quality, **result}, _pretty(ctx))


@cli.command()
@click.argument("track_id")
@click.option("--quality", default=None, help="音质档（可选）")
@click.pass_context
def play(ctx, track_id, quality):
    """上报播放统计（需登录；防刷：自然日去重）。"""
    _need_token(ctx)
    check_uuid(track_id, _pretty(ctx))
    body = {"quality": quality} if quality else {}
    data = _api(ctx).request("POST", f"/music/track/{track_id}/play", body=body)
    emit({"ok": True, "data": data}, _pretty(ctx))


# ---------- 歌单 ----------

@cli.group()
def playlist():
    """歌单管理（需登录）。"""


@playlist.command(name="create")
@click.option("--name", required=True, help="歌单名")
@click.option("--cover-url", default=None, help="封面 URL（可选）")
@click.option("--public/--private", "is_public", default=True,
              help="是否公开（默认公开）")
@click.pass_context
def playlist_create(ctx, name, cover_url, is_public):
    """创建歌单。"""
    _need_token(ctx)
    body = {"title": name, "isPublic": is_public}
    if cover_url:
        body["coverUrl"] = cover_url
    data = _api(ctx).request("POST", "/playlists", body=body)
    emit({"ok": True, "data": data}, _pretty(ctx))


@playlist.command(name="detail")
@click.argument("playlist_id")
@click.pass_context
def playlist_detail(ctx, playlist_id):
    """歌单详情（含歌曲列表）。"""
    _need_token(ctx)
    check_uuid(playlist_id, _pretty(ctx))
    data = _api(ctx).request("GET", f"/playlists/{playlist_id}")
    emit({"ok": True, "data": data}, _pretty(ctx))


@playlist.command(name="add")
@click.argument("playlist_id")
@click.argument("track_id")
@click.pass_context
def playlist_add(ctx, playlist_id, track_id):
    """向歌单加歌。"""
    _need_token(ctx)
    check_uuid(playlist_id, _pretty(ctx))
    check_uuid(track_id, _pretty(ctx))
    data = _api(ctx).request(
        "POST", f"/playlists/{playlist_id}/tracks",
        body={"trackId": track_id})
    emit({"ok": True, "data": data}, _pretty(ctx))


@playlist.command(name="list")
@click.pass_context
def playlist_list(ctx):
    """（后端暂无此接口）"""
    fail("后端暂无「我的歌单列表」接口", _pretty(ctx),
         hint="用 playlist create 建歌单后，自行保存返回的 id；再用 playlist detail 查看")


def main():
    cli(obj={})


if __name__ == "__main__":
    main()
