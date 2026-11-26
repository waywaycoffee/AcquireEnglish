from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.deps import bearer, get_current_user
from app.models import User
from app.schemas import (
    AuthSessionOut,
    EmailSendIn,
    EmailSendOut,
    SmsLoginIn,
    SmsSendIn,
    SmsSendOut,
    TokenOut,
    UserCreate,
    UserLogin,
    UserOut,
    WechatLoginIn,
)
from app.security import (
    create_access_token,
    decode_access_token_full,
    hash_password,
    verify_password,
)
from app.services.auth_sessions import (
    issue_auth_session,
    list_auth_sessions,
    revoke_auth_session,
)
from fastapi.security import HTTPAuthorizationCredentials
from app.services.email_auth import (
    deliver_email_code,
    email_mock_enabled,
    email_delivery_ready,
    issue_email_code,
    normalize_email,
    verify_email_code,
)
from app.services.phone_auth import (
    deliver_sms,
    issue_sms_code,
    normalize_phone,
    phone_synthetic_email,
    random_password_hash as phone_password_hash,
    sms_mock_enabled,
    verify_sms_code,
)
from app.services.member_no import ensure_member_no
from app.services.wechat_auth import (
    exchange_wechat_code,
    exchange_wechat_mp_code,
    random_password_hash as wechat_password_hash,
    wechat_synthetic_email,
)

router = APIRouter(prefix="/auth", tags=["auth"])


async def _token_for(
    db: AsyncSession,
    user: User,
    *,
    is_new_user: bool = False,
    device_id: str | None = None,
    device_label: str | None = None,
) -> TokenOut:
    session = await issue_auth_session(
        db,
        user_id=user.id,
        device_id=device_id,
        device_label=device_label,
    )
    return TokenOut(
        access_token=create_access_token(user.email, session_id=session.id),
        user=UserOut.from_user(user),
        is_new_user=is_new_user,
    )


async def _record_login_day(db: AsyncSession, user: User) -> None:
    """Track UTC login days for trial-extend streak (idempotent)."""
    try:
        from app.services.commerce.trial import record_user_login_day

        await record_user_login_day(db, user.id)
    except Exception:  # noqa: BLE001 — auth must not fail on streak bookkeeping
        pass


async def _ensure_default_pro(db: AsyncSession, user: User) -> None:
    """Re-apply lifetime Pro for owner/demo accounts (e.g. weiwei)."""
    try:
        from app.services.owner_pro_seed import ensure_user_default_pro

        await ensure_user_default_pro(db, user)
    except Exception:  # noqa: BLE001 — auth must not fail on Pro grant
        pass


async def _after_auth_success(
    db: AsyncSession, user: User, *, is_new: bool = False
) -> None:
    # Assign / backfill public registration serial (AE-000123).
    await ensure_member_no(db, user)
    # Pro welcome month is claim-once via popup (POST /commerce/trial/claim-welcome).
    await _ensure_default_pro(db, user)
    await _record_login_day(db, user)


@router.post("/email/send", response_model=EmailSendOut)
async def email_send(payload: EmailSendIn, db: AsyncSession = Depends(get_db)) -> EmailSendOut:
    if not email_delivery_ready():
        raise HTTPException(status_code=503, detail="邮箱注册暂未开放")
    try:
        email = normalize_email(str(payload.email))
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    existing = await db.execute(select(User).where(User.email == email))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="该邮箱已注册")
    code = issue_email_code(email)
    try:
        await deliver_email_code(email, code)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"验证码发送失败：{exc}",
        ) from exc
    mock = email_mock_enabled()
    return EmailSendOut(
        ok=True,
        expires_in=settings.auth_email_code_ttl_seconds,
        mock=mock,
        debug_code=code if mock else None,
    )


@router.post("/register", response_model=TokenOut)
async def register(payload: UserCreate, db: AsyncSession = Depends(get_db)) -> TokenOut:
    if settings.production_mode and not email_delivery_ready():
        raise HTTPException(status_code=503, detail="邮箱注册暂未开放")
    try:
        email = normalize_email(str(payload.email))
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    existing = await db.execute(select(User).where(User.email == email))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="该邮箱已注册")
    if not verify_email_code(email, payload.code):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="邮箱验证码错误或已过期",
        )

    user = User(
        email=email,
        hashed_password=hash_password(payload.password),
        display_name=payload.display_name or email.split("@")[0],
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    await _after_auth_success(db, user, is_new=True)
    return await _token_for(
        db,
        user,
        is_new_user=True,
        device_id=payload.device_id,
        device_label=payload.device_label,
    )


@router.post("/login", response_model=TokenOut)
async def login(payload: UserLogin, db: AsyncSession = Depends(get_db)) -> TokenOut:
    result = await db.execute(select(User).where(User.email == payload.email.lower()))
    user = result.scalar_one_or_none()
    if user is None or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")
    await _after_auth_success(db, user, is_new=False)
    return await _token_for(
        db,
        user,
        device_id=payload.device_id,
        device_label=payload.device_label,
    )


@router.post("/sms/send", response_model=SmsSendOut)
async def sms_send(payload: SmsSendIn) -> SmsSendOut:
    try:
        phone = normalize_phone(payload.phone)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    code = issue_sms_code(phone)
    try:
        await deliver_sms(phone, code)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"短信发送失败：{exc}",
        ) from exc
    mock = sms_mock_enabled()
    return SmsSendOut(
        ok=True,
        expires_in=settings.auth_sms_code_ttl_seconds,
        mock=mock,
        debug_code=code if mock else None,
    )


