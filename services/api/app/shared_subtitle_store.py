"""Upsert helpers for the shared Bilibili softsub cache."""

from __future__ import annotations

import re
from dataclasses import dataclass

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import SharedBilibiliSubtitle, UserLinkCourse
from app.shared_subtitle_quality import evaluate_shared_pack, parse_srt_cues


@dataclass(frozen=True)
class SharedUpsertResult:
    stored: bool
    replaced: bool = False
    quality_score: float = 0.0
    cue_count: int = 0
    reason: str = ""


def normalize_bvid(raw: str) -> str:
    """Preserve Bilibili BV case.

    The view/playurl APIs are case-sensitive; uppercasing can 404 or (worse)
    resolve a different稿件. Only normalize the ``BV`` prefix.
    """
    value = (raw or "").strip()
    if not value:
        return ""
    if len(value) >= 2 and value[:2].upper() == "BV":
        return "BV" + value[2:]
    return value


def parse_bvid_page(external_id: str) -> tuple[str, int]:
    eid = (external_id or "").strip()
    match = re.match(r"^(BV[0-9A-Za-z]+)(?:-p(\d+))?$", eid, re.I)
    if not match:
        return normalize_bvid(eid), 1
    return normalize_bvid(match.group(1)), int(match.group(2) or 1)


def personal_external_id(bvid: str, page: int = 1) -> str:
    """Match ``link_import`` / App personal asset keys (``BV…`` or ``BV…-pN``)."""
    key = normalize_bvid(bvid)
    if page <= 1:
        return key
    return f"{key}-p{int(page)}"


def personal_external_id_aliases(bvid: str, page: int = 1) -> list[str]:
    """Canonical + padded variants so older personal rows still match."""
    key = normalize_bvid(bvid)
    page = int(page or 1)
    aliases: list[str] = []
    if page <= 1:
        aliases.extend([key, f"{key}-p1", f"{key}-p01"])
    else:
        aliases.extend([f"{key}-p{page}", f"{key}-p{page:02d}"])
    out: list[str] = []
    for item in aliases:
        if item and item not in out:
            out.append(item)
    return out


def bilibili_watch_url(bvid: str, page: int = 1) -> str:
    key = normalize_bvid(bvid)
    url = f"https://www.bilibili.com/video/{key}"
    if int(page or 1) > 1:
        url = f"{url}?p={int(page)}"
    return url


def preview_zh_from_srt(zh_srt: str | None, *, max_cues: int = 2, max_chars: int = 160) -> str:
    """First 1–2 Chinese cue bodies for list identity."""
    cues = parse_srt_cues(zh_srt or "")
    if not cues:
        return ""
    bodies: list[str] = []
    for _, _, body in cues[: max(1, max_cues)]:
        text = re.sub(r"\s+", " ", (body or "").strip())
        if text:
            bodies.append(text)
    if not bodies:
        return ""
    joined = " · ".join(bodies)
    if len(joined) <= max_chars:
        return joined
    return joined[: max_chars - 1].rstrip() + "…"


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


def _apply_identity(
    row: SharedBilibiliSubtitle,
    *,
    title: str | None,
    zh_srt: str | None,
) -> None:
    cleaned = (title or "").strip()
    if cleaned:
        row.title = cleaned[:512]
    preview = preview_zh_from_srt(zh_srt)
    if preview:
        row.preview_zh = preview[:512]
    elif not (row.preview_zh or "").strip():
        # Fall back to English first cue so EN-only packs still show something.
        en_cues = parse_srt_cues(row.subtitle_en_srt or "")
        if en_cues:
            row.preview_zh = re.sub(r"\s+", " ", en_cues[0][2]).strip()[:512]


async def get_shared_bilibili_pack(
    db: AsyncSession,
    *,
    bvid: str,
    page: int = 1,
) -> SharedBilibiliSubtitle | None:
    key = normalize_bvid(bvid)
    if not key:
        return None
    page_no = int(page or 1)
    # Exact first (common path), then CI for legacy all-upper rows.
    result = await db.execute(
        select(SharedBilibiliSubtitle).where(
            SharedBilibiliSubtitle.bvid == key,
            SharedBilibiliSubtitle.page == page_no,
        )
    )
    row = result.scalar_one_or_none()
    if row is not None:
        return row
    result = await db.execute(
        select(SharedBilibiliSubtitle).where(
            func.upper(SharedBilibiliSubtitle.bvid) == key.upper(),
            SharedBilibiliSubtitle.page == page_no,
        )
    )
    legacy = result.scalar_one_or_none()
    if legacy is not None and legacy.bvid != key:
        legacy.bvid = key
    return legacy


