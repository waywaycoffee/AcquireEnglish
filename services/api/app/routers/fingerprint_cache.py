"""素材指纹缓存复用 API（用户检索 / 写入 + 管理员看板）。"""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.deps import get_current_user
from app.deps_admin import require_admin_token
from app.models import AssetCache, UploadTask, User, UserCourseAsset
from app.services.fingerprint import asset_store as blobs
from app.services.fingerprint import service as fp_svc

router = APIRouter(prefix="/fingerprint-cache", tags=["fingerprint-cache"])
admin_router = APIRouter(prefix="/admin/fingerprint-cache", tags=["admin-fingerprint-cache"])


def _iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.isoformat()


def _asset_out(asset: AssetCache, *, include_lessons: bool = False) -> dict[str, Any]:
    tags: list[Any] = []
    try:
        tags = json.loads(asset.tag_list_json or "[]")
    except json.JSONDecodeError:
        tags = []
    out: dict[str, Any] = {
        "id": asset.id,
        "asset_name": asset.asset_name,
        "source_type": asset.source_type,
        "total_lesson_count": int(asset.total_lesson_count or 0),
        "cefr_level": asset.cefr_level,
        "wordbank_ref_url": asset.wordbank_ref_url,
        "lesson_structure_url": asset.lesson_structure_url,
        "summary_text": asset.summary_text,
        "tags": tags if isinstance(tags, list) else [],
        "hit_count": int(asset.hit_count or 0),
        "last_hit_at": _iso(asset.last_hit_at),
        "is_ban": bool(asset.is_ban),
        "create_at": _iso(asset.create_at),
    }
    if include_lessons:
        out["lessons"] = blobs.read_json_blob(asset.id, "lesson_structure.json") or {
            "lessons": []
        }
    return out


def _user_course_out(row: UserCourseAsset) -> dict[str, Any]:
    patch: Any = None
    if row.diff_patch_json:
        try:
            patch = json.loads(row.diff_patch_json)
        except json.JSONDecodeError:
            patch = None
    return {
        "id": row.id,
        "user_id": row.user_id,
        "asset_cache_id": row.asset_cache_id,
        "asset_title": row.asset_title,
        "diff_patch": patch,
        "is_from_cache": bool(row.is_from_cache),
        "source_upload_id": row.source_upload_id,
        "is_shared": bool(row.is_shared),
        "share_audit_status": row.share_audit_status,
        "create_at": _iso(row.create_at),
        "update_at": _iso(row.update_at),
    }


# ----- request / response models -----


class SearchBody(BaseModel):
    cleaned_text: str = Field(..., min_length=80)
    source_type: str = Field(default="pdf_text", max_length=32)
    file_name: str | None = Field(default=None, max_length=256)
    file_type: str = Field(default="pdf", max_length=32)
    create_upload_task: bool = True
    auto_bind_course: bool = True


class RegisterBody(BaseModel):
    cleaned_text: str = Field(..., min_length=80)
    source_type: str = Field(default="pdf_text", max_length=32)
    asset_name: str = Field(..., min_length=1, max_length=256)
    lessons: list[dict[str, Any]] = Field(default_factory=list)
    wordbank: dict[str, Any] | list[Any] | None = None
    cefr_level: str | None = Field(default=None, max_length=16)
    summary_text: str | None = None
    tags: list[str] = Field(default_factory=list)
    version_tag: str | None = Field(default=None, max_length=64)
    upload_task_id: str | None = None


class DiffPatchBody(BaseModel):
    diff_patch: dict[str, Any]


class UploadTaskCreate(BaseModel):
    file_name: str | None = Field(default=None, max_length=256)
    file_type: str = Field(default="pdf", max_length=32)
    raw_file_key: str | None = Field(default=None, max_length=256)


class BanBody(BaseModel):
    asset_id: str | None = None
    fingerprint_id: str | None = None
    ban_asset: bool = True


class ConfigUpdateBody(BaseModel):
    enabled: bool | None = None
    sim_hamming_max: int | None = Field(default=None, ge=0, le=32)
    min_similar_blocks: int | None = Field(default=None, ge=1, le=64)
    vec_score_min: float | None = Field(default=None, ge=0.0, le=1.0)
    len_ratio_max: float | None = Field(default=None, ge=0.0, le=1.0)
    max_blocks: int | None = Field(default=None, ge=4, le=256)


# ----- user APIs -----


@router.get("/config")
async def public_config() -> dict[str, Any]:
    return {
        "enabled": settings.fingerprint_cache_enabled,
        "messages": {
            "hit": "检测到该教材已有解析资产，直接复用课程结构，无需重新分析",
            "miss": "素材未找到匹配解析资产，已加入 GPU 解析队列，完成后通知你",
            "failed": "解析失败，请稍后重试或更换素材",
            "scan_pdf_hint": "扫描版图片 PDF 指纹命中率较低，建议使用可复制文本 PDF / EPUB",
        },
    }


