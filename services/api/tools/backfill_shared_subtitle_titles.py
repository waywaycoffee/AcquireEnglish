#!/usr/bin/env python3
"""Backfill title + preview_zh on shared_bilibili_subtitles.

Sources (in order):
1. Existing UserLinkCourse.title for matching BV/page
2. Bilibili view API (title · 分P part)
3. Always refresh preview_zh from Chinese (or English) SRT cues

Run on ECS:

  cd /opt/acquireenglish/services/api
  PYTHONPATH=. .venv/bin/python tools/backfill_shared_subtitle_titles.py
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

_API_ROOT = Path(__file__).resolve().parents[1]
if (_API_ROOT / "app" / "database.py").is_file():
    sys.path.insert(0, str(_API_ROOT))

import httpx  # noqa: E402
from sqlalchemy import select  # noqa: E402

from app.config import settings  # noqa: E402
from app.database import SessionLocal  # noqa: E402
from app.db_migrate import ensure_schema_columns  # noqa: E402
from app.database import engine  # noqa: E402
from app.link_import import _bilibili_headers  # noqa: E402
from app.models import SharedBilibiliSubtitle, UserLinkCourse  # noqa: E402
from app.shared_subtitle_store import (  # noqa: E402
    parse_bvid_page,
    preview_zh_from_srt,
)


async def _ensure_columns() -> None:
    async with engine.begin() as conn:
        await ensure_schema_columns(conn)


def _title_from_personal(rows: list[UserLinkCourse], bvid: str, page: int) -> str:
    for row in rows:
        if (row.source or "").lower() != "bilibili":
            continue
        eid_bvid, eid_page = parse_bvid_page(row.external_id)
        if eid_bvid.upper() != bvid.upper() or eid_page != page:
            continue
        title = (row.title or "").strip()
        if title:
            return title[:512]
    return ""


async def _fetch_bili_titles(
    client: httpx.AsyncClient, bvids: list[str]
) -> dict[str, dict[int, str]]:
    """bvid -> {page: 'title · part'}"""
    out: dict[str, dict[int, str]] = {}
    for bvid in bvids:
        try:
            resp = await client.get(
                "https://api.bilibili.com/x/web-interface/view",
                params={"bvid": bvid},
            )
            root = resp.json()
            if root.get("code") != 0:
                print(f"BILI miss {bvid}: {root.get('message')}")
                continue
            data = root.get("data") or {}
            base = (data.get("title") or "").strip() or bvid
            pages = data.get("pages") if isinstance(data.get("pages"), list) else []
            mapping: dict[int, str] = {}
            for page_row in pages:
                if not isinstance(page_row, dict):
                    continue
                p = int(page_row.get("page") or 0)
                if p < 1:
                    continue
                part = str(page_row.get("part") or "").strip()
                title = base
                if part and part not in title:
                    title = f"{title} · {part}"
                mapping[p] = title[:512]
            if not mapping:
                mapping[1] = base[:512]
            out[bvid.upper()] = mapping
            await asyncio.sleep(0.15)
        except Exception as exc:  # noqa: BLE001
            print(f"BILI error {bvid}: {exc}")
    return out


async def main() -> None:
    await _ensure_columns()
    updated = 0
    async with SessionLocal() as db:
        packs = (
            await db.execute(select(SharedBilibiliSubtitle).order_by(SharedBilibiliSubtitle.id))
        ).scalars().all()
        personal = (await db.execute(select(UserLinkCourse))).scalars().all()
        need_bili = sorted(
            {
                (r.bvid or "").upper()
                for r in packs
                if (r.bvid or "").startswith("BV")
                and not (r.title or "").strip()
                and not _title_from_personal(personal, r.bvid, int(r.page or 1))
            }
        )
        bili_map: dict[str, dict[int, str]] = {}
        if need_bili:
            headers = _bilibili_headers(getattr(settings, "bilibili_cookie", "") or "")
            async with httpx.AsyncClient(
                headers=headers, timeout=25.0, follow_redirects=True
            ) as client:
                bili_map = await _fetch_bili_titles(client, need_bili)

        for row in packs:
            page = int(row.page or 1)
            title = (row.title or "").strip()
            if not title:
                title = _title_from_personal(personal, row.bvid, page)
            if not title:
                title = (bili_map.get((row.bvid or "").upper()) or {}).get(page, "")
            preview = preview_zh_from_srt(row.subtitle_zh_srt)
            if not preview:
                preview = preview_zh_from_srt(row.subtitle_en_srt)
            dirty = False
            if title and title != (row.title or "").strip():
                row.title = title[:512]
                dirty = True
            if preview and preview != (row.preview_zh or "").strip():
                row.preview_zh = preview[:512]
                dirty = True
            if dirty:
                updated += 1
                print(f"OK {row.bvid} p{page}: {(row.title or '')[:40]} | {(row.preview_zh or '')[:40]}")
        await db.commit()
    print(f"DONE updated={updated} total={len(packs)}")


if __name__ == "__main__":
    asyncio.run(main())
