#!/usr/bin/env python3
"""把 crawl-metadata.py 的 JSON 结果转成 SQL INSERT 文件。

用法：
  python3 import-metadata.py --in out.json --out import.sql
  # 然后在服务器上：
  docker exec -i $(docker ps -q --filter "name=postgres") \\
      psql -U music -d musicdb -f import.sql

说明：
  - 每条生成合法 UUIDv4 的 tracks 行（status='online'，无歌词/无音频源，
    仅元数据占位；音频需另行授权上传后补 track_sources）。
  - 按 (source, sourceId) 去重，避免重复导入（sourceId 存入 album 字段备注？
    不——用单独的外部幂等：ON CONFLICT DO NOTHING 依赖 id，重复跑会插重复行；
    因此脚本输出前按 (source, sourceId) 去重，跨文件去重请自行合并 JSON）。
"""
from __future__ import annotations

import argparse
import json
import sys
import uuid


def sql_str(v: str | None) -> str:
    if v is None:
        return "NULL"
    return "'" + v.replace("'", "''") + "'"


def main() -> int:
    ap = argparse.ArgumentParser(description="元数据 JSON -> SQL")
    ap.add_argument("--in", dest="inp", required=True, help="crawl-metadata.py 的输出 JSON")
    ap.add_argument("--out", dest="out", required=True, help="输出 SQL 文件")
    ap.add_argument(
        "--dry-run", action="store_true", help="只打印条数，不写文件"
    )
    args = ap.parse_args()

    with open(args.inp, encoding="utf-8") as f:
        payload = json.load(f)
    items = payload.get("items", [])
    # 按 (source, sourceId) 去重
    seen: set[tuple[str, str]] = set()
    uniq: list[dict] = []
    for it in payload.get("items", []):
        key = (str(it.get("source")), str(it.get("sourceId")))
        if key not in seen and it.get("title") and it.get("artist"):
            seen.add(key)
            uniq.append(it)

    if args.dry_run:
        print(f"可导入 {len(uniq)} 条（去重后）")
        return 0

    lines: list[str] = [
        "-- 由 import-metadata.py 生成",
        f"-- 来源：{payload.get('source')} / {payload.get('query')}",
        f"-- 共 {len(uniq)} 条",
        "BEGIN;",
    ]
    for it in uniq:
        tid = str(uuid.uuid4())
        title = str(it["title"])[:255]
        artist = str(it["artist"])[:255]
        album = str(it.get("album") or "")[:255] or None
        cover = it.get("coverUrl")
        duration = int(it.get("durationMs") or 0)
        lines.append(
            "INSERT INTO tracks (id, title, artist, album, cover_url, "
            "duration_ms, lrc_synced, status) VALUES ("
            f"{sql_str(tid)}, {sql_str(title)}, {sql_str(artist)}, "
            f"{sql_str(album)}, {sql_str(cover)}, {duration}, FALSE, 'online'"
            ") ON CONFLICT (id) DO NOTHING;"
        )
    lines.append("COMMIT;")
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"已生成 {args.out}，{len(uniq)} 条 INSERT", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