@router.post("/search")
async def search_and_reuse(
    body: SearchBody,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    upload_id: str | None = None
    if body.create_upload_task:
        upload_id = str(uuid.uuid4())
        db.add(
            UploadTask(
                id=upload_id,
                user_id=user.id,
                file_name=body.file_name,
                file_type=body.file_type,
                status="pending",
            )
        )
        await db.flush()

    result = await fp_svc.search_fingerprint(
        db,
        cleaned_text=body.cleaned_text,
        source_type=body.source_type,
        user_id=user.id,
    )

    user_course = None
    if result.hit and result.asset_id and body.auto_bind_course:
        user_course = await fp_svc.create_user_course_from_cache(
            db,
            user_id=user.id,
            asset_cache_id=result.asset_id,
            upload_task_id=upload_id,
        )
        if upload_id:
            task = (
                await db.execute(select(UploadTask).where(UploadTask.id == upload_id))
            ).scalar_one_or_none()
            if task:
                task.status = "fingerprint_match"
                task.fingerprint_id = result.fingerprint_id
                task.user_course_asset_id = user_course.id
                await db.commit()
    elif upload_id and not result.hit:
        task = (
            await db.execute(select(UploadTask).where(UploadTask.id == upload_id))
        ).scalar_one_or_none()
        if task:
            task.status = "queue_gpu"
            task.fail_reason = None
            await db.commit()
    else:
        await db.commit()

    asset_payload = None
    if result.asset is not None:
        asset_payload = _asset_out(result.asset, include_lessons=True)

    return {
        "hit": result.hit,
        "degraded": result.degraded,
        "message": result.message
        or (
            "检测到该教材已有解析资产，直接复用课程结构，无需重新分析"
            if result.hit
            else "素材未找到匹配解析资产，已加入 GPU 解析队列，完成后通知你"
        ),
        "asset_id": result.asset_id,
        "fingerprint_id": result.fingerprint_id,
        "similar_blocks": result.similar_blocks,
        "cost_ms": result.cost_ms,
        "candidates": result.candidates,
        "upload_task_id": upload_id,
        "asset": asset_payload,
        "user_course_asset": _user_course_out(user_course) if user_course else None,
    }


@router.post("/register")
async def register_after_gpu(
    body: RegisterBody,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    """解构流水线成功后写入公共缓存（需登录；管理员亦可代写）。"""
    if not settings.fingerprint_cache_enabled:
        raise HTTPException(status_code=503, detail="指纹缓存复用已关闭")
    try:
        out = await fp_svc.register_decomposed_asset(
            db,
            cleaned_text=body.cleaned_text,
            source_type=body.source_type,
            asset_name=body.asset_name,
            lessons=body.lessons,
            wordbank=body.wordbank,
            cefr_level=body.cefr_level,
            summary_text=body.summary_text,
            tags=body.tags,
            version_tag=body.version_tag,
            created_by=user.id,
            upload_task_id=body.upload_task_id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return {"ok": True, **out}


@router.get("/assets/{asset_id}")
async def get_asset(
    asset_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    _ = user
    asset = (
        await db.execute(
            select(AssetCache).where(
                AssetCache.id == asset_id,
                AssetCache.is_ban.is_(False),
            )
        )
    ).scalar_one_or_none()
    if asset is None:
        raise HTTPException(status_code=404, detail="资产不存在或已下架")
    return _asset_out(asset, include_lessons=True)


@router.get("/my-courses")
async def list_my_courses(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    rows = (
        await db.execute(
            select(UserCourseAsset)
            .where(UserCourseAsset.user_id == user.id)
            .order_by(UserCourseAsset.create_at.desc())
            .limit(200)
        )
    ).scalars().all()
    return {"items": [_user_course_out(r) for r in rows]}


@router.patch("/my-courses/{course_id}/diff")
async def patch_my_course_diff(
    course_id: str,
    body: DiffPatchBody,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    try:
        row = await fp_svc.update_user_diff_patch(
            db,
            user_id=user.id,
            user_course_asset_id=course_id,
            diff_patch=body.diff_patch,
        )
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return _user_course_out(row)


@router.post("/upload-tasks")
async def create_upload_task(
    body: UploadTaskCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    tid = str(uuid.uuid4())
    row = UploadTask(
        id=tid,
        user_id=user.id,
        file_name=body.file_name,
        file_type=body.file_type,
        raw_file_key=body.raw_file_key,
        status="pending",
    )
    db.add(row)
    await db.commit()
    return {
        "id": tid,
        "status": "pending",
        "file_name": body.file_name,
        "file_type": body.file_type,
    }


@router.get("/upload-tasks/{task_id}")
async def get_upload_task(
    task_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    row = (
        await db.execute(
            select(UploadTask).where(
                UploadTask.id == task_id,
                UploadTask.user_id == user.id,
            )
        )
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    return {
        "id": row.id,
        "status": row.status,
        "file_name": row.file_name,
        "file_type": row.file_type,
        "fingerprint_id": row.fingerprint_id,
        "user_course_asset_id": row.user_course_asset_id,
        "fail_reason": row.fail_reason,
        "create_at": _iso(row.create_at),
        "update_at": _iso(row.update_at),
    }


@router.post("/upload-tasks/{task_id}/fail")
async def mark_upload_failed(
    task_id: str,
    reason: str = Query(default="解构失败", max_length=500),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    row = (
        await db.execute(
            select(UploadTask).where(
                UploadTask.id == task_id,
                UploadTask.user_id == user.id,
            )
        )
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    row.status = "failed"
    row.fail_reason = reason
    if row.fingerprint_id:
        await fp_svc.invalidate_fingerprint(db, fingerprint_id=row.fingerprint_id)
    await db.commit()
    return {"id": row.id, "status": "failed", "fail_reason": reason}


# ----- admin APIs -----


@admin_router.get("/stats")
async def admin_cache_stats(
    days: int = Query(30, ge=1, le=365),
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    return await fp_svc.admin_stats(db, days=days)


@admin_router.post("/invalidate")
async def admin_invalidate(
    body: BanBody,
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    if not body.asset_id and not body.fingerprint_id:
        raise HTTPException(status_code=400, detail="需要 asset_id 或 fingerprint_id")
    n = await fp_svc.invalidate_fingerprint(
        db,
        fingerprint_id=body.fingerprint_id,
        asset_id=body.asset_id,
        ban_asset=body.ban_asset,
    )
    return {"invalidated": n, "ban_asset": body.ban_asset}


@admin_router.post("/lru-evict")
async def admin_lru_evict(
    limit: int = Query(50, ge=1, le=500),
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    removed = await fp_svc.lru_evict_cold_assets(db, limit=limit)
    return {"removed": removed, "count": len(removed)}


@admin_router.get("/config")
async def admin_get_config(
    _: str = Depends(require_admin_token),
) -> dict[str, Any]:
    return {
        "enabled": settings.fingerprint_cache_enabled,
        "sim_hamming_max": settings.fingerprint_sim_hamming_max,
        "min_similar_blocks": settings.fingerprint_min_similar_blocks,
        "vec_score_min": settings.fingerprint_vec_score_min,
        "len_ratio_max": settings.fingerprint_len_ratio_max,
        "max_blocks": settings.fingerprint_max_blocks,
        "block_chars": settings.fingerprint_block_chars,
        "top_k": settings.fingerprint_top_k,
        "lru_min_hits": settings.fingerprint_lru_min_hits,
        "lru_idle_days": settings.fingerprint_lru_idle_days,
        "gpu_save_minutes": settings.fingerprint_gpu_save_minutes,
        "embed_url_configured": bool((settings.fingerprint_embed_url or "").strip()),
    }


@admin_router.patch("/config")
async def admin_patch_config(
    body: ConfigUpdateBody,
    _: str = Depends(require_admin_token),
) -> dict[str, Any]:
    """运行时热更新（进程内；重启后回落到环境变量）。"""
    if body.enabled is not None:
        settings.fingerprint_cache_enabled = body.enabled
    if body.sim_hamming_max is not None:
        settings.fingerprint_sim_hamming_max = body.sim_hamming_max
    if body.min_similar_blocks is not None:
        settings.fingerprint_min_similar_blocks = body.min_similar_blocks
    if body.vec_score_min is not None:
        settings.fingerprint_vec_score_min = body.vec_score_min
    if body.len_ratio_max is not None:
        settings.fingerprint_len_ratio_max = body.len_ratio_max
    if body.max_blocks is not None:
        settings.fingerprint_max_blocks = body.max_blocks
    return {
        "enabled": settings.fingerprint_cache_enabled,
        "sim_hamming_max": settings.fingerprint_sim_hamming_max,
        "min_similar_blocks": settings.fingerprint_min_similar_blocks,
        "vec_score_min": settings.fingerprint_vec_score_min,
        "len_ratio_max": settings.fingerprint_len_ratio_max,
        "max_blocks": settings.fingerprint_max_blocks,
        "block_chars": settings.fingerprint_block_chars,
        "top_k": settings.fingerprint_top_k,
        "lru_min_hits": settings.fingerprint_lru_min_hits,
        "lru_idle_days": settings.fingerprint_lru_idle_days,
        "gpu_save_minutes": settings.fingerprint_gpu_save_minutes,
        "embed_url_configured": bool((settings.fingerprint_embed_url or "").strip()),
    }
