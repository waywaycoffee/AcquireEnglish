from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import User, UserPreference
from app.schemas import PreferencesOut, PreferencesUpdate

router = APIRouter(prefix="/preferences", tags=["preferences"])


def _default_prefs(user_id: int) -> UserPreference:
    return UserPreference(
        user_id=user_id,
        level="A2",
        tags_json='["slow","daily"]',
        daily_quota=2,
        notify_daily_feed=1,
        bilibili_cookie=None,
    )


def _to_out(row: UserPreference) -> PreferencesOut:
    import json

    try:
        tags = json.loads(row.tags_json or "[]")
    except Exception:
        tags = []
    if not isinstance(tags, list):
        tags = []
    return PreferencesOut(
        level=row.level or "A2",
        tags=[str(t) for t in tags],
        daily_quota=row.daily_quota or 2,
        notify_daily_feed=bool(row.notify_daily_feed),
        has_bilibili_cookie=bool((row.bilibili_cookie or "").strip()),
        has_asr_api_key=bool((row.asr_api_key or "").strip()),
    )


@router.get("", response_model=PreferencesOut)
async def get_preferences(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> PreferencesOut:
    result = await db.execute(select(UserPreference).where(UserPreference.user_id == user.id))
    row = result.scalar_one_or_none()
    if row is None:
        row = _default_prefs(user.id)
        db.add(row)
        await db.commit()
        await db.refresh(row)
    return _to_out(row)


@router.put("", response_model=PreferencesOut)
async def put_preferences(
    payload: PreferencesUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> PreferencesOut:
    import json

    result = await db.execute(select(UserPreference).where(UserPreference.user_id == user.id))
    row = result.scalar_one_or_none()
    if row is None:
        row = _default_prefs(user.id)
        db.add(row)
    row.level = payload.level
    row.tags_json = json.dumps(payload.tags, ensure_ascii=False)
    row.daily_quota = payload.daily_quota
    row.notify_daily_feed = 1 if payload.notify_daily_feed else 0
    if payload.bilibili_cookie is not None:
        cleaned = payload.bilibili_cookie.strip()
        row.bilibili_cookie = cleaned or None
    if payload.asr_api_key is not None:
        key = payload.asr_api_key.strip()
        row.asr_api_key = key or None
    await db.commit()
    await db.refresh(row)
    return _to_out(row)
