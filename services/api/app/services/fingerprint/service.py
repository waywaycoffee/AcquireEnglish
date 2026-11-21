"""Fingerprint search, cache write, and private course copy helpers."""

from __future__ import annotations

import hashlib
import json
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import delete, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import (
    AssetCache,
    CacheHitLog,
    FingerprintIndex,
    SimhashBand,
    UploadTask,
    UserCourseAsset,
)
from app.services.fingerprint import embedding as emb
from app.services.fingerprint import simhash as sh
from app.services.fingerprint.asset_store import (
    delete_asset_blobs,
    read_json_blob,
    write_json_blob,
)

# Short-lived compute / negative caches (process-local).
_fp_compute_cache: dict[str, tuple[float, dict[str, Any]]] = {}
_fp_miss_cache: dict[str, float] = {}
_COMPUTE_TTL = 24 * 3600
_MISS_TTL = 600


def _now() -> datetime:
    return datetime.now(tz=timezone.utc)


def _new_id() -> str:
    return str(uuid.uuid4())


def _text_digest(text: str) -> str:
    return hashlib.sha256((text or "").encode("utf-8")).hexdigest()


def _loads_list(raw: str | None) -> list[Any]:
    if not raw:
        return []
    try:
        val = json.loads(raw)
        return val if isinstance(val, list) else []
    except json.JSONDecodeError:
        return []


def _dumps(obj: Any) -> str:
    return json.dumps(obj, ensure_ascii=False)


@dataclass
class FingerprintSearchResult:
    hit: bool
    asset_id: str | None = None
    fingerprint_id: str | None = None
    asset: AssetCache | None = None
    similar_blocks: int = 0
    cost_ms: int = 0
    degraded: bool = False  # vector store down → SimHash-only "疑似"
    message: str = ""
    candidates: list[str] = field(default_factory=list)


def _feature_enabled() -> bool:
    return bool(settings.fingerprint_cache_enabled)


async def _log_hit(
    db: AsyncSession,
    *,
    user_id: int | None,
    fingerprint_id: str | None,
    asset_cache_id: str | None,
    hit_result: str,
    cost_ms: int,
) -> None:
    db.add(
        CacheHitLog(
            user_id=int(user_id or 0),
            fingerprint_id=fingerprint_id,
            asset_cache_id=asset_cache_id,
            hit_result=hit_result,
            cost_ms=int(cost_ms),
        )
    )


async def _compute_features(cleaned_text: str) -> dict[str, Any]:
    digest = _text_digest(cleaned_text)
    cached = _fp_compute_cache.get(digest)
    now = time.time()
    if cached and now - cached[0] < _COMPUTE_TTL:
        return cached[1]

    max_blocks = int(settings.fingerprint_max_blocks or 64)
    block_chars = int(settings.fingerprint_block_chars or sh.DEFAULT_BLOCK_CHARS)
    blocks = sh.compute_simhash_blocks(
        cleaned_text, block_chars=block_chars, max_blocks=max_blocks
    )
    vector = await emb.embed_text(cleaned_text)
    payload = {
        "digest": digest,
        "simhash_blocks": blocks,
        "vector": vector,
        "text_length": len(cleaned_text or ""),
    }
    _fp_compute_cache[digest] = (now, payload)
    # Bound memory
    if len(_fp_compute_cache) > 256:
        oldest = sorted(_fp_compute_cache.items(), key=lambda kv: kv[1][0])[:64]
        for k, _ in oldest:
            _fp_compute_cache.pop(k, None)
    return payload