@router.post("/sms/login", response_model=TokenOut)
async def sms_login(payload: SmsLoginIn, db: AsyncSession = Depends(get_db)) -> TokenOut:
    try:
        phone = normalize_phone(payload.phone)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    if not verify_sms_code(phone, payload.code):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="验证码错误或已过期")

    result = await db.execute(select(User).where(User.phone == phone))
    user = result.scalar_one_or_none()
    is_new = False
    if user is None:
        email = phone_synthetic_email(phone)
        clash = await db.execute(select(User).where(User.email == email))
        if clash.scalar_one_or_none():
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="该手机号账号冲突，请联系支持")
        is_new = True
        user = User(
            email=email,
            hashed_password=phone_password_hash(),
            display_name=f"用户{phone[-4:]}",
            phone=phone,
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)
    await _after_auth_success(db, user, is_new=is_new)
    return await _token_for(
        db,
        user,
        is_new_user=is_new,
        device_id=payload.device_id,
        device_label=payload.device_label,
    )


@router.post("/wechat/login", response_model=TokenOut)
async def wechat_login(payload: WechatLoginIn, db: AsyncSession = Depends(get_db)) -> TokenOut:
    if not settings.wechat_mock_enabled and not settings.wechat_configured:
        raise HTTPException(status_code=503, detail="微信登录暂未开放")
    try:
        identity = await exchange_wechat_code(payload.code)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc

    clauses = [User.wechat_openid == identity.openid]
    if identity.unionid:
        clauses.append(User.wechat_unionid == identity.unionid)
    result = await db.execute(select(User).where(or_(*clauses)))
    user = result.scalar_one_or_none()
    is_new = False
    if user is None:
        email = wechat_synthetic_email(identity.openid)
        clash = await db.execute(select(User).where(User.email == email))
        if clash.scalar_one_or_none():
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="该微信账号冲突，请联系支持")
        is_new = True
        display = (payload.nickname or identity.nickname or "微信用户").strip()[:120]
        user = User(
            email=email,
            hashed_password=wechat_password_hash(),
            display_name=display or "微信用户",
            wechat_openid=identity.openid,
            wechat_unionid=identity.unionid,
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)
    else:
        dirty = False
        if identity.unionid and not user.wechat_unionid:
            user.wechat_unionid = identity.unionid
            dirty = True
        if not user.wechat_openid:
            user.wechat_openid = identity.openid
            dirty = True
        if dirty:
            await db.commit()
            await db.refresh(user)
    await _after_auth_success(db, user, is_new=is_new)
    return await _token_for(
        db,
        user,
        is_new_user=is_new,
        device_id=payload.device_id,
        device_label=payload.device_label,
    )


@router.post("/wechat/mp-login", response_model=TokenOut)
async def wechat_mp_login(
    payload: WechatLoginIn, db: AsyncSession = Depends(get_db)
) -> TokenOut:
    """WeChat mini program login (js_code → openid). Prefer UnionID merge with App."""
    if not settings.wechat_mp_mock_enabled and not settings.wechat_mp_configured:
        raise HTTPException(status_code=503, detail="微信小程序登录暂未开放")
    try:
        identity = await exchange_wechat_mp_code(payload.code)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc

    clauses = [User.wechat_mp_openid == identity.openid]
    if identity.unionid:
        clauses.append(User.wechat_unionid == identity.unionid)
    result = await db.execute(select(User).where(or_(*clauses)))
    user = result.scalar_one_or_none()
    is_new = False
    if user is None:
        email = wechat_synthetic_email(f"mp_{identity.openid}")
        clash = await db.execute(select(User).where(User.email == email))
        if clash.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT, detail="该小程序微信账号冲突，请联系支持"
            )
        is_new = True
        display = (payload.nickname or identity.nickname or "微信用户").strip()[:120]
        user = User(
            email=email,
            hashed_password=wechat_password_hash(),
            display_name=display or "微信用户",
            wechat_mp_openid=identity.openid,
            wechat_unionid=identity.unionid,
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)
    else:
        dirty = False
        if identity.unionid and not user.wechat_unionid:
            user.wechat_unionid = identity.unionid
            dirty = True
        if not user.wechat_mp_openid:
            user.wechat_mp_openid = identity.openid
            dirty = True
        if dirty:
            await db.commit()
            await db.refresh(user)
    await _after_auth_success(db, user, is_new=is_new)
    return await _token_for(
        db,
        user,
        is_new_user=is_new,
        device_id=payload.device_id,
        device_label=payload.device_label or "wechat-miniprogram",
    )


@router.get("/me", response_model=UserOut)
async def me(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> UserOut:
    await ensure_member_no(db, user)
    return UserOut.from_user(user)


@router.get("/sessions", response_model=list[AuthSessionOut])
async def sessions(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
) -> list[AuthSessionOut]:
    current_sid = None
    if credentials is not None and credentials.scheme.lower() == "bearer":
        _, current_sid = decode_access_token_full(credentials.credentials)
    rows = await list_auth_sessions(db, user_id=user.id)
    return [
        AuthSessionOut(
            id=row.id,
            device_id=row.device_id,
            device_label=row.device_label or "",
            created_at=row.created_at,
            last_seen_at=row.last_seen_at,
            current=bool(current_sid and row.id == current_sid),
        )
        for row in rows
    ]


@router.delete("/sessions/{session_id}")
async def delete_session(
    session_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, bool]:
    ok = await revoke_auth_session(db, user_id=user.id, session_id=session_id)
    if not ok:
        raise HTTPException(status_code=404, detail="会话不存在")
    return {"ok": True}
