"""Private product feedback (user submit → admin console only)."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.deps_admin import require_admin_token
from app.models import ProductFeedback, User

router = APIRouter(prefix="/feedback", tags=["feedback"])
admin_router = APIRouter(prefix="/admin/feedback", tags=["admin-feedback"])

FeedbackCategory = Literal[
    "bug",
    "ux",
    "content",
    "performance",
    "billing",
    "feature",
    "general",
]
FeedbackStatus = Literal["open", "read", "done"]

_RATE_LIMIT_PER_DAY = 20


class FeedbackCreateBody(BaseModel):
    body: str = Field(min_length=2, max_length=8000)
    title: str = Field(default="", max_length=200)
    category: FeedbackCategory = "general"
    contact: str = Field(default="", max_length=120)
    app_version: str = Field(default="", max_length=64)
    screenshot_url: str = Field(default="", max_length=512)


class FeedbackStatusBody(BaseModel):
    status: FeedbackStatus
    # None = leave existing note unchanged (avoid wiping when only flipping status).
    admin_note: str | None = Field(default=None, max_length=4000)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _serialize(row: ProductFeedback, user: User | None = None) -> dict[str, Any]:
    return {
        "id": row.id,
        "user_id": row.user_id,
        "category": row.category,
        "title": row.title or "",
        "body": row.body or "",
        "contact": row.contact or "",
        "app_version": row.app_version or "",
        "screenshot_url": row.screenshot_url or "",
        "status": row.status,
        "admin_note": row.admin_note or "",
        "created_at": row.created_at.isoformat() if row.created_at else None,
        "updated_at": row.updated_at.isoformat() if row.updated_at else None,
        "user_email": (user.email if user else None),
        "user_display_name": (user.display_name if user else None),
        "user_phone": (user.phone if user else None),
    }


@router.post("")
async def submit_feedback(
    body: FeedbackCreateBody,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    text = (body.body or "").strip()
    if len(text) < 2:
        raise HTTPException(status_code=400, detail="请填写问题情况描述")
    title = (body.title or "").strip()
    if not title:
        title = "功能问题反馈"
    screenshot = (body.screenshot_url or "").strip()[:512]

    day_key = _utcnow().date().isoformat()
    # Soft rate limit: count today's rows for this user.
    day_start = datetime.fromisoformat(f"{day_key}T00:00:00+00:00")
    used = int(
        (
            await db.execute(
                select(func.count())
                .select_from(ProductFeedback)
                .where(
                    ProductFeedback.user_id == user.id,
                    ProductFeedback.created_at >= day_start,
                )
            )
        ).scalar()
        or 0
    )
    if used >= _RATE_LIMIT_PER_DAY:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="今日反馈次数已达上限，请明天再试或稍后再写",
        )

    row = ProductFeedback(
        user_id=user.id,
        category=body.category,
        title=title[:200],
        body=text[:8000],
        contact=(body.contact or "").strip()[:120],
        app_version=(body.app_version or "").strip()[:64],
        screenshot_url=screenshot,
        status="open",
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return {
        "ok": True,
        "id": row.id,
        "message": "已提交，仅运营可见，其他用户看不到你的反馈",
    }


@router.get("/mine")
async def my_feedback(
    limit: int = Query(20, ge=1, le=50),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    rows = list(
        (
            await db.execute(
                select(ProductFeedback)
                .where(ProductFeedback.user_id == user.id)
                .order_by(ProductFeedback.id.desc())
                .limit(limit)
            )
        )
        .scalars()
        .all()
    )
    return {
        "items": [
            {
                "id": r.id,
                "category": r.category,
                "title": r.title,
                "body": r.body,
                "screenshot_url": r.screenshot_url or "",
                "status": r.status,
                "admin_note": r.admin_note or "",
                "created_at": r.created_at.isoformat() if r.created_at else None,
                "updated_at": r.updated_at.isoformat() if r.updated_at else None,
            }
            for r in rows
        ]
    }


@admin_router.get("")
async def admin_list_feedback(
    status_filter: str | None = Query(None, alias="status"),
    category: str | None = Query(None),
    q: str = Query("", max_length=120),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    filters = []
    if status_filter in ("open", "read", "done"):
        filters.append(ProductFeedback.status == status_filter)
    if category in (
        "bug",
        "ux",
        "content",
        "performance",
        "billing",
        "feature",
        "general",
    ):
        filters.append(ProductFeedback.category == category)
    needle = q.strip()
    stmt = select(ProductFeedback)
    count_stmt = select(func.count()).select_from(ProductFeedback)
    if filters:
        stmt = stmt.where(*filters)
        count_stmt = count_stmt.where(*filters)
    if needle:
        from sqlalchemy import or_

        like = f"%{needle}%"
        user_ids = list(
            (
                await db.execute(
                    select(User.id).where(
                        User.email.ilike(like)
                        | User.display_name.ilike(like)
                        | User.phone.ilike(like)
                    )
                )
            )
            .scalars()
            .all()
        )
        clauses = [
            ProductFeedback.title.ilike(like),
            ProductFeedback.body.ilike(like),
        ]
        if user_ids:
            clauses.append(ProductFeedback.user_id.in_(user_ids))
        text_filter = or_(*clauses)
        stmt = stmt.where(text_filter)
        count_stmt = count_stmt.where(text_filter)

    total = int((await db.execute(count_stmt)).scalar() or 0)
    rows = list(
        (
            await db.execute(
                stmt.order_by(ProductFeedback.id.desc()).offset(offset).limit(limit)
            )
        )
        .scalars()
        .all()
    )
    users = {
        u.id: u
        for u in (
            await db.execute(
                select(User).where(User.id.in_({r.user_id for r in rows} or {-1}))
            )
        )
        .scalars()
        .all()
    }
    open_count = int(
        (
            await db.execute(
                select(func.count())
                .select_from(ProductFeedback)
                .where(ProductFeedback.status == "open")
            )
        ).scalar()
        or 0
    )
    return {
        "total": total,
        "open_count": open_count,
        "offset": offset,
        "limit": limit,
        "items": [_serialize(r, users.get(r.user_id)) for r in rows],
    }


@admin_router.patch("/{feedback_id}")
async def admin_update_feedback(
    feedback_id: int,
    body: FeedbackStatusBody,
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    row = (
        await db.execute(
            select(ProductFeedback).where(ProductFeedback.id == feedback_id)
        )
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=404, detail="feedback_not_found")
    row.status = body.status
    if body.admin_note is not None:
        row.admin_note = (body.admin_note or "").strip()[:4000]
    row.updated_at = _utcnow()
    await db.commit()
    await db.refresh(row)
    user = (
        await db.execute(select(User).where(User.id == row.user_id))
    ).scalar_one_or_none()
    return {"ok": True, "item": _serialize(row, user)}
