#!/usr/bin/env python3
"""歌曲元数据爬虫（仅元数据，不碰音频，尊重版权）。

数据源：
  itunes  - Apple iTunes Search API（公开、无需 key），用 requests 拉取
  html    - 任意音乐详情页 HTML，用 Scrapling Selector 解析
            OpenGraph / music:* meta 标签 + 常见 CSS 选择器

用法：
  python3 crawl-metadata.py --source itunes --query "陈粒" --limit 10 --out out.json
  python3 crawl-metadata.py --source html --url "https://example.com/song/1" --out out.json

输出 JSON 数组，每项：
  {title, artist, album, coverUrl, durationMs, genre, source, sourceId}
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.parse


ITUNES_API = "https://itunes.apple.com/search"
MUSICBRAINZ_API = "https://musicbrainz.org/ws/2/recording/"
MB_UA = "MusicMetaBot/1.0 (music-platform metadata crawler)"


def crawl_musicbrainz(query: str, limit: int) -> list[dict]:
    """MusicBrainz 公开 API（CC0 元数据），中文曲库覆盖好。"""
    import requests

    out: list[dict] = []
    seen: set[str] = set()
    offset = 0
    per = min(limit, 100)
    # 失败重试
    while len(out) < limit:
        params = {
            "query": query,
            "fmt": "json",
            "limit": min(per, limit - len(out)),
            "offset": offset,
        }
        last_err: Exception | None = None
        for attempt in range(3):
            try:
                resp = requests.get(
                    MUSICBRAINZ_API,
                    params=params,
                    headers={"User-Agent": MB_UA},
                    timeout=20,
                )
                resp.raise_for_status()
                data = resp.json()
                break
            except Exception as e:  # noqa: BLE001
                last_err = e
                time.sleep(2 ** attempt)
        else:
            raise RuntimeError(f"MusicBrainz 请求失败(3次): {last_err}")

        recordings = data.get("recordings", [])
        if not recordings:
            break
        for rec in recordings:
            mbid = rec.get("id", "")
            if not mbid or mbid in seen:
                continue
            seen.add(mbid)
            artists = rec.get("artist-credit", [])
            artist = " / ".join(
                a.get("name", "") for a in artists if a.get("name")
            ).strip() or None
            releases = rec.get("releases", [])
            album = releases[0].get("title") if releases else None
            # 封面：Cover Art Archive（release MBID）
            cover = None
            if releases and releases[0].get("id"):
                cover = (
                    f"https://coverartarchive.org/release/"
                    f"{releases[0]['id']}/front-250"
                )
            out.append(
                {
                    "title": (rec.get("title") or "").strip(),
                    "artist": artist,
                    "album": album,
                    "coverUrl": cover,
                    "durationMs": int(rec.get("length") or 0),
                    "genre": None,
                    "source": "musicbrainz",
                    "sourceId": mbid,
                }
            )
            if len(out) >= limit:
                break
        offset += len(recordings)
        # 遵守 MusicBrainz 速率限制（1 req/s）
        time.sleep(1.1)
    return [i for i in out if i["title"] and i["artist"]]


def crawl_itunes(query: str, limit: int) -> list[dict]:
    import requests

    params = {
        "term": query,
        "media": "music",
        "entity": "song",
        "limit": max(1, min(limit, 200)),
        "country": "CN",
        "lang": "zh_cn",
    }
    # 失败重试 3 次，指数退避
    last_err: Exception | None = None
    for attempt in range(3):
        try:
            resp = requests.get(ITUNES_API, params=params, timeout=20)
            resp.raise_for_status()
            data = resp.json()
            break
        except Exception as e:  # noqa: BLE001
            last_err = e
            time.sleep(2 ** attempt)
    else:
        raise RuntimeError(f"iTunes API 请求失败(3次): {last_err}")

    out: list[dict] = []
    for r in data.get("results", []):
        if r.get("wrapperType") != "track" or r.get("kind") != "song":
            continue
        # artworkUrl100 -> 600x600 高清封面
        art = (r.get("artworkUrl100") or "").replace("100x100bb", "600x600bb")
        out.append(
            {
                "title": (r.get("trackName") or "").strip(),
                "artist": (r.get("artistName") or "").strip(),
                "album": (r.get("collectionName") or "").strip() or None,
                "coverUrl": art or None,
                "durationMs": int(r.get("trackTimeMillis") or 0),
                "genre": r.get("primaryGenreName"),
                "source": "itunes",
                "sourceId": str(r.get("trackId") or ""),
            }
        )
    # 去重（同 sourceId）
    seen: set[str] = set()
    uniq: list[dict] = []
    for item in out:
        if item["sourceId"] and item["sourceId"] not in seen:
            seen.add(item["sourceId"])
            uniq.append(item)
    return [i for i in uniq if i["title"] and i["artist"]]


def crawl_html(url: str) -> list[dict]:
    """用 Scrapling 解析单个音乐详情页的元信息。"""
    from scrapling import Selector
    import requests

    resp = requests.get(
        url,
        timeout=20,
        headers={"User-Agent": "Mozilla/5.0 (compatible; MusicMetaBot/1.0)"},
    )
    resp.raise_for_status()
    sel = Selector(resp.text)

    def meta(prop: str) -> str | None:
        v = sel.css(f'meta[property="{prop}"]::attr(content)').get()
        return v.strip() if v else None

    title = (
        meta("og:title")
        or meta("music:title")
        or sel.css("h1::text").get(default="").strip()
        or None
    )
    artist = (
        meta("music:musician")
        or meta("og:audio:artist")
        or sel.css('[itemprop="byArtist"]::text').get(default="").strip()
        or None
    )
    cover = meta("og:image")
    if not title:
        raise RuntimeError("页面中未解析到标题(og:title/h1)，换个 URL 试试")
    return [
        {
            "title": title,
            "artist": artist,
            "album": meta("music:album") or meta("og:album"),
            "coverUrl": cover,
            "durationMs": 0,
            "genre": None,
            "source": "html",
            "sourceId": url,
        }
    ]


def main() -> int:
    ap = argparse.ArgumentParser(description="歌曲元数据爬虫（仅元数据）")
    ap.add_argument(
        "--source", choices=["itunes", "musicbrainz", "html"], default="itunes"
    )
    ap.add_argument("--query", default="", help="itunes 搜索关键词")
    ap.add_argument("--url", default="", help="html 模式的目标页面 URL")
    ap.add_argument("--limit", type=int, default=20, help="itunes 返回条数上限")
    ap.add_argument("--out", default="", help="输出 JSON 文件（不填则打到 stdout）")
    args = ap.parse_args()

    if args.source == "itunes" and not args.query:
        print("错误：itunes 模式需要 --query", file=sys.stderr)
        return 2
    if args.source == "html" and not args.url:
        print("错误：html 模式需要 --url", file=sys.stderr)
        return 2
    if args.url and not args.url.startswith(("http://", "https://")):
        print("错误：--url 必须是 http(s) 链接", file=sys.stderr)
        return 2

    try:
        if args.source == "itunes":
            items = crawl_itunes(args.query, args.limit)
        elif args.source == "musicbrainz":
            items = crawl_musicbrainz(args.query, args.limit)
        else:
            items = crawl_html(args.url)
    except Exception as e:  # noqa: BLE001
        print(f"爬取失败：{e}", file=sys.stderr)
        return 1

    payload = {
        "source": args.source,
        "query": args.query or args.url,
        "crawledAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "count": len(items),
        "items": items,
    }
    text = json.dumps(payload, ensure_ascii=False, indent=2)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"已写入 {args.out}，共 {len(items)} 条", file=sys.stderr)
    else:
        print(text)
    return 0


if __name__ == "__main__":
    # 防止 query 中的中文被 shell 误处理
    sys.exit(main())
