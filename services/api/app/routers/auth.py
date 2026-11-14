from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.deps import get_current_user
from app.models import User
from app.schemas import (
    SmsLoginIn,
    SmsSendIn,
    SmsSendOut,
    TokenOut,
    UserCreate,
    UserLogin,
    UserOut,
    WechatLoginIn,
)
from app.security import create_access_token, hash_password, verify_password
from app.services.phone_auth import (
    deliver_sms,
    issue_sms_code,
    normalize_phone,
    phone_synthetic_email,
    random_password_hash as phone_password_hash,
    sms_mock_enabled,
    verify_sms_code,
)
from app.services.wechat_auth import (
    exchange_wechat_code,
    random_password_hash as wechat_password_hash,
    wechat_synthetic_email,
)

router = APIRouter(prefix="/auth", tags=["auth"])


def _token_for(user: User, *, is_new_user: bool = False) -> TokenOut:
    return TokenOut(
        access_token=create_access_token(user.email),
        user=UserOut.from_user(user),
        is_new_user=is_new_user,
    )


@router.post("/register", response_model=TokenOut)
async def register(payload: UserCreate, db: AsyncSession = Depends(get_db)) -> TokenOut:
    existing = await db.execute(select(User).where(User.email == payload.email.lower()))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")

    user = User(
        email=payload.email.lower(),
        hashed_password=hash_password(payload.password),
        display_name=payload.display_name or payload.email.split("@")[0],
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return _token_for(user, is_new_user=True)


@router.post("/login", response_model=TokenOut)
async def login(payload: UserLogin, db: AsyncSession = Depends(get_db)) -> TokenOut:
    result = await db.execute(select(User).where(User.email == payload.email.lower()))
    user = result.scalar_one_or_none()
    if user is None or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")
    return _token_for(user)


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
    return _token_for(user, is_new_user=is_new)


@router.post("/wechat/login", response_model=TokenOut)
async def wechat_login(payload: WechatLoginIn, db: AsyncSession = Depends(get_db)) -> TokenOut:
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
    return _token_for(user, is_new_user=is_new)


@router.get("/me", response_model=UserOut)
async def me(user: User = Depends(get_current_user)) -> UserOut:
    return UserOut.from_user(user)