async def _band_recall(
    db: AsyncSession,
    *,
    bands_per_block: list[list[int]],
    source_type: str,
    text_length: int,
    len_ratio_max: float,
    candidate_cap: int = 200,
) -> set[str]:
    lo = max(0, int(text_length * (1.0 - len_ratio_max)))
    hi = int(text_length * (1.0 + len_ratio_max)) + 1
    asset_ids: set[str] = set()
    seen_queries: set[tuple[int, int]] = set()
    for bands in bands_per_block:
        for band_no, band_value in enumerate(bands):
            key = (band_no, int(band_value))
            if key in seen_queries:
                continue
            seen_queries.add(key)
            q = (
                select(SimhashBand.asset_id)
                .where(
                    SimhashBand.band_no == band_no,
                    SimhashBand.band_value == int(band_value),
                    SimhashBand.source_type == source_type,
                    SimhashBand.text_length >= lo,
                    SimhashBand.text_length <= hi,
                )
                .limit(80)
            )
            rows = (await db.execute(q)).scalars().all()
            asset_ids.update(str(a) for a in rows if a)
            if len(asset_ids) >= candidate_cap:
                return asset_ids
    return asset_ids


async def search_fingerprint(
    db: AsyncSession,
    *,
    cleaned_text: str,
    source_type: str = "pdf_text",
    user_id: int | None = None,
    skip_log: bool = False,
) -> FingerprintSearchResult:
    started = time.perf_counter()
    text = (cleaned_text or "").strip()
    source_type = (source_type or "pdf_text").strip().lower()

    if not _feature_enabled():
        return FingerprintSearchResult(
            hit=False,
            cost_ms=0,
            message="指纹缓存复用已关闭",
        )
    if len(text) < 80:
        return FingerprintSearchResult(
            hit=False,
            cost_ms=int((time.perf_counter() - started) * 1000),
            message="文本过短，无法计算指纹",
        )

    digest = _text_digest(text)
    miss_at = _fp_miss_cache.get(digest)
    if miss_at and time.time() - miss_at < _MISS_TTL:
        cost = int((time.perf_counter() - started) * 1000)
        if not skip_log:
            await _log_hit(
                db,
                user_id=user_id,
                fingerprint_id=None,
                asset_cache_id=None,
                hit_result="miss",
                cost_ms=cost,
            )
        return FingerprintSearchResult(
            hit=False,
            cost_ms=cost,
            message="近期检索未命中（负缓存）",
        )

    feats = await _compute_features(text)
    blocks: list[int] = feats["simhash_blocks"]
    vector: list[float] = feats["vector"]
    length: int = int(feats["text_length"])
    bands_per_block = [sh.to_bands(h) for h in blocks]

    sim_max = int(settings.fingerprint_sim_hamming_max)
    min_blocks = int(settings.fingerprint_min_similar_blocks)
    vec_min = float(settings.fingerprint_vec_score_min)
    len_ratio = float(settings.fingerprint_len_ratio_max)
    top_k = int(settings.fingerprint_top_k)

    cand_a = await _band_recall(
        db,
        bands_per_block=bands_per_block,
        source_type=source_type,
        text_length=length,
        len_ratio_max=len_ratio,
    )

    degraded = False
    cand_b: set[str] = set()
    if emb.vector_store_available():
        hits = emb.search_vectors(
            vector,
            source_type=source_type,
            limit=top_k,
            score_min=vec_min,
        )
        for h in hits:
            aid = (h.get("payload") or {}).get("asset_id")
            if aid:
                cand_b.add(str(aid))
    else:
        # 向量库不可用：仅 SimHash，命中降级为「疑似」不自动复用
        degraded = True

    cost_ms = int((time.perf_counter() - started) * 1000)

    if not cand_a:
        _fp_miss_cache[digest] = time.time()
        if not skip_log:
            await _log_hit(
                db,
                user_id=user_id,
                fingerprint_id=None,
                asset_cache_id=None,
                hit_result="miss",
                cost_ms=cost_ms,
            )
        return FingerprintSearchResult(
            hit=False,
            cost_ms=cost_ms,
            message="未找到匹配解析资产",
            candidates=[],
        )

    # Dual gate: intersection when vector path healthy; otherwise candidates
    # from SimHash only → degraded (do not auto-reuse).
    if degraded:
        if not skip_log:
            await _log_hit(
                db,
                user_id=user_id,
                fingerprint_id=None,
                asset_cache_id=None,
                hit_result="miss",
                cost_ms=cost_ms,
            )
        return FingerprintSearchResult(
            hit=False,
            cost_ms=cost_ms,
            degraded=True,
            candidates=sorted(cand_a)[:20],
            message="向量库不可用，仅 SimHash 疑似命中，请确认后手动复用",
        )

    cand = cand_a & cand_b
    if not cand:
        _fp_miss_cache[digest] = time.time()
        if not skip_log:
            await _log_hit(
                db,
                user_id=user_id,
                fingerprint_id=None,
                asset_cache_id=None,
                hit_result="miss",
                cost_ms=cost_ms,
            )
        return FingerprintSearchResult(
            hit=False,
            cost_ms=cost_ms,
            message="未找到匹配解析资产",
            candidates=sorted(cand_a | cand_b)[:20],
        )

    # Load fingerprints for candidates and score.
    best: tuple[str, str, int] | None = None  # asset_id, fp_id, similar_blocks
    fp_rows = (
        await db.execute(
            select(FingerprintIndex).where(
                FingerprintIndex.asset_id.in_(list(cand)),
                FingerprintIndex.is_valid.is_(True),
            )
        )
    ).scalars().all()

    for fp in fp_rows:
        fp_blocks = sh.parse_simhash_blocks(fp.simhash_blocks_json)
        similar = sh.count_similar_blocks(blocks, fp_blocks, sim_max)
        if similar < min_blocks:
            continue
        fp_len = max(1, int(fp.text_length or 1))
        if abs(length - fp_len) / fp_len > len_ratio:
            continue
        if best is None or similar > best[2]:
            best = (fp.asset_id, fp.id, similar)

    cost_ms = int((time.perf_counter() - started) * 1000)
    if best is None:
        _fp_miss_cache[digest] = time.time()
        if not skip_log:
            await _log_hit(
                db,
                user_id=user_id,
                fingerprint_id=None,
                asset_cache_id=None,
                hit_result="miss",
                cost_ms=cost_ms,
            )
        return FingerprintSearchResult(
            hit=False,
            cost_ms=cost_ms,
            message="未找到匹配解析资产",
            candidates=sorted(cand)[:20],
        )

    asset_id, fp_id, similar_n = best
    asset = (
        await db.execute(
            select(AssetCache).where(
                AssetCache.id == asset_id,
                AssetCache.is_ban.is_(False),
            )
        )
    ).scalar_one_or_none()
    if asset is None:
        _fp_miss_cache[digest] = time.time()
        if not skip_log:
            await _log_hit(
                db,
                user_id=user_id,
                fingerprint_id=fp_id,
                asset_cache_id=asset_id,
                hit_result="miss",
                cost_ms=cost_ms,
            )
        return FingerprintSearchResult(
            hit=False,
            cost_ms=cost_ms,
            message="匹配资产已下架",
        )

    asset.hit_count = int(asset.hit_count or 0) + 1
    asset.last_hit_at = _now()
    if not skip_log:
        await _log_hit(
            db,
            user_id=user_id,
            fingerprint_id=fp_id,
            asset_cache_id=asset_id,
            hit_result="hit",
            cost_ms=cost_ms,
        )
    _fp_miss_cache.pop(digest, None)
    return FingerprintSearchResult(
        hit=True,
        asset_id=asset_id,
        fingerprint_id=fp_id,
        asset=asset,
        similar_blocks=similar_n,
        cost_ms=cost_ms,
        message="检测到该教材已有解析资产，直接复用课程结构，无需重新分析",
    )


