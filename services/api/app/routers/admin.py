"""Ops console: user management + user assets (token-gated)."""

from __future__ import annotations

import json
import logging
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps_admin import (
    require_admin_token,
    resolved_admin_token,
    resolved_admin_username,
    verify_admin_login,
)
from app.models import (
    CommerceEvent,
    CommunityPost,
    MembershipCoupon,
    Order,
    OrderItem,
    PointsLedger,
    ProductSku,
    RankState,
    User,
    UserEntitlement,
    UserLoginDay,
    UserPointsLedger,
    WalletAccount,
    WalletLedger,
)
from app.services import admin_user_assets as admin_assets_svc
from app.services import user_assets as assets_svc
from app.security import hash_password
from app.services.email_auth import normalize_email
from app.services.netdisk_share_link import netdisk_share_provider
from app.services.phone_auth import normalize_phone

router = APIRouter(prefix="/admin", tags=["admin"])
_audit_log = logging.getLogger("admin.actions")


def _iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.isoformat()


def _user_brief(user: User, *, wallet: WalletAccount | None = None) -> dict[str, Any]:
    return {
        "id": user.id,
        "email": user.email,
        "display_name": user.display_name,
        "phone": user.phone,
        "wechat_bound": bool(user.wechat_openid),
        "points_balance": int(user.points_balance or 0),
        "wallet_credits": int(wallet.balance_credits or 0) if wallet else None,
        "created_at": _iso(user.created_at),
    }


def _entitlement_out(row: UserEntitlement) -> dict[str, Any]:
    meta: Any = {}
    try:
        meta = json.loads(row.meta_json or "{}")
    except json.JSONDecodeError:
        meta = {}
    return {
        "id": row.id,
        "asset_kind": row.asset_kind,
        "asset_ref": row.asset_ref,
        "source": row.source,
        "status": row.status,
        "quantity": row.quantity,
        "starts_at": _iso(row.starts_at),
        "ends_at": _iso(row.ends_at),
        "order_id": row.order_id,
        "meta": meta if isinstance(meta, dict) else {},
        "created_at": _iso(row.created_at),
        "updated_at": _iso(row.updated_at),
    }


class GrantBody(BaseModel):
    asset_kind: str = Field(..., min_length=1, max_length=32)
    asset_ref: str = Field(..., min_length=1, max_length=160)
    quantity: int | None = None
    duration_days: int | None = Field(default=None, ge=1, le=3650)
    lifetime: bool = False
    source: str = Field(default="grant", max_length=24)
    meta: dict[str, Any] = Field(default_factory=dict)


class WalletAdjustBody(BaseModel):
    delta: int
    reason: str = Field(default="admin_adjust", max_length=64)
    note: str = ""


class PointsAdjustBody(BaseModel):
    delta: int
    reason: str = Field(default="admin_adjust", max_length=64)
    note: str = ""


class UserPatchBody(BaseModel):
    display_name: str | None = Field(default=None, max_length=120)
    email: str | None = Field(default=None, max_length=255)
    phone: str | None = Field(default=None, max_length=32)


class PasswordResetBody(BaseModel):
    new_password: str | None = Field(default=None, min_length=12, max_length=128)


class MembershipBody(BaseModel):
    level: str = Field(pattern="^(free|pro)$")
    duration_days: int = Field(default=30, ge=1, le=3650)


class PostPatchBody(BaseModel):
    title: str | None = Field(default=None, max_length=200)
    body: str | None = Field(default=None, max_length=4000)
    link_url: str | None = Field(default=None, max_length=1024)
    status: str | None = Field(default=None, pattern="^(visible|hidden)$")


class AdminLoginBody(BaseModel):
    username: str = Field(..., min_length=1, max_length=64)
    password: str = Field(..., min_length=1, max_length=256)
    token: str = Field(..., min_length=1, max_length=512)


@router.post("/login")
async def login(body: AdminLoginBody) -> dict[str, Any]:
    """Gate: username + password + login token. APIs still use X-Admin-Token after."""
    verify_admin_login(body.username, body.password, body.token)
    return {
        "ok": True,
        "username": resolved_admin_username(),
        "token": resolved_admin_token(),
        "token_file_hint": "acquireenglish-admin-login.token",
    }


