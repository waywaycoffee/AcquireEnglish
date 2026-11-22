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
from app.services.fingerprint.canonical import (
    CANONICAL_SOURCE_TYPE,
    TEXT_SOURCE_TYPES,
    compatible_source_types,
    fingerprint_input,
)
from app.services.fingerprint.asset_store import (
    delete_asset_blobs,
    delete_upload_payload,
    read_json_blob,
    read_upload_payload,
    write_json_blob,
    write_upload_payload,
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
                    SimhashBand.source_type.in_(compatible_source_types(source_type)),
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
    source_type = (source_type or "pdf_text").strip().lower()
    text = fingerprint_input(cleaned_text, source_type)

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
            source_types=compatible_source_types(source_type),
            limit=top_k,
            score_min=vec_min,
        )
        for h in hits:
            aid = (h.get("payload") or {}).get("asset_id")
            if aid and (h.get("payload") or {}).get("source_type") in compatible_source_types(source_type):
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
                FingerprintIndex.source_type.in_(compatible_source_types(source_type)),
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
    source_type = (source_type or "pdf_text").strip().lower()
    text = fingerprint_input(cleaned_text, source_type)
    if len(text) < 80:
        raise ValueError("cleaned_text too short")
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
        source_type=CANONICAL_SOURCE_TYPE if source_type in TEXT_SOURCE_TYPES else source_type,
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
        source_type=CANONICAL_SOURCE_TYPE if source_type in TEXT_SOURCE_TYPES else source_type,
        text_length=length,
        simhash_blocks=blocks,
    )
    emb.upsert_vector(
        vector_ref_id,
        vector,
        payload={
            "asset_id": asset_id,
            "source_type": CANONICAL_SOURCE_TYPE if source_type in TEXT_SOURCE_TYPES else source_type,
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
            task.notify_pending = 1
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


def load_asset_lessons(asset_id: str) -> list[dict[str, Any]]:
    data = read_json_blob(asset_id, "lesson_structure.json")
    if isinstance(data, dict):
        lessons = data.get("lessons")
        if isinstance(lessons, list):
            return [dict(x) for x in lessons if isinstance(x, dict)]
        return []
    return []


_LESSON_HEADING_RE = None


def _lesson_heading_re():
    global _LESSON_HEADING_RE
    if _LESSON_HEADING_RE is None:
        import re

        _LESSON_HEADING_RE = re.compile(
            r"(?im)^(?:\s*)(?:lesson|unit|chapter|第)\s*"
            r"(?:\d+|[ivxlcdm]+|[一二三四五六七八九十百]+)\s*"
            r"[.:：、\-]?\s*(.*)$"
        )
    return _LESSON_HEADING_RE


def decompose_text_to_lessons(
    cleaned_text: str,
    *,
    asset_name: str = "",
    max_lesson_chars: int = 2800,
    min_lesson_chars: int = 160,
    annotate: bool = True,
) -> list[dict[str, Any]]:
    """Light CPU decompose: split by lesson/chapter headings or sized paragraphs.

    When annotate=True (default), each lesson gets CEFR, 3–8 target_words, goal, tasks.
    Heavy LLM/OpenMAIC 解构 can replace this later; workers still call register the same way.
    """
    text = (cleaned_text or "").strip()
    if not text:
        return []

    import re

    heading_re = _lesson_heading_re()
    lines = text.splitlines()
    chunks: list[tuple[str, list[str]]] = []
    current_title = ""
    buf: list[str] = []

    def flush(title: str, body_lines: list[str]) -> None:
        body = "\n".join(body_lines).strip()
        if len(body) < min_lesson_chars and chunks:
            # Merge tiny leftover into previous.
            prev_title, prev_body = chunks[-1]
            chunks[-1] = (prev_title, (prev_body + "\n\n" + body).strip().splitlines())
            return
        if body:
            chunks.append((title or "", body.splitlines()))

    for line in lines:
        m = heading_re.match(line.strip())
        if m and buf:
            flush(current_title, buf)
            buf = []
            current_title = (m.group(1) or line.strip())[:120]
            continue
        if m and not buf:
            current_title = (m.group(1) or line.strip())[:120]
            continue
        buf.append(line)
    flush(current_title, buf)

    # No headings → pack by blank-line paragraphs into size windows.
    if len(chunks) <= 1 and len(text) > max_lesson_chars:
        paras = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
        chunks = []
        acc: list[str] = []
        acc_len = 0
        part = 1
        for p in paras:
            if acc and acc_len + len(p) > max_lesson_chars:
                chunks.append((f"Part {part}", acc))
                part += 1
                acc = [p]
                acc_len = len(p)
            else:
                acc.append(p)
                acc_len += len(p) + 2
        if acc:
            chunks.append((f"Part {part}", acc))

    # Still oversized single lesson → hard split.
    normalized: list[tuple[str, str]] = []
    for title, body_lines in chunks:
        body = "\n".join(body_lines).strip()
        if len(body) <= max_lesson_chars * 2:
            normalized.append((title, body))
            continue
        start = 0
        sub = 1
        while start < len(body):
            end = min(len(body), start + max_lesson_chars)
            if end < len(body):
                cut = body.rfind("\n", start + min_lesson_chars, end)
                if cut > start:
                    end = cut
            piece = body[start:end].strip()
            if piece:
                label = title or asset_name or "Lesson"
                normalized.append(
                    (f"{label} · {sub}" if sub > 1 or title else label, piece)
                )
                sub += 1
            start = end

    if not normalized:
        normalized = [(asset_name or "Lesson 1", text)]

    lessons: list[dict[str, Any]] = []
    for i, (title, body) in enumerate(normalized, start=1):
        lessons.append(
            {
                "lesson_no": i,
                "title": (title or f"Lesson {i}")[:256],
                "text_content": body,
            }
        )
    if annotate:
        from app.services.fingerprint.annotate import annotate_lessons

        lessons, _, _ = annotate_lessons(lessons)
    return lessons


def store_upload_task_payload(
    task_id: str,
    *,
    cleaned_text: str,
    source_type: str,
    file_name: str | None,
    file_type: str,
    user_id: int,
    asset_name: str | None = None,
    candidates: list[str] | None = None,
    degraded: bool = False,
    private_only: bool = False,
) -> str:
    return write_upload_payload(
        task_id,
        {
            "cleaned_text": cleaned_text,
            "source_type": source_type,
            "file_name": file_name,
            "file_type": file_type,
            "user_id": user_id,
            "asset_name": (asset_name or file_name or "导入教材")[:256],
            "candidates": candidates or [],
            "degraded": bool(degraded),
            "private_only": bool(private_only),
        },
    )


def _renumber_lessons(lessons: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for i, raw in enumerate(lessons, start=1):
        item = dict(raw)
        item["lesson_no"] = i
        out.append(item)
    return out


def _patch_dict(row: UserCourseAsset) -> dict[str, Any]:
    if not row.diff_patch_json:
        return {}
    try:
        data = json.loads(row.diff_patch_json)
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def resolve_user_course_lessons_sync(row: UserCourseAsset) -> list[dict[str, Any]]:
    """Merge public asset lessons with private diff_patch lessons overlay."""
    patch = _patch_dict(row)
    if isinstance(patch.get("lessons"), list) and patch["lessons"]:
        return [dict(x) for x in patch["lessons"] if isinstance(x, dict)]
    if row.asset_cache_id:
        return load_asset_lessons(row.asset_cache_id)
    return []


async def register_private_user_course(
    db: AsyncSession,
    *,
    user_id: int,
    asset_name: str,
    lessons: list[dict[str, Any]],
    cefr_level: str | None = None,
    wordbank: dict[str, Any] | list[Any] | None = None,
    summary_text: str | None = None,
    upload_task_id: str | None = None,
    source_type: str = "pdf_text",
) -> dict[str, Any]:
    """Private-only finalize: UserCourseAsset without public asset_cache / fingerprint."""
    from app.services.fingerprint.annotate import annotate_lessons

    annotated, pack_cefr, pack_bank = annotate_lessons(list(lessons or []))
    if cefr_level:
        pack_cefr = cefr_level
    if wordbank is not None:
        pack_bank = wordbank if isinstance(wordbank, dict) else {"words": wordbank}

    course_id = _new_id()
    patch = {
        "private_only": True,
        "status": "draft",
        "source_type": source_type,
        "cefr_level": pack_cefr,
        "wordbank": pack_bank,
        "summary_text": (summary_text or "")[:500],
        "lessons": annotated,
        "copyright_disclaimer": (
            "用户声明素材仅供个人学习或已获授权；平台不自动公开发布。"
        ),
    }
    row = UserCourseAsset(
        id=course_id,
        user_id=user_id,
        asset_cache_id=None,
        asset_title=(asset_name or "私人教材课")[:256],
        diff_patch_json=_dumps(patch),
        is_from_cache=False,
        source_upload_id=upload_task_id,
        is_shared=False,
        share_audit_status="private",
    )
    db.add(row)
    if upload_task_id:
        task = (
            await db.execute(select(UploadTask).where(UploadTask.id == upload_task_id))
        ).scalar_one_or_none()
        if task:
            task.status = "success"
            task.user_course_asset_id = course_id
            task.fail_reason = None
            task.notify_pending = 1
            task.update_at = _now()
    await db.commit()
    await db.refresh(row)
    return {
        "user_course_asset_id": course_id,
        "asset_id": None,
        "fingerprint_id": None,
        "private_only": True,
        "cefr_level": pack_cefr,
        "lesson_count": len(annotated),
    }


def apply_lesson_ops(
    lessons: list[dict[str, Any]],
    *,
    action: str,
    lesson_nos: list[int] | None = None,
    split_at_char: int | None = None,
    lesson_edit: dict[str, Any] | None = None,
    replace_lessons: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    """Apply merge/split/delete/edit/replace on a lesson list."""
    from app.services.fingerprint.annotate import annotate_lesson

    action = (action or "").strip().lower()
    if action == "replace":
        if not isinstance(replace_lessons, list):
            raise ValueError("replace requires lessons array")
        return _renumber_lessons(
            [annotate_lesson(dict(x)) for x in replace_lessons if isinstance(x, dict)]
        )

    current = _renumber_lessons([dict(x) for x in lessons if isinstance(x, dict)])
    nos = [int(n) for n in (lesson_nos or [])]

    if action == "delete":
        if not nos:
            raise ValueError("delete requires lesson_nos")
        drop = set(nos)
        current = [L for L in current if int(L.get("lesson_no") or 0) not in drop]
        return _renumber_lessons(current)

    if action == "edit":
        if len(nos) != 1 or not isinstance(lesson_edit, dict):
            raise ValueError("edit requires one lesson_no and lesson object")
        target = nos[0]
        out: list[dict[str, Any]] = []
        for L in current:
            if int(L.get("lesson_no") or 0) == target:
                merged = dict(L)
                for key in (
                    "title",
                    "text_content",
                    "goal",
                    "cefr",
                    "target_words",
                    "tasks",
                ):
                    if key in lesson_edit:
                        merged[key] = lesson_edit[key]
                out.append(annotate_lesson(merged))
            else:
                out.append(L)
        return _renumber_lessons(out)

    if action == "merge":
        if len(nos) < 2:
            raise ValueError("merge requires at least two lesson_nos")
        nos_sorted = sorted(set(nos))
        by_no = {int(L.get("lesson_no") or 0): L for L in current}
        missing = [n for n in nos_sorted if n not in by_no]
        if missing:
            raise ValueError(f"unknown lesson_nos: {missing}")
        first = dict(by_no[nos_sorted[0]])
        bodies = [str(by_no[n].get("text_content") or "").strip() for n in nos_sorted]
        titles = [str(by_no[n].get("title") or "").strip() for n in nos_sorted]
        first["text_content"] = "\n\n".join(b for b in bodies if b)
        first["title"] = " / ".join(t for t in titles if t)[:256]
        drop = set(nos_sorted[1:])
        out = []
        for L in current:
            n = int(L.get("lesson_no") or 0)
            if n == nos_sorted[0]:
                out.append(annotate_lesson(first))
            elif n in drop:
                continue
            else:
                out.append(L)
        return _renumber_lessons(out)

    if action == "split":
        if len(nos) != 1:
            raise ValueError("split requires exactly one lesson_no")
        target = nos[0]
        out = []
        for L in current:
            n = int(L.get("lesson_no") or 0)
            if n != target:
                out.append(L)
                continue
            body = str(L.get("text_content") or "")
            if split_at_char is None:
                cut = max(80, len(body) // 2)
                # Prefer paragraph boundary near midpoint.
                para = body.find("\n\n", cut - 40)
                if para > 40:
                    cut = para
            else:
                cut = max(1, min(len(body) - 1, int(split_at_char)))
            left = body[:cut].strip()
            right = body[cut:].strip()
            if not left or not right:
                raise ValueError("split produced empty half")
            a = dict(L)
            b = dict(L)
            a["text_content"] = left
            a["title"] = f"{L.get('title') or 'Lesson'} (1)"
            b["text_content"] = right
            b["title"] = f"{L.get('title') or 'Lesson'} (2)"
            out.append(annotate_lesson(a))
            out.append(annotate_lesson(b))
        return _renumber_lessons(out)

    raise ValueError(f"unsupported action: {action}")


async def patch_user_course_lessons(
    db: AsyncSession,
    *,
    user_id: int,
    user_course_asset_id: str,
    action: str,
    lesson_nos: list[int] | None = None,
    split_at_char: int | None = None,
    lesson_edit: dict[str, Any] | None = None,
    replace_lessons: list[dict[str, Any]] | None = None,
) -> tuple[UserCourseAsset, list[dict[str, Any]]]:
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
    current = resolve_user_course_lessons_sync(row)
    updated = apply_lesson_ops(
        current,
        action=action,
        lesson_nos=lesson_nos,
        split_at_char=split_at_char,
        lesson_edit=lesson_edit,
        replace_lessons=replace_lessons,
    )
    patch = _patch_dict(row)
    patch["lessons"] = updated
    patch["private_only"] = bool(patch.get("private_only") or row.asset_cache_id is None)
    if "status" not in patch:
        patch["status"] = "draft"
    row.diff_patch_json = _dumps(patch)
    row.update_at = _now()
    await db.commit()
    await db.refresh(row)
    return row, updated


async def sync_user_course_from_public(
    db: AsyncSession,
    *,
    user_id: int,
    user_course_asset_id: str,
) -> tuple[UserCourseAsset, list[dict[str, Any]]]:
    """Drop private lesson overlay and re-read public asset_cache lessons."""
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
    if not row.asset_cache_id:
        raise ValueError("课程未关联公共缓存，无法同步公共版本")
    public = load_asset_lessons(row.asset_cache_id)
    if not public:
        raise ValueError("公共课程资产为空或已下架")
    patch = _patch_dict(row)
    patch.pop("lessons", None)
    patch["private_only"] = False
    patch["synced_from_public_at"] = _now().isoformat()
    patch["kept_private_edits"] = False
    row.diff_patch_json = _dumps(patch) if patch else None
    row.update_at = _now()
    await db.commit()
    await db.refresh(row)
    return row, public


async def list_pending_decompose_notifications(
    db: AsyncSession, *, user_id: int, limit: int = 20
) -> list[dict[str, Any]]:
    rows = (
        await db.execute(
            select(UploadTask)
            .where(
                UploadTask.user_id == user_id,
                UploadTask.notify_pending == 1,
                UploadTask.status.in_(("success", "fingerprint_match")),
            )
            .order_by(UploadTask.update_at.desc())
            .limit(max(1, min(50, limit)))
        )
    ).scalars().all()
    out: list[dict[str, Any]] = []
    for row in rows:
        out.append(
            {
                "upload_task_id": row.id,
                "status": row.status,
                "file_name": row.file_name,
                "user_course_asset_id": row.user_course_asset_id,
                "message": "云端解析完成，已写入课程包",
                "update_at": row.update_at.isoformat() if row.update_at else None,
            }
        )
    return out


async def ack_decompose_notifications(
    db: AsyncSession, *, user_id: int, upload_task_ids: list[str] | None = None
) -> int:
    q = select(UploadTask).where(
        UploadTask.user_id == user_id,
        UploadTask.notify_pending == 1,
    )
    if upload_task_ids:
        q = q.where(UploadTask.id.in_(upload_task_ids))
    rows = (await db.execute(q)).scalars().all()
    for row in rows:
        row.notify_pending = 0
        row.update_at = _now()
    if rows:
        await db.commit()
    return len(rows)


async def finalize_user_course(
    db: AsyncSession,
    *,
    user_id: int,
    user_course_asset_id: str,
    title: str | None = None,
) -> tuple[UserCourseAsset, list[dict[str, Any]]]:
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
    lessons = resolve_user_course_lessons_sync(row)
    if not lessons:
        raise ValueError("course has no lessons to finalize")
    patch = _patch_dict(row)
    patch["lessons"] = lessons
    patch["status"] = "ready"
    patch["finalized_at"] = _now().isoformat()
    patch["private_only"] = True if row.asset_cache_id is None else bool(
        patch.get("private_only", False)
    )
    # Never auto-share on finalize.
    row.is_shared = False
    if row.share_audit_status not in ("private", "rejected"):
        row.share_audit_status = "private"
    if title and title.strip():
        row.asset_title = title.strip()[:256]
    row.diff_patch_json = _dumps(patch)
    row.update_at = _now()
    await db.commit()
    await db.refresh(row)
    return row, lessons


async def drain_queue_gpu(
    db: AsyncSession,
    *,
    limit: int = 3,
) -> list[dict[str, Any]]:
    """Claim ``queue_gpu`` upload tasks, decompose, register public assets."""
    q = (
        select(UploadTask)
        .where(UploadTask.status == "queue_gpu")
        .order_by(UploadTask.create_at.asc())
        .limit(max(1, limit))
    )
    try:
        rows = (await db.execute(q.with_for_update(skip_locked=True))).scalars().all()
    except Exception:  # noqa: BLE001 — SQLite / dialects without skip_locked
        await db.rollback()
        rows = (await db.execute(q)).scalars().all()

    results: list[dict[str, Any]] = []
    for task in rows:
        task.status = "processing"
        task.update_at = _now()
    if rows:
        await db.commit()

    for task in rows:
        out = await _process_queue_gpu_task(db, task)
        results.append(out)
    return results


async def _process_queue_gpu_task(
    db: AsyncSession,
    task: UploadTask,
) -> dict[str, Any]:
    payload = read_upload_payload(task.id)
    if not isinstance(payload, dict):
        task.status = "failed"
        task.fail_reason = "缺少解构文本载荷（payload.json）"
        task.update_at = _now()
        await db.commit()
        return {"task_id": task.id, "ok": False, "error": task.fail_reason}

    cleaned = str(payload.get("cleaned_text") or "").strip()
    if len(cleaned) < 80:
        task.status = "failed"
        task.fail_reason = "解构文本过短"
        task.update_at = _now()
        await db.commit()
        return {"task_id": task.id, "ok": False, "error": task.fail_reason}

    source_type = str(payload.get("source_type") or "pdf_text")
    asset_name = str(
        payload.get("asset_name") or task.file_name or "导入教材"
    )[:256]
    user_id = payload.get("user_id")
    try:
        created_by = int(user_id) if user_id is not None else int(task.user_id)
    except (TypeError, ValueError):
        created_by = int(task.user_id)

    private_only = bool(payload.get("private_only"))
    try:
        from app.services.fingerprint.annotate import clean_material_text
        from app.services.fingerprint.openmaic_adapter import decompose_and_annotate

        cleaned = clean_material_text(cleaned)
        lessons, pack_cefr, wordbank = decompose_and_annotate(
            cleaned,
            asset_name=asset_name,
            already_cleaned=True,
        )
        summary = cleaned[:280].replace("\n", " ").strip()
        if private_only:
            reg = await register_private_user_course(
                db,
                user_id=created_by,
                asset_name=asset_name,
                lessons=lessons,
                cefr_level=pack_cefr,
                wordbank=wordbank,
                summary_text=summary,
                upload_task_id=task.id,
                source_type=source_type,
            )
        else:
            reg = await register_decomposed_asset(
                db,
                cleaned_text=cleaned,
                source_type=source_type,
                asset_name=asset_name,
                lessons=lessons,
                wordbank=wordbank,
                cefr_level=pack_cefr,
                summary_text=summary,
                tags=["auto_decompose"],
                created_by=created_by,
                upload_task_id=task.id,
            )
        delete_upload_payload(task.id)
        return {"task_id": task.id, "ok": True, **reg}
    except Exception as exc:  # noqa: BLE001
        # Re-load task in case register partially committed.
        fresh = (
            await db.execute(select(UploadTask).where(UploadTask.id == task.id))
        ).scalar_one_or_none()
        if fresh and fresh.status not in ("success", "fingerprint_match"):
            fresh.status = "failed"
            fresh.fail_reason = f"解构失败: {exc}"[:500]
            fresh.update_at = _now()
            await db.commit()
        return {"task_id": task.id, "ok": False, "error": str(exc)}


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
        "vector_backend": emb.vector_backend(),
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
    # Any active user course must keep its referenced shared asset available.
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
    protected = {str(aid) for aid, n in ref_counts if aid and int(n) > 0}

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