async def _write_bands(
    db: AsyncSession,
    *,
    fingerprint_id: str,
    asset_id: str,
    source_type: str,
    text_length: int,
    simhash_blocks: list[int],
) -> None:
    await db.execute(
        delete(SimhashBand).where(SimhashBand.fingerprint_id == fingerprint_id)
    )
    # Index unique bands across blocks to keep table lean.
    seen: set[tuple[int, int]] = set()
    for h in simhash_blocks:
        for band_no, band_value in enumerate(sh.to_bands(h)):
            key = (band_no, int(band_value))
            if key in seen:
                continue
            seen.add(key)
            db.add(
                SimhashBand(
                    fingerprint_id=fingerprint_id,
                    asset_id=asset_id,
                    band_no=band_no,
                    band_value=int(band_value),
                    source_type=source_type,
                    text_length=text_length,
                )
            )


async def register_decomposed_asset(
    db: AsyncSession,
    *,
    cleaned_text: str,
    source_type: str,
    asset_name: str,
    lessons: list[dict[str, Any]] | None = None,
    wordbank: dict[str, Any] | list[Any] | None = None,
    cefr_level: str | None = None,
    summary_text: str | None = None,
    tags: list[str] | None = None,
    version_tag: str | None = None,
    created_by: int | None = None,
    upload_task_id: str | None = None,
) -> dict[str, Any]:
    """After GPU 解构成功：原子写入 asset_cache + fingerprint + vectors + bands."""
    text = (cleaned_text or "").strip()
    if len(text) < 80:
        raise ValueError("cleaned_text too short")
    source_type = (source_type or "pdf_text").strip().lower()
    feats = await _compute_features(text)
    blocks: list[int] = feats["simhash_blocks"]
    vector: list[float] = feats["vector"]
    length = int(feats["text_length"])

    asset_id = _new_id()
    fp_id = _new_id()
    vector_ref_id = fp_id

    lesson_payload = {"lessons": lessons or []}
    lesson_url = write_json_blob(asset_id, "lesson_structure.json", lesson_payload)
    wordbank_url = None
    if wordbank is not None:
        wordbank_url = write_json_blob(asset_id, "wordbank.json", wordbank)

    asset = AssetCache(
        id=asset_id,
        asset_name=(asset_name or "未命名教材")[:256],
        source_type=source_type,
        total_lesson_count=len(lessons or []),
        cefr_level=(cefr_level or None),
        wordbank_ref_url=wordbank_url,
        lesson_structure_url=lesson_url,
        summary_text=summary_text,
        tag_list_json=_dumps(tags or []),
        hit_count=0,
        is_ban=False,
        created_by=created_by,
    )
    fp = FingerprintIndex(
        id=fp_id,
        asset_id=asset_id,
        source_type=source_type,
        simhash_blocks_json=_dumps(sh.serialize_simhash_blocks(blocks)),
        vector_ref_id=vector_ref_id,
        text_length=length,
        version_tag=version_tag,
        is_valid=True,
    )
    db.add(asset)
    db.add(fp)
    await db.flush()
    await _write_bands(
        db,
        fingerprint_id=fp_id,
        asset_id=asset_id,
        source_type=source_type,
        text_length=length,
        simhash_blocks=blocks,
    )
    emb.upsert_vector(
        vector_ref_id,
        vector,
        payload={
            "asset_id": asset_id,
            "source_type": source_type,
            "text_length": length,
        },
    )

    user_course_id = None
    if created_by is not None:
        user_course_id = _new_id()
        db.add(
            UserCourseAsset(
                id=user_course_id,
                user_id=created_by,
                asset_cache_id=asset_id,
                asset_title=asset.asset_name,
                diff_patch_json=None,
                is_from_cache=False,
                source_upload_id=upload_task_id,
                is_shared=False,
                share_audit_status="pending",
            )
        )

    if upload_task_id:
        task = (
            await db.execute(select(UploadTask).where(UploadTask.id == upload_task_id))
        ).scalar_one_or_none()
        if task:
            task.status = "success"
            task.fingerprint_id = fp_id
            task.user_course_asset_id = user_course_id
            task.fail_reason = None
            task.update_at = _now()

    # Clear miss negative cache for this text.
    _fp_miss_cache.pop(_text_digest(text), None)
    await db.commit()
    await db.refresh(asset)
    return {
        "asset_id": asset_id,
        "fingerprint_id": fp_id,
        "vector_ref_id": vector_ref_id,
        "user_course_asset_id": user_course_id,
        "lesson_structure_url": lesson_url,
        "wordbank_ref_url": wordbank_url,
    }