async def upsert_shared_bilibili_pack(
    db: AsyncSession,
    *,
    bvid: str,
    page: int = 1,
    cid: int | None = None,
    duration_sec: int | None = None,
    subtitle_en_srt: str,
    subtitle_zh_srt: str | None = None,
    title: str | None = None,
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
    if existing is None:
        result = await db.execute(
            select(SharedBilibiliSubtitle).where(
                func.upper(SharedBilibiliSubtitle.bvid) == key.upper(),
                SharedBilibiliSubtitle.page == page,
            )
        )
        existing = result.scalar_one_or_none()
        if existing is not None and existing.bvid != key:
            existing.bvid = key
    new_has_zh = bool(zh)

    if existing is None:
        row = SharedBilibiliSubtitle(
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
        _apply_identity(row, title=title, zh_srt=zh)
        db.add(row)
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
        # Still enrich identity when a better pack already exists.
        dirty = False
        cleaned = (title or "").strip()
        if cleaned and not (existing.title or "").strip():
            existing.title = cleaned[:512]
            dirty = True
        if zh and not (existing.preview_zh or "").strip():
            preview = preview_zh_from_srt(zh)
            if preview:
                existing.preview_zh = preview[:512]
                dirty = True
        if dirty and commit:
            await db.commit()
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
    _apply_identity(
        existing,
        title=title or existing.title,
        zh_srt=existing.subtitle_zh_srt,
    )
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
    title: str | None = None,
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
        title=title,
        uploader_user_id=uploader_user_id,
        source_origin=source_origin,
        commit=True,
    )


async def fanout_gpu_pack_to_personal(
    db: AsyncSession,
    *,
    bvid: str,
    page: int = 1,
    subtitle_en_srt: str,
    subtitle_zh_srt: str | None,
    title: str | None = None,
    duration_sec: int | None = None,
    requester_user_ids: list[int] | None = None,
    commit: bool = True,
) -> int:
    """Write GPU EN/ZH into private libraries: requesters + existing BV owners.

    Shared cache must already be upserted by the caller. Returns how many
    ``UserLinkCourse`` rows were created or refreshed.
    """
    en = (subtitle_en_srt or "").strip()
    if len(en) < 20:
        return 0
    zh = (subtitle_zh_srt or "").strip() or None
    key = normalize_bvid(bvid)
    page = int(page or 1)
    eid = personal_external_id(key, page)
    aliases = personal_external_id_aliases(key, page)
    watch = bilibili_watch_url(key, page)
    duration = int(duration_sec or 0) or 60
    cleaned_title = (title or "").strip() or key

    user_ids: list[int] = []
    for raw in requester_user_ids or []:
        try:
            uid = int(raw)
        except (TypeError, ValueError):
            continue
        if uid > 0 and uid not in user_ids:
            user_ids.append(uid)

    existing = await db.execute(
        select(UserLinkCourse).where(
            UserLinkCourse.source == "bilibili",
            or_(
                *[
                    UserLinkCourse.external_id == alias
                    for alias in aliases
                ]
            ),
        )
    )
    rows = list(existing.scalars().all())
    for row in rows:
        if row.user_id not in user_ids:
            user_ids.append(row.user_id)

    if not user_ids:
        return 0

    by_user: dict[int, UserLinkCourse] = {}
    for row in rows:
        # Prefer the canonical external_id when a user somehow has aliases.
        prev = by_user.get(row.user_id)
        if prev is None or row.external_id == eid:
            by_user[row.user_id] = row

    touched = 0
    for uid in user_ids:
        row = by_user.get(uid)
        if row is None:
            row = UserLinkCourse(
                user_id=uid,
                source="bilibili",
                external_id=eid,
                title=cleaned_title[:512],
                author=None,
                watch_url=watch,
                duration_sec=duration,
                subtitle_en_srt=en,
                subtitle_zh_srt=zh,
            )
            db.add(row)
            touched += 1
            continue
        if cleaned_title and (
            not (row.title or "").strip() or row.title == row.external_id
        ):
            row.title = cleaned_title[:512]
        row.watch_url = watch or row.watch_url
        if duration_sec:
            row.duration_sec = duration
        row.subtitle_en_srt = en
        if zh:
            row.subtitle_zh_srt = zh
        if row.external_id != eid and row.external_id in aliases:
            # Normalize alias keys to the App/link_import form.
            row.external_id = eid
        touched += 1

    if commit and touched:
        await db.commit()
    return touched
