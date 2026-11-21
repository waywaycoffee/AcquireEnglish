"""Community exam asset upload / list / download metadata / report."""

from __future__ import annotations

import json
from typing import Any

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import Select, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import ExamAsset, ExamAssetReport, User
from app.routers.community_social import post_guard
from app.services import exam_asset_store as store

router = APIRouter(
    prefix="/community/exam-assets",
    tags=["exam-assets"],
    dependencies=[Depends(post_guard)],
)


def _public_name(user: User) -> str:
    name = (user.display_name or "").strip()
    if name:
        return name[:40]
    return f"学员{user.id:04d}"


def _meta(raw: str | None) -> dict[str, Any]:
    try:
        data = json.loads(raw or "{}")
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def _serialize(asset: ExamAsset, uploader: User | None = None) -> dict[str, Any]:
    return {
        "id": asset.id,
        "family_id": asset.family_id,
        "kind": asset.kind,
        "title": asset.title,
        "sha256": asset.sha256,
        "size_bytes": asset.size_bytes,
        "download_url": store.public_download_url(asset.storage_path),
        "meta": _meta(asset.meta_json),
        "status": asset.status,
        "report_count": asset.report_count,
        "uploader_name": _public_name(uploader) if uploader else f"学员{asset.user_id:04d}",
        "uploader_id": asset.user_id,
        "created_at": asset.created_at.isoformat() if asset.created_at else None,
    }


@router.get("")
async def list_assets(
    family_id: str | None = Query(None),
    kind: str | None = Query(None),
    limit: int = Query(40, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> list[dict[str, Any]]:
    del user  # auth required
    stmt: Select[tuple[ExamAsset]] = select(ExamAsset).where(
        ExamAsset.status == "visible"
    )
    if family_id:
        stmt = stmt.where(ExamAsset.family_id == family_id.strip())
    if kind:
        stmt = stmt.where(ExamAsset.kind == kind.strip().lower())
    stmt = stmt.order_by(ExamAsset.id.desc()).limit(limit)
    rows = (await db.execute(stmt)).scalars().all()
    uploaders: dict[int, User] = {}
    if rows:
        ids = {r.user_id for r in rows}
        for u in (
            await db.execute(select(User).where(User.id.in_(ids)))
        ).scalars().all():
            uploaders[u.id] = u
    return [_serialize(r, uploaders.get(r.user_id)) for r in rows]


@router.get("/{asset_id}")
async def get_asset(
    asset_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict[str, Any]:
    del user
    asset = await db.get(ExamAsset, asset_id)
    if asset is None or asset.status != "visible":
        raise HTTPException(status_code=404, detail="asset not found")
    uploader = await db.get(User, asset.user_id)
    return _serialize(asset, uploader)


@router.post("")
async def upload_asset(
    file: UploadFile = File(...),
    family_id: str = Form(...),
    kind: str = Form("other"),
    title: str = Form(...),
    license_ack: str = Form("0"),
    meta_json: str = Form("{}"),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict[str, Any]:
    if license_ack not in {"1", "true", "True", "yes"}:
        raise HTTPException(
            status_code=400,
            detail="must acknowledge personal-study / authorized use",
        )
    try:
        kind_n = store.assert_kind(kind)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    fam = (family_id or "").strip()
    if not fam:
        raise HTTPException(status_code=400, detail="family_id required")
    title_n = (title or "").strip()[:200]
    if not title_n:
        raise HTTPException(status_code=400, detail="title required")
    data = await file.read()
    try:
        saved = store.save_bytes(
            data, family_id=fam, filename=file.filename or "asset.bin"
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    existing = (
        await db.execute(
            select(ExamAsset).where(
                ExamAsset.sha256 == saved["sha256"],
                ExamAsset.family_id == fam,
            )
        )
    ).scalar_one_or_none()
    if existing is not None:
        if existing.status != "visible":
            existing.status = "visible"
            existing.title = title_n
            existing.kind = kind_n
            existing.license_ack = 1
            await db.commit()
            await db.refresh(existing)
        return _serialize(existing, user)

    meta = _meta(meta_json)
    meta.setdefault("original_filename", file.filename or "")
    meta.setdefault("ext", saved["ext"])
    asset = ExamAsset(
        user_id=user.id,
        family_id=fam,
        kind=kind_n,
        title=title_n,
        storage_path=saved["storage_path"],
        sha256=saved["sha256"],
        size_bytes=int(saved["size"]),
        meta_json=store.dumps_meta(meta),
        status="visible",
        license_ack=1,
    )
    db.add(asset)
    await db.commit()
    await db.refresh(asset)
    return _serialize(asset, user)


class ReportIn(BaseModel):
    reason: str = Field(..., min_length=2, max_length=500)


@router.post("/{asset_id}/report")
async def report_asset(
    asset_id: int,
    body: ReportIn,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict[str, str]:
    asset = await db.get(ExamAsset, asset_id)
    if asset is None:
        raise HTTPException(status_code=404, detail="asset not found")
    already = (
        await db.execute(
            select(ExamAssetReport).where(
                ExamAssetReport.user_id == user.id,
                ExamAssetReport.asset_id == asset_id,
            )
        )
    ).scalar_one_or_none()
    if already is not None:
        return {"status": "already_reported"}
    db.add(
        ExamAssetReport(
            user_id=user.id,
            asset_id=asset_id,
            reason=body.reason.strip()[:500],
        )
    )
    asset.report_count = int(asset.report_count or 0) + 1
    if asset.report_count >= 5:
        asset.status = "hidden"
    await db.commit()
    return {"status": "ok"}