async def create_user_course_from_cache(
    db: AsyncSession,
    *,
    user_id: int,
    asset_cache_id: str,
    asset_title: str | None = None,
    upload_task_id: str | None = None,
) -> UserCourseAsset:
    asset = (
        await db.execute(
            select(AssetCache).where(
                AssetCache.id == asset_cache_id,
                AssetCache.is_ban.is_(False),
            )
        )
    ).scalar_one_or_none()
    if asset is None:
        raise ValueError("asset not found or banned")

    existing = (
        await db.execute(
            select(UserCourseAsset).where(
                UserCourseAsset.user_id == user_id,
                UserCourseAsset.asset_cache_id == asset_cache_id,
            )
        )
    ).scalar_one_or_none()
    if existing is not None:
        return existing

    row = UserCourseAsset(
        id=_new_id(),
        user_id=user_id,
        asset_cache_id=asset_cache_id,
        asset_title=(asset_title or asset.asset_name or "复用课程")[:256],
        is_from_cache=True,
        source_upload_id=upload_task_id,
    )
    db.add(row)
    if upload_task_id:
        task = (
            await db.execute(select(UploadTask).where(UploadTask.id == upload_task_id))
        ).scalar_one_or_none()
        if task:
            task.status = "fingerprint_match"
            task.user_course_asset_id = row.id
            task.update_at = _now()
    await db.commit()
    await db.refresh(row)
    return row


