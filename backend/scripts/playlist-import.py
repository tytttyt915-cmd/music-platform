#!/usr/bin/env python3
"""歌单导入爬虫：网易云/QQ 音乐歌单链接 → 歌曲清单 JSON。

用法：
    python playlist-import.py "https://music.163.com/playlist?id=123456"
    # 输出：playlist_123456.json（含歌单名、歌曲列表）

只爬公开元数据（歌名/歌手/专辑/封面），不碰音频。
"""
import json
import re
import sys


def import_netease_playlist(url: str) -> dict:
    from scrapling import Fetcher

    m = re.search(r"id=(\d+)", url)
    if not m:
        raise ValueError("链接中没有 playlist id")
    playlist_id = m.group(1)

    # 网易云歌单页是 SSR，直出 HTML，普通 Fetcher 够用
    page = Fetcher.get(
        f"https://music.163.com/playlist?id={playlist_id}",
        impersonate="chrome124",
        stealthy_headers=True,
    )

    name = page.css("h2.f-ff2::text").get("").strip() or f"网易云歌单 {playlist_id}"
    # 歌曲列表在 <ul class="f-hide"> 里
    songs = []
    for a in page.css("ul.f-hide a"):
        href = a.attrib.get("href", "")
        sm = re.search(r"id=(\d+)", href)
        if not sm:
            continue
        text = a.css("::text").get("").strip()
        # 文本格式通常是 "歌名 - 歌手" 或只有歌名
        title, _, artist = text.partition(" - ")
        songs.append({
            "platform": "netease",
            "platform_id": sm.group(1),
            "title": title.strip(),
            "artist": artist.strip(),
        })
    return {
        "platform": "netease",
        "playlist_id": playlist_id,
        "name": name,
        "songs": songs,
    }


def import_qq_playlist(url: str) -> dict:
    from scrapling import StealthyFetcher

    m = re.search(r"id=(\d+)", url)
    playlist_id = m.group(1) if m else "unknown"
    # QQ 音乐歌单页是 CSR，必须等 JS 渲染
    page = StealthyFetcher.fetch(url, impersonate="chrome124", wait=3000)
    name = page.css("h1.data__name_txt::text").get("").strip() or f"QQ歌单 {playlist_id}"
    songs = []
    for li in page.css("ul.songlist__list li"):
        title = li.css(".songlist__songname_txt a::text").get("").strip()
        artist = li.css(".songlist__artist a::text").get("").strip()
        if title:
            songs.append({
                "platform": "qq",
                "platform_id": "",
                "title": title,
                "artist": artist,
            })
    return {
        "platform": "qq",
        "playlist_id": playlist_id,
        "name": name,
        "songs": songs,
    }


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python playlist-import.py <歌单链接>", file=sys.stderr)
        sys.exit(1)
    url = sys.argv[1]
    if "music.163.com" in url:
        result = import_netease_playlist(url)
    elif "y.qq.com" in url:
        result = import_qq_playlist(url)
    else:
        print("不支持的链接（仅支持 music.163.com / y.qq.com）", file=sys.stderr)
        sys.exit(1)
    out = f"playlist_{result['playlist_id']}.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(f"OK: {len(result['songs'])} 首 → {out}")