@router.get("/ping")
async def ping(_: str = Depends(require_admin_token)) -> dict[str, Any]:
    return {
        "ok": True,
        "admin_configured": bool(resolved_admin_token()),
        "username_configured": bool(resolved_admin_username()),
    }


@router.get("/stats")
async def stats(
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    users = int((await db.execute(select(func.count()).select_from(User))).scalar() or 0)
    entitlements = int(
        (
            await db.execute(
                select(func.count())
                .select_from(UserEntitlement)
                .where(UserEntitlement.status == "active")
            )
        ).scalar()
        or 0
    )
    orders_paid = int(
        (
            await db.execute(
                select(func.count()).select_from(Order).where(Order.status == "paid")
            )
        ).scalar()
        or 0
    )
    wallet_sum = int(
        (await db.execute(select(func.coalesce(func.sum(WalletAccount.balance_credits), 0)))).scalar()
        or 0
    )
    points_sum = int(
        (await db.execute(select(func.coalesce(func.sum(User.points_balance), 0)))).scalar()
        or 0
    )
    return {
        "users": users,
        "active_entitlements": entitlements,
        "orders_paid": orders_paid,
        "wallet_credits_sum": wallet_sum,
        "points_sum": points_sum,
    }


@router.get("/users")
async def list_users(
    q: str = Query("", max_length=120),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    needle = q.strip()
    filters = []
    if needle:
        like = f"%{needle}%"
        filters = [
            User.email.ilike(like),
            User.display_name.ilike(like),
            User.phone.ilike(like),
        ]
        if needle.isdigit():
            filters.append(User.id == int(needle))
    where = or_(*filters) if filters else None
    count_stmt = select(func.count()).select_from(User)
    list_stmt = select(User)
    if where is not None:
        count_stmt = count_stmt.where(where)
        list_stmt = list_stmt.where(where)
    total = int((await db.execute(count_stmt)).scalar() or 0)
    rows = (
        await db.execute(
            list_stmt.order_by(User.created_at.desc(), User.id.desc())
            .offset(offset)
            .limit(limit)
        )
    ).scalars().all()
    user_ids = [u.id for u in rows]
    wallets: dict[int, WalletAccount] = {}
    asset_map: dict[int, dict[str, Any]] = {}
    if user_ids:
        wrows = (
            await db.execute(select(WalletAccount).where(WalletAccount.user_id.in_(user_ids)))
        ).scalars().all()
        wallets = {w.user_id: w for w in wrows}
        asset_map = await admin_assets_svc.batch_asset_summaries(db, user_ids)
    items = []
    for u in rows:
        brief = _user_brief(u, wallet=wallets.get(u.id))
        assets = asset_map.get(u.id) or {}
        brief.update(
            {
                "asset_count": int(assets.get("asset_count") or 0),
                "storage_bytes": int(assets.get("storage_bytes") or 0),
                "link_courses": int(assets.get("link_courses") or 0),
                "exam_assets": int(assets.get("exam_assets") or 0),
                "ocr_books": int(assets.get("ocr_books") or 0),
                "shared_subtitles": int(assets.get("shared_subtitles") or 0),
                "netdisk_bindings": int(assets.get("netdisk_bindings") or 0),
                "vocab_items": int(assets.get("vocab_items") or 0),
                "active_entitlements": int(assets.get("active_entitlements") or 0),
                "storage_breakdown": assets.get("storage_breakdown") or {},
            }
        )
        items.append(brief)
    return {
        "total": total,
        "offset": offset,
        "limit": limit,
        "items": items,
    }


@router.get("/users/{user_id}")
async def get_user(
    user_id: int,
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="user not found")
    wallet = await assets_svc.get_or_create_wallet(db, user_id)
    entitlements = (
        await db.execute(
            select(UserEntitlement)
            .where(UserEntitlement.user_id == user_id)
            .order_by(UserEntitlement.id.desc())
        )
    ).scalars().all()
    orders = (
        await db.execute(
            select(Order).where(Order.user_id == user_id).order_by(Order.id.desc()).limit(30)
        )
    ).scalars().all()
    assets = await admin_assets_svc.detailed_asset_report(db, user_id)
    wallet_ledger = (
        await db.execute(
            select(WalletLedger)
            .where(WalletLedger.user_id == user_id)
            .order_by(WalletLedger.id.desc())
            .limit(40)
        )
    ).scalars().all()
    points_ledger = (
        await db.execute(
            select(UserPointsLedger)
            .where(UserPointsLedger.user_id == user_id)
            .order_by(UserPointsLedger.id.desc())
            .limit(40)
        )
    ).scalars().all()
    brief = _user_brief(user, wallet=wallet)
    brief.update(
        {
            "asset_count": int(assets.get("asset_count") or 0),
            "storage_bytes": int(assets.get("storage_bytes") or 0),
            "membership_level": "pro" if any(
                e.asset_kind == "membership" and e.asset_ref == "pro"
                and e.status == "active" and (e.ends_at is None or
                (e.ends_at.replace(tzinfo=timezone.utc) if e.ends_at.tzinfo is None else e.ends_at) > datetime.now(timezone.utc))
                for e in entitlements
            ) else "free",
        }
    )
    return {
        "user": brief,
        "entitlements": [_entitlement_out(e) for e in entitlements],
        "orders": [
            {
                "id": o.id,
                "status": o.status,
                "provider": o.provider,
                "amount_cents": o.amount_cents,
                "currency": o.currency,
                "created_at": _iso(o.created_at),
                "paid_at": _iso(o.paid_at),
            }
            for o in orders
        ],
        "counts": {
            "link_courses": int(assets.get("link_courses") or 0),
            "vocab_items": int(assets.get("vocab_items") or 0),
            "exam_assets": int(assets.get("exam_assets") or 0),
            "ocr_books": int(assets.get("ocr_books") or 0),
            "shared_subtitles": int(assets.get("shared_subtitles") or 0),
            "netdisk_bindings": int(assets.get("netdisk_bindings") or 0),
            "active_entitlements": int(assets.get("active_entitlements") or 0),
            "lesson_progress": int(assets.get("lesson_progress") or 0),
            "asset_count": int(assets.get("asset_count") or 0),
            "entitlements": len(entitlements),
            "orders": len(orders),
        },
        "storage": {
            "storage_bytes": int(assets.get("storage_bytes") or 0),
            "breakdown": assets.get("storage_breakdown") or {},
            "media_cache_dir": assets.get("media_cache_dir"),
        },
        "assets": {
            "link_courses": assets.get("link_courses_items") or [],
            "exam_assets": assets.get("exam_assets_items") or [],
            "ocr_books": assets.get("ocr_books_items") or [],
            "shared_subtitles": assets.get("shared_subtitles_items") or [],
            "netdisk": assets.get("netdisk_items") or [],
        },
        "wallet_ledger": [
            {
                "id": r.id,
                "delta": r.delta,
                "reason": r.reason,
                "order_id": r.order_id,
                "created_at": _iso(r.created_at),
            }
            for r in wallet_ledger
        ],
        "points_ledger": [
            {
                "id": r.id,
                "delta": r.delta,
                "reason": r.reason,
                "ref": r.ref,
                "created_at": _iso(r.created_at),
            }
            for r in points_ledger
        ],
    }


@router.patch("/users/{user_id}")
async def patch_user(
    user_id: int,
    body: UserPatchBody,
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="user not found")
    if body.display_name is not None:
        name = body.display_name.strip()
        user.display_name = name or None
    if body.email is not None:
        try:
            email = normalize_email(body.email)
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        other = (await db.execute(select(User.id).where(User.email == email, User.id != user_id))).scalar_one_or_none()
        if other is not None:
            raise HTTPException(409, "邮箱已被其他账号使用")
        user.email = email
    if body.phone is not None:
        if not body.phone.strip():
            user.phone = None
        else:
            try:
                phone = normalize_phone(body.phone)
            except ValueError as exc:
                raise HTTPException(400, str(exc)) from exc
            other = (await db.execute(select(User.id).where(User.phone == phone, User.id != user_id))).scalar_one_or_none()
            if other is not None:
                raise HTTPException(409, "手机号已被其他账号使用")
            user.phone = phone
    await db.commit()
    _audit_log.warning("admin user profile updated user_id=%s", user_id)
    await db.refresh(user)
    wallet = await assets_svc.get_or_create_wallet(db, user_id)
    return {"user": _user_brief(user, wallet=wallet)}


@router.post("/users/{user_id}/password/reset")
async def reset_user_password(
    user_id: int,
    body: PasswordResetBody,
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(404, "user not found")
    generated = body.new_password is None
    password = body.new_password or secrets.token_urlsafe(24)
    user.hashed_password = hash_password(password)
    await db.commit()
    _audit_log.warning("admin password reset user_id=%s generated=%s", user_id, generated)
    return {"ok": True, "temporary_password": password if generated else None}


@router.put("/users/{user_id}/membership")
async def set_user_membership(
    user_id: int,
    body: MembershipBody,
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    from datetime import timedelta

    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(404, "user not found")
    row = (await db.execute(select(UserEntitlement).where(
        UserEntitlement.user_id == user_id,
        UserEntitlement.asset_kind == "membership",
        UserEntitlement.asset_ref == "pro",
    ))).scalar_one_or_none()
    if body.level == "free":
        if row is not None:
            row.status = "revoked"
    else:
        now = datetime.now(timezone.utc)
        if row is None:
            row = UserEntitlement(user_id=user_id, asset_kind="membership", asset_ref="pro")
            db.add(row)
        row.status = "active"
        row.source = "grant"
        row.starts_at = now
        row.ends_at = now + timedelta(days=body.duration_days)
        row.meta_json = json.dumps({"via": "admin_web", "admin_override": True})
    await db.commit()
    _audit_log.warning("admin membership changed user_id=%s level=%s", user_id, body.level)
    if row is not None:
        await db.refresh(row)
    return {"level": body.level, "entitlement": _entitlement_out(row) if row else None}


@router.get("/community/posts")
async def admin_list_posts(
    q: str = Query("", max_length=120),
    status: str = Query("", pattern="^(|visible|hidden)$"),
    limit: int = Query(40, ge=1, le=100),
    offset: int = Query(0, ge=0),
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(CommunityPost, User.display_name, User.email).join(User, User.id == CommunityPost.user_id)
    count = select(func.count()).select_from(CommunityPost)
    if q.strip():
        filt = or_(CommunityPost.title.ilike(f"%{q.strip()}%"), CommunityPost.body.ilike(f"%{q.strip()}%"))
        stmt, count = stmt.where(filt), count.where(filt)
    if status:
        stmt, count = stmt.where(CommunityPost.status == status), count.where(CommunityPost.status == status)
    total = int((await db.execute(count)).scalar() or 0)
    rows = (await db.execute(stmt.order_by(CommunityPost.id.desc()).offset(offset).limit(limit))).all()
    return {"total": total, "items": [{
        "id": post.id, "user_id": post.user_id, "author_name": name or email,
        "kind": post.kind, "title": post.title, "body": post.body,
        "link_url": post.link_url or "", "status": post.status,
        "created_at": _iso(post.created_at),
    } for post, name, email in rows]}


@router.patch("/community/posts/{post_id}")
async def admin_patch_post(
    post_id: int,
    body: PostPatchBody,
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    post = await db.get(CommunityPost, post_id)
    if post is None:
        raise HTTPException(404, "post not found")
    if body.title is not None:
        post.title = body.title.strip()
    if body.body is not None:
        post.body = body.body.strip()
    if body.link_url is not None:
        link = body.link_url.strip()
        if post.kind == "share_netdisk" and not netdisk_share_provider(link):
            raise HTTPException(400, "请填写受支持的 HTTPS 网盘链接")
        post.link_url = link or None
        if post.kind == "share_netdisk":
            from urllib.parse import parse_qs, urlparse
            try:
                meta = json.loads(post.meta_json or "{}")
            except json.JSONDecodeError:
                meta = {}
            meta["netdisk_provider"] = netdisk_share_provider(link)
            meta["share_code"] = parse_qs(urlparse(link).query).get("pwd", [""])[0]
            post.meta_json = json.dumps(meta, ensure_ascii=False)
    if body.status is not None:
        post.status = body.status
    await db.commit()
    _audit_log.warning("admin community post updated post_id=%s status=%s", post_id, post.status)
    return {"ok": True, "id": post.id, "status": post.status}


@router.post("/users/{user_id}/entitlements/grant")
async def grant_user_entitlement(
    user_id: int,
    body: GrantBody,
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="user not found")
    meta = dict(body.meta or {})
    meta.setdefault("admin", True)
    row = await assets_svc.grant_entitlement(
        db,
        user_id,
        asset_kind=body.asset_kind,
        asset_ref=body.asset_ref,
        source=body.source or "grant",
        quantity=body.quantity,
        duration_days=None if body.lifetime else body.duration_days,
        lifetime=bool(body.lifetime),
        meta=meta,
    )
    return {"entitlement": _entitlement_out(row)}


@router.post("/users/{user_id}/entitlements/{entitlement_id}/revoke")
async def revoke_entitlement(
    user_id: int,
    entitlement_id: int,
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    row = await db.get(UserEntitlement, entitlement_id)
    if row is None or row.user_id != user_id:
        raise HTTPException(status_code=404, detail="entitlement not found")
    row.status = "revoked"
    await db.commit()
    await db.refresh(row)
    return {"entitlement": _entitlement_out(row)}


@router.post("/users/{user_id}/wallet/adjust")
async def adjust_wallet(
    user_id: int,
    body: WalletAdjustBody,
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="user not found")
    if body.delta == 0:
        raise HTTPException(status_code=400, detail="delta must be non-zero")
    wallet = await assets_svc.credit_wallet(
        db,
        user_id,
        body.delta,
        reason=body.reason or "admin_adjust",
        meta={"note": body.note, "admin": True},
    )
    return {
        "wallet_credits": int(wallet.balance_credits or 0),
        "delta": int(body.delta),
    }


@router.post("/users/{user_id}/points/adjust")
async def adjust_points(
    user_id: int,
    body: PointsAdjustBody,
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="user not found")
    if body.delta == 0:
        raise HTTPException(status_code=400, detail="delta must be non-zero")
    new_balance = int(user.points_balance or 0) + int(body.delta)
    if new_balance < 0:
        raise HTTPException(status_code=400, detail="points balance cannot go negative")
    user.points_balance = new_balance
    db.add(
        UserPointsLedger(
            user_id=user_id,
            delta=int(body.delta),
            reason=(body.reason or "admin_adjust")[:64],
            ref=(body.note or "admin")[:255],
            client_share_id=f"admin-{user_id}-{int(datetime.now(tz=timezone.utc).timestamp())}-{abs(body.delta)}",
        )
    )
    await db.commit()
    await db.refresh(user)
    return {"points_balance": int(user.points_balance or 0), "delta": int(body.delta)}


@router.get("/skus")
async def list_skus(
    kind: str | None = Query(default=None, max_length=32),
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(ProductSku).order_by(ProductSku.id.asc())
    if kind:
        stmt = stmt.where(ProductSku.kind == kind.strip())
    rows = (await db.execute(stmt)).scalars().all()
    return {
        "items": [
            {
                "id": s.id,
                "sku_code": s.sku_code,
                "kind": s.kind,
                "title": s.title,
                "ref_id": s.ref_id,
                "price_cents": s.price_cents,
                "grant_quantity": s.grant_quantity,
                "duration_days": s.duration_days,
                "active": bool(s.active),
            }
            for s in rows
        ]
    }


@router.get("/commerce/overview")
async def commerce_overview(
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    now = datetime.now(tz=timezone.utc)
    day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    since_7d = now - timedelta(days=7)
    since_30d = now - timedelta(days=30)

    async def _count(stmt) -> int:
        return int((await db.execute(stmt)).scalar() or 0)

    sku_rows = (await db.execute(select(ProductSku))).scalars().all()
    by_kind: dict[str, int] = {}
    for s in sku_rows:
        by_kind[s.kind] = by_kind.get(s.kind, 0) + 1

    total_users = await _count(select(func.count()).select_from(User))
    new_users_today = await _count(
        select(func.count()).select_from(User).where(User.created_at >= day_start)
    )
    new_users_7d = await _count(
        select(func.count()).select_from(User).where(User.created_at >= since_7d)
    )
    new_users_30d = await _count(
        select(func.count()).select_from(User).where(User.created_at >= since_30d)
    )

    # Active Pro: status=active and not past ends_at (null ends_at = open-ended).
    active_pro = await _count(
        select(func.count())
        .select_from(UserEntitlement)
        .where(
            UserEntitlement.asset_kind == "membership",
            UserEntitlement.asset_ref == "pro",
            UserEntitlement.status == "active",
            or_(UserEntitlement.ends_at.is_(None), UserEntitlement.ends_at > now),
        )
    )
    new_pro_7d = await _count(
        select(func.count())
        .select_from(UserEntitlement)
        .where(
            UserEntitlement.asset_kind == "membership",
            UserEntitlement.asset_ref == "pro",
            UserEntitlement.created_at >= since_7d,
        )
    )

    order_status_rows = (
        await db.execute(select(Order.status, func.count()).group_by(Order.status))
    ).all()
    orders_by_status = {str(status): int(cnt) for status, cnt in order_status_rows}
    paid_orders = int(orders_by_status.get("paid", 0))
    unpaid_orders = int(orders_by_status.get("pending", 0)) + int(
        orders_by_status.get("created", 0)
    )
    paid_7d = await _count(
        select(func.count())
        .select_from(Order)
        .where(
            Order.status == "paid",
            or_(Order.paid_at >= since_7d, and_(Order.paid_at.is_(None), Order.created_at >= since_7d)),
        )
    )
    paid_cents_total = int(
        (
            await db.execute(
                select(func.coalesce(func.sum(Order.amount_cents), 0)).where(
                    Order.status == "paid"
                )
            )
        ).scalar()
        or 0
    )

    recent_users = (
        await db.execute(select(User).order_by(User.created_at.desc(), User.id.desc()).limit(12))
    ).scalars().all()

    trial_coupons = await _count(
        select(func.count())
        .select_from(MembershipCoupon)
        .where(MembershipCoupon.reward_code.like("trial_extend%"))
    )
    trial_used = await _count(
        select(func.count())
        .select_from(MembershipCoupon)
        .where(
            MembershipCoupon.reward_code.like("trial_extend%"),
            MembershipCoupon.used == 1,
        )
    )
    return {
        "skus_by_kind": by_kind,
        "users": {
            "total": total_users,
            "new_today": new_users_today,
            "new_7d": new_users_7d,
            "new_30d": new_users_30d,
            "active_pro": active_pro,
            "new_pro_7d": new_pro_7d,
            "recent": [
                {
                    "id": u.id,
                    "display_name": u.display_name,
                    "email": u.email,
                    "phone": u.phone,
                    "created_at": _iso(u.created_at),
                }
                for u in recent_users
            ],
        },
        "orders": {
            "by_status": orders_by_status,
            "paid": paid_orders,
            "unpaid": unpaid_orders,
            "paid_7d": paid_7d,
            "paid_amount_cents": paid_cents_total,
        },
        "trial": {
            "extend_coupons": trial_coupons,
            "extend_redeemed": trial_used,
            "login_day_rows": await _count(select(func.count()).select_from(UserLoginDay)),
        },
        "points_ledger_rows": await _count(select(func.count()).select_from(PointsLedger)),
        "rank_states": await _count(select(func.count()).select_from(RankState)),
        "commerce_events": await _count(select(func.count()).select_from(CommerceEvent)),
    }


@router.get("/commerce/orders")
async def commerce_orders(
    kind: str | None = Query(default=None, max_length=32),
    status_filter: str | None = Query(default=None, alias="status", max_length=24),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(Order).order_by(Order.id.desc())
    if status_filter:
        stmt = stmt.where(Order.status == status_filter.strip())
    rows = (await db.execute(stmt.offset(offset).limit(limit * 3))).scalars().all()
    items = []
    for order in rows:
        oitems = (
            await db.execute(select(OrderItem).where(OrderItem.order_id == order.id))
        ).scalars().all()
        sku_kinds: list[str] = []
        sku_codes: list[str] = []
        for oi in oitems:
            sku = await db.get(ProductSku, oi.sku_id)
            if sku is None:
                continue
            sku_kinds.append(sku.kind)
            sku_codes.append(sku.sku_code)
        if kind and kind.strip() not in sku_kinds:
            continue
        items.append(
            {
                "id": order.id,
                "user_id": order.user_id,
                "status": order.status,
                "provider": order.provider,
                "amount_cents": order.amount_cents,
                "sku_codes": sku_codes,
                "sku_kinds": sku_kinds,
                "created_at": _iso(order.created_at),
                "paid_at": _iso(order.paid_at),
            }
        )
        if len(items) >= limit:
            break
    return {"items": items, "offset": offset, "limit": limit}


@router.get("/commerce/points-ledger")
async def commerce_points_ledger_peek(
    user_id: int | None = Query(default=None),
    limit: int = Query(40, ge=1, le=200),
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(PointsLedger).order_by(PointsLedger.id.desc()).limit(limit)
    if user_id is not None:
        stmt = stmt.where(PointsLedger.user_id == user_id)
    rows = (await db.execute(stmt)).scalars().all()
    return {
        "items": [
            {
                "id": r.id,
                "user_id": r.user_id,
                "delta": r.delta,
                "direction": r.direction,
                "reason": r.reason,
                "created_at": _iso(r.created_at),
            }
            for r in rows
        ]
    }


@router.get("/commerce/events")
async def commerce_events_peek(
    event: str | None = Query(default=None, max_length=64),
    limit: int = Query(50, ge=1, le=200),
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(CommerceEvent).order_by(CommerceEvent.id.desc()).limit(limit)
    if event:
        stmt = stmt.where(CommerceEvent.event == event.strip())
    rows = (await db.execute(stmt)).scalars().all()
    return {
        "items": [
            {
                "id": r.id,
                "user_id": r.user_id,
                "event": r.event,
                "module": r.module,
                "page": r.page,
                "created_at": _iso(r.created_at),
            }
            for r in rows
        ]
    }


class PublishSeriesBody(BaseModel):
    publisher_user_id: int
    series_key: str = Field(min_length=4, max_length=64)
    slug: str = Field(min_length=2, max_length=64)
    title: str | None = Field(default=None, max_length=512)
    license_note: str = Field(default="", max_length=2000)
    status: str = Field(default="published", pattern="^(pending|published|rejected)$")


@router.get("/published-series")
async def admin_list_published_series(
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    from app.models import PublishedNetdiskSeries

    rows = (
        await db.execute(
            select(PublishedNetdiskSeries).order_by(PublishedNetdiskSeries.id.desc())
        )
    ).scalars().all()
    return {
        "items": [
            {
                "id": r.id,
                "slug": r.slug,
                "title": r.title,
                "publisher_user_id": r.publisher_user_id,
                "series_key": r.series_key,
                "status": r.status,
                "license_note": r.license_note,
                "course_id": f"public-series-{r.slug}",
                "reviewed_at": _iso(r.reviewed_at),
                "reviewed_by": r.reviewed_by,
            }
            for r in rows
        ]
    }


@router.post("/published-series")
async def admin_publish_series(
    body: PublishSeriesBody,
    _: str = Depends(require_admin_token),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    from app.services.published_series import upsert_published_series

    try:
        pub = await upsert_published_series(
            db,
            publisher_user_id=body.publisher_user_id,
            series_key=body.series_key.strip(),
            slug=body.slug,
            title=body.title,
            license_note=body.license_note,
            reviewed_by="admin",
            status=body.status,
        )
    except ValueError as exc:
        code = str(exc)
        if code == "series_not_found":
            raise HTTPException(404, "series not found for publisher") from exc
        if code == "slug_taken":
            raise HTTPException(409, "slug already taken") from exc
        raise HTTPException(400, code) from exc
    _audit_log.warning(
        "admin published series slug=%s publisher=%s key=%s",
        pub.slug,
        pub.publisher_user_id,
        pub.series_key,
    )
    return {
        "ok": True,
        "id": pub.id,
        "slug": pub.slug,
        "course_id": f"public-series-{pub.slug}",
        "status": pub.status,
        "title": pub.title,
    }