async def update_user_diff_patch(
    db: AsyncSession,
    *,
    user_id: int,
    user_course_asset_id: str,
    diff_patch: dict[str, Any],
) -> UserCourseAsset:
    row = (
        await db.execute(
            select(UserCourseAsset).where(
                UserCourseAsset.id == user_course_asset_id,
                UserCourseAsset.user_id == user_id,
            )
        )
    ).scalar_one_or_none()
    if row is None:
        raise ValueError("user course asset not found")
    row.diff_patch_json = _dumps(diff_patch)
    row.update_at = _now()
    await db.commit()
    await db.refresh(row)
    return row


async def invalidate_fingerprint(
    db: AsyncSession,
    *,
    fingerprint_id: str | None = None,
    asset_id: str | None = None,
    ban_asset: bool = False,
) -> int:
    """Mark fingerprint invalid; optionally ban / delete public asset blobs."""
    count = 0
    q = select(FingerprintIndex)
    if fingerprint_id:
        q = q.where(FingerprintIndex.id == fingerprint_id)
    elif asset_id:
        q = q.where(FingerprintIndex.asset_id == asset_id)
    else:
        return 0
    rows = (await db.execute(q)).scalars().all()
    for fp in rows:
        fp.is_valid = False
        fp.update_at = _now()
        emb.delete_vector(fp.vector_ref_id)
        await db.execute(
            delete(SimhashBand).where(SimhashBand.fingerprint_id == fp.id)
        )
        count += 1
        if ban_asset:
            asset = (
                await db.execute(
                    select(AssetCache).where(AssetCache.id == fp.asset_id)
                )
            ).scalar_one_or_none()
            if asset:
                asset.is_ban = True
                asset.update_at = _now()
    await db.commit()
    return count


async def load_asset_lessons(asset_id: str) -> list[dict[str, Any]]:
    data = read_json_blob(asset_id, "lesson_structure.json")
    if isinstance(data, dict):
        lessons = data.get("lessons")
        return lessons if isinstance(lessons, list) else []
    return []


