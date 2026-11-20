"""Seed a few demo community posts so the feed is never empty on first boot."""

from __future__ import annotations

import secrets

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CommunityPost, User, UserPreference
from app.security import hash_password

_SEED_EMAIL = "community.seed@acquire.local"


async def ensure_community_seed(db: AsyncSession) -> None:
    count = int(
        (await db.execute(select(func.count()).select_from(CommunityPost))).scalar()
        or 0
    )
    if count > 0:
        return

    result = await db.execute(select(User).where(User.email == _SEED_EMAIL))
    seed_user = result.scalar_one_or_none()
    if seed_user is None:
        seed_user = User(
            email=_SEED_EMAIL,
            hashed_password=hash_password(secrets.token_urlsafe(24)),
            display_name="社区小助手",
        )
        db.add(seed_user)
        await db.flush()
        db.add(
            UserPreference(
                user_id=seed_user.id,
                level="B1",
                tags_json='["slow","daily","news"]',
                followed_creators_json=(
                    '[{"source":"bilibili","creator_id":"3764822",'
                    '"display_name":"老高與小茉",'
                    '"profile_url":"https://space.bilibili.com/3764822"}]'
                ),
            )
        )

    samples = [
        CommunityPost(
            user_id=seed_user.id,
            kind="feedback",
            title="希望导入进度能显示剩余时间",
            body="B 站合集导入时转圈比较久，如果能看到大概剩余时间会安心很多。",
        ),
        CommunityPost(
            user_id=seed_user.id,
            kind="method",
            title="我的三遍精听法",
            body=(
                "第一遍只听不看字幕，第二遍跟读影子跟读，第三遍收藏生词。"
                "每天 20 分钟比周末突击更稳。"
            ),
        ),
        CommunityPost(
            user_id=seed_user.id,
            kind="share_link",
            title="适合精听的新闻短片",
            body="语速适中，字幕干净，适合 A2–B1。",
            link_url="https://www.bilibili.com/video/BV1GJ411x7h7",
            link_title="示例分享 · 新闻短片",
        ),
    ]
    for post in samples:
        db.add(post)
    await db.commit()
