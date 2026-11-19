"""Upsert helpers for the shared Bilibili softsub cache."""

from __future__ import annotations

import re
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import SharedBilibiliSubtitle
from app.shared_subtitle_quality import evaluate_shared_pack


@dataclass(frozen=True)
class SharedUpsertResult:
    stored: bool
    replaced: bool = False
    quality_score: float = 0.0
    cue_count: int = 0
    reason: str = ""


def normalize_bvid(raw: str) -> str:
    value = (raw or "").strip().upper()
    return value


def parse_bvid_page(external_id: str) -> tuple[str, int]:
    eid = (external_id or "").strip()
    match = re.match(r"^(BV[0-9A-Za-z]+)(?:-p(\d+))?$", eid, re.I)
    if not match:
        return normalize_bvid(eid), 1
    return match.group(1).upper(), int(match.group(2) or 1)


def should_replace_shared(
    existing: SharedBilibiliSubtitle,
    *,
    new_score: float,
    new_has_zh: bool,
) -> bool:
    old_score = float(existing.quality_score or 0.0)
    if new_score > old_score + 1e-9:
        return True
    if abs(new_score - old_score) <= 1e-9:
        old_has_zh = bool((existing.subtitle_zh_srt or "").strip())
        if new_has_zh and not old_has_zh:
            return True
    return False


async def upsert_shared_bilibili_pack(
    db: AsyncSession,
    *,
    bvid: str,
    page: int = 1,
    cid: int | None = None,
    duration_sec: int | None = None,
    subtitle_en_srt: str,
    subtitle_zh_srt: str | None = None,
    uploader_user_id: int | None = None,
    source_origin: str = "asr",
    commit: bool = True,
) -> SharedUpsertResult:
    key = normalize_bvid(bvid)
    if not key:
        return SharedUpsertResult(stored=False, reason="bvid required")

    origin = (source_origin or "asr").strip().lower()
    if origin not in {"asr", "official", "mixed"}:
        origin = "asr"

    en = (subtitle_en_srt or "").strip()
    zh = (subtitle_zh_srt or "").strip() or None
    if len(en) < 20:
        return SharedUpsertResult(stored=False, reason="英文字幕过短")

    quality = evaluate_shared_pack(
        en_srt=en,
        zh_srt=zh,
        duration_sec=duration_sec,
    )
    # Duration metadata from clients is often coarse (minutes*60); retry without
    # the coverage gate so otherwise-good packs still enter the shared cache.
    if not quality.passed and duration_sec is not None:
        quality = evaluate_shared_pack(en_srt=en, zh_srt=zh, duration_sec=None)
    if not quality.passed:
        return SharedUpsertResult(
            stored=False,
            quality_score=quality.score,
            cue_count=quality.cue_count,
            reason=quality.reason or "quality check failed",
        )

    result = await db.execute(
        select(SharedBilibiliSubtitle).where(
            SharedBilibiliSubtitle.bvid == key,
            SharedBilibiliSubtitle.page == page,
        )
    )
    existing = result.scalar_one_or_none()
    new_has_zh = bool(zh)

    if existing is None:
        db.add(
            SharedBilibiliSubtitle(
                bvid=key,
                page=page,
                cid=cid,
                duration_sec=duration_sec,
                subtitle_en_srt=en,
                subtitle_zh_srt=zh,
                quality_score=quality.score,
                cue_count=quality.cue_count,
                en_hits=quality.en_hits,
                zh_hits=quality.zh_hits,
                uploader_user_id=uploader_user_id,
                source_origin=origin,
            )
        )
        if commit:
            await db.commit()
        return SharedUpsertResult(
            stored=True,
            replaced=False,
            quality_score=quality.score,
            cue_count=quality.cue_count,
        )

    if not should_replace_shared(
        existing, new_score=quality.score, new_has_zh=new_has_zh
    ):
        return SharedUpsertResult(
            stored=False,
            replaced=False,
            quality_score=float(existing.quality_score or 0.0),
            cue_count=int(existing.cue_count or 0),
            reason="existing pack has equal or better quality",
        )

    existing.cid = cid or existing.cid
    existing.duration_sec = duration_sec or existing.duration_sec
    existing.subtitle_en_srt = en
    existing.subtitle_zh_srt = zh or existing.subtitle_zh_srt
    existing.quality_score = quality.score
    existing.cue_count = quality.cue_count
    existing.en_hits = quality.en_hits
    existing.zh_hits = quality.zh_hits
    if uploader_user_id is not None:
        existing.uploader_user_id = uploader_user_id
    existing.source_origin = origin
    if commit:
        await db.commit()
    return SharedUpsertResult(
        stored=True,
        replaced=True,
        quality_score=quality.score,
        cue_count=quality.cue_count,
    )


async def promote_personal_bilibili_to_shared(
    db: AsyncSession,
    *,
    external_id: str,
    subtitle_en_srt: str | None,
    subtitle_zh_srt: str | None,
    duration_sec: int | None,
    uploader_user_id: int | None,
    source_origin: str = "asr",
) -> SharedUpsertResult:
    en = (subtitle_en_srt or "").strip()
    if len(en) < 20:
        return SharedUpsertResult(stored=False, reason="no english")
    bvid, page = parse_bvid_page(external_id)
    if not bvid.startswith("BV"):
        return SharedUpsertResult(stored=False, reason="not a BV id")
    return await upsert_shared_bilibili_pack(
        db,
        bvid=bvid,
        page=page,
        duration_sec=duration_sec,
        subtitle_en_srt=en,
        subtitle_zh_srt=subtitle_zh_srt,
        uploader_user_id=uploader_user_id,
        source_origin=source_origin,
        commit=True,
    )