async def admin_stats(db: AsyncSession, *, days: int = 30) -> dict[str, Any]:
    since = _now().replace(microsecond=0)
    from datetime import timedelta

    since = since - timedelta(days=max(1, days))
    hit_n = (
        await db.execute(
            select(func.count())
            .select_from(CacheHitLog)
            .where(
                CacheHitLog.create_at >= since,
                CacheHitLog.hit_result == "hit",
            )
        )
    ).scalar() or 0
    miss_n = (
        await db.execute(
            select(func.count())
            .select_from(CacheHitLog)
            .where(
                CacheHitLog.create_at >= since,
                CacheHitLog.hit_result == "miss",
            )
        )
    ).scalar() or 0
    total = int(hit_n) + int(miss_n)
    hit_rate = (float(hit_n) / total) if total else 0.0
    # Rough GPU save: assume 8 min per avoided decompose.
    gpu_saved_minutes = int(hit_n) * int(settings.fingerprint_gpu_save_minutes)

    top = (
        await db.execute(
            select(AssetCache)
            .where(AssetCache.is_ban.is_(False))
            .order_by(AssetCache.hit_count.desc())
            .limit(20)
        )
    ).scalars().all()
    banned = (
        await db.execute(
            select(AssetCache).where(AssetCache.is_ban.is_(True)).limit(50)
        )
    ).scalars().all()
    asset_count = (
        await db.execute(select(func.count()).select_from(AssetCache))
    ).scalar() or 0
    fp_count = (
        await db.execute(
            select(func.count())
            .select_from(FingerprintIndex)
            .where(FingerprintIndex.is_valid.is_(True))
        )
    ).scalar() or 0

    return {
        "days": days,
        "hit_count": int(hit_n),
        "miss_count": int(miss_n),
        "hit_rate": round(hit_rate, 4),
        "gpu_saved_minutes_est": gpu_saved_minutes,
        "asset_cache_total": int(asset_count),
        "fingerprint_valid_total": int(fp_count),
        "top_assets": [
            {
                "id": a.id,
                "asset_name": a.asset_name,
                "hit_count": int(a.hit_count or 0),
                "source_type": a.source_type,
                "cefr_level": a.cefr_level,
                "last_hit_at": a.last_hit_at.isoformat() if a.last_hit_at else None,
            }
            for a in top
        ],
        "banned_assets": [
            {
                "id": a.id,
                "asset_name": a.asset_name,
                "hit_count": int(a.hit_count or 0),
            }
            for a in banned
        ],
        "config": {
            "enabled": settings.fingerprint_cache_enabled,
            "sim_hamming_max": settings.fingerprint_sim_hamming_max,
            "min_similar_blocks": settings.fingerprint_min_similar_blocks,
            "vec_score_min": settings.fingerprint_vec_score_min,
            "len_ratio_max": settings.fingerprint_len_ratio_max,
            "max_blocks": settings.fingerprint_max_blocks,
        },
    }


async def lru_evict_cold_assets(
    db: AsyncSession,
    *,
    min_hit_count: int | None = None,
    idle_days: int | None = None,
    limit: int = 50,
) -> list[str]:
    """Drop cold, low-reference public assets (P1). High hit_count kept."""
    min_hits = (
        min_hit_count
        if min_hit_count is not None
        else int(settings.fingerprint_lru_min_hits)
    )
    idle = idle_days if idle_days is not None else int(settings.fingerprint_lru_idle_days)
    from datetime import timedelta

    cutoff = _now() - timedelta(days=idle)
    # Do not evict assets referenced by many user copies.
    ref_counts = (
        await db.execute(
            select(
                UserCourseAsset.asset_cache_id,
                func.count().label("n"),
            )
            .where(UserCourseAsset.asset_cache_id.is_not(None))
            .group_by(UserCourseAsset.asset_cache_id)
        )
    ).all()
    protected = {str(aid) for aid, n in ref_counts if aid and int(n) >= 5}

    candidates = (
        await db.execute(
            select(AssetCache)
            .where(
                AssetCache.is_ban.is_(False),
                AssetCache.hit_count < min_hits,
                or_(
                    AssetCache.last_hit_at.is_(None),
                    AssetCache.last_hit_at < cutoff,
                ),
            )
            .order_by(AssetCache.hit_count.asc(), AssetCache.create_at.asc())
            .limit(limit)
        )
    ).scalars().all()

    removed: list[str] = []
    for asset in candidates:
        if asset.id in protected:
            continue
        await invalidate_fingerprint(db, asset_id=asset.id, ban_asset=False)
        fps = (
            await db.execute(
                select(FingerprintIndex).where(FingerprintIndex.asset_id == asset.id)
            )
        ).scalars().all()
        for fp in fps:
            await db.delete(fp)
        delete_asset_blobs(asset.id)
        await db.delete(asset)
        removed.append(asset.id)
    if removed:
        await db.commit()
    return removed
