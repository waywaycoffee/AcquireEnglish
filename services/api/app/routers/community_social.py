"""Ownership, block-aware interactions, and moderation for community content."""
import secrets
from datetime import timedelta
from typing import Literal
from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import select, delete, update, func, or_
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.deps import get_current_user
from app.config import settings
from app.models import (CommunityFollow, CommunityBookmark, CommunityNotice, CommunityReport,
                        CommunityPost, DeskBlock, DeskMember, User, CommunityNoticePreference)
from app.routers.study_desk import blocked, name, now, no_store
from app.services.study_rewards import insert

router = APIRouter(prefix='/community-social', tags=['community-social'], dependencies=[Depends(no_store)])


def blocked_ids(uid):
    return select(DeskBlock.blocked_id).where(DeskBlock.user_id == uid).union(select(DeskBlock.user_id).where(DeskBlock.blocked_id == uid))


async def visible_post(db, uid, post_id):
    post = await db.get(CommunityPost, post_id)
    if post is None or post.status != 'visible' or await blocked(db, uid, post.user_id):
        raise HTTPException(404, '帖子不存在或不可访问')
    return post


async def post_guard(request: Request, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    pid = request.path_params.get('post_id')
    if pid is not None:
        try:
            post_id = int(pid)
        except ValueError:
            raise HTTPException(404, '帖子不存在')
        await visible_post(db, user.id, post_id)


async def notice(db, recipient, actor, event, text, post_id=None):
    preference = await db.get(CommunityNoticePreference, recipient)
    if recipient == actor or await blocked(db, recipient, actor) or (preference is not None and not preference.enabled):
        return False
    added = (await db.execute(insert(db, CommunityNotice).values(user_id=recipient, actor_id=actor, event_key=event, text=text, post_id=post_id, read=0).on_conflict_do_nothing().returning(CommunityNotice.id))).scalar_one_or_none()
    return added is not None


class ReportIn(BaseModel):
    reason: str = Field(min_length=2, max_length=500)


class ReviewIn(BaseModel):
    action: Literal['hide', 'dismiss']
    note: str = Field(min_length=2, max_length=500)


@router.get('')
async def social_state(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    follows = list((await db.execute(select(CommunityFollow.target_id).where(CommunityFollow.user_id == user.id))).scalars())
    bookmarks = list((await db.execute(select(CommunityBookmark.post_id).join(CommunityPost, CommunityPost.id == CommunityBookmark.post_id).where(CommunityBookmark.user_id == user.id, CommunityPost.status == 'visible', CommunityPost.user_id.not_in(blocked_ids(user.id))))).scalars())
    blocks = list((await db.execute(select(DeskBlock.blocked_id).where(DeskBlock.user_id == user.id))).scalars())
    preference = await db.get(CommunityNoticePreference, user.id)
    return {'notifications_enabled': preference.enabled == 1 if preference else True, 'my_id': user.id, 'following': follows, 'bookmarks': bookmarks, 'blocks': blocks}


@router.put('/following/{target_id}')
async def follow(target_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    if target_id == user.id or await db.get(User, target_id) is None or await blocked(db, user.id, target_id):
        raise HTTPException(400, '无法关注该用户')
    await db.execute(insert(db, CommunityFollow).values(user_id=user.id, target_id=target_id).on_conflict_do_nothing())
    await notice(db, target_id, user.id, f'follow:{user.id}', f'{name(user)}关注了你')
    await db.commit()
    return {'following': True}


@router.delete('/following/{target_id}')
async def unfollow(target_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await db.execute(delete(CommunityFollow).where(CommunityFollow.user_id == user.id, CommunityFollow.target_id == target_id))
    await db.commit()
    return {'following': False}


@router.put('/bookmarks/{post_id}')
async def bookmark(post_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await visible_post(db, user.id, post_id)
    await db.execute(insert(db, CommunityBookmark).values(user_id=user.id, post_id=post_id).on_conflict_do_nothing())
    await db.commit()
    return {'bookmarked': True}


@router.delete('/bookmarks/{post_id}')
async def unbookmark(post_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await db.execute(delete(CommunityBookmark).where(CommunityBookmark.user_id == user.id, CommunityBookmark.post_id == post_id))
    await db.commit()
    return {'bookmarked': False}


@router.put('/blocks/{target_id}')
async def block_user(target_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    if target_id == user.id or await db.get(User, target_id) is None:
        raise HTTPException(400, '无法屏蔽该用户')
    await db.execute(insert(db, DeskBlock).values(user_id=user.id, blocked_id=target_id).on_conflict_do_nothing())
    await db.execute(delete(CommunityFollow).where(or_((CommunityFollow.user_id == user.id) & (CommunityFollow.target_id == target_id), (CommunityFollow.user_id == target_id) & (CommunityFollow.target_id == user.id))))
    me, other = await db.get(DeskMember, user.id), await db.get(DeskMember, target_id)
    if me and other and me.desk_id == other.desk_id:
        await db.execute(delete(DeskMember).where(DeskMember.desk_id == me.desk_id))
    await db.commit()
    return {'blocked': True}


@router.delete('/blocks/{target_id}')
async def unblock(target_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await db.execute(delete(DeskBlock).where(DeskBlock.user_id == user.id, DeskBlock.blocked_id == target_id))
    await db.commit()
    return {'blocked': False}


@router.delete('/posts/{post_id}')
async def delete_post(post_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    post = await db.get(CommunityPost, post_id)
    if post is None or post.user_id != user.id:
        raise HTTPException(404, '帖子不存在')
    post.status = 'hidden'
    await db.commit()
    return {'status': 'deleted'}


@router.post('/posts/{post_id}/report', status_code=201)
async def report(post_id: int, payload: ReportIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await visible_post(db, user.id, post_id)
    daily = await db.scalar(select(func.count()).select_from(CommunityReport).where(CommunityReport.user_id == user.id, CommunityReport.created_at >= now() - timedelta(days=1)))
    if daily >= 20:
        raise HTTPException(429, '今天的举报数量已达上限')
    await db.execute(insert(db, CommunityReport).values(user_id=user.id, post_id=post_id, reason=payload.reason.strip(), status='pending', review_note='').on_conflict_do_nothing())
    await db.commit()
    return {'status': 'pending'}


@router.get('/reports')
async def my_reports(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(select(CommunityReport).where(CommunityReport.user_id == user.id).order_by(CommunityReport.id.desc()).limit(50))).scalars()
    return {'reports': [{'id': r.id, 'post_id': r.post_id, 'status': r.status, 'review_note': r.review_note} for r in rows]}


def admin(token):
    if not settings.community_admin_token or not secrets.compare_digest(token, settings.community_admin_token):
        raise HTTPException(403, '需要社区管理员凭据')


@router.get('/moderation')
async def moderation(token: str = Header('', alias='X-Community-Admin-Token'), db: AsyncSession = Depends(get_db)):
    admin(token)
    rows = (await db.execute(select(CommunityReport).where(CommunityReport.status == 'pending').order_by(CommunityReport.id).limit(100))).scalars()
    return {'reports': [{'id': r.id, 'post_id': r.post_id, 'reason': r.reason} for r in rows]}


@router.post('/moderation/{report_id}')
async def review(report_id: int, payload: ReviewIn, token: str = Header('', alias='X-Community-Admin-Token'), db: AsyncSession = Depends(get_db)):
    admin(token)
    row = await db.get(CommunityReport, report_id)
    if row is None or row.status != 'pending':
        raise HTTPException(409, '举报已处理或不存在')
    if payload.action == 'hide':
        post = await db.get(CommunityPost, row.post_id)
        if post:
            post.status = 'hidden'
    row.status, row.review_note = payload.action, payload.note
    row.reviewed_at = now()
    await db.commit()
    return {'status': row.status}


@router.get('/notices')
async def notices(before: int | None = None, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    stmt = select(CommunityNotice).where(CommunityNotice.user_id == user.id, CommunityNotice.actor_id.not_in(blocked_ids(user.id)))
    if before:
        stmt = stmt.where(CommunityNotice.id < before)
    rows = (await db.execute(stmt.order_by(CommunityNotice.id.desc()).limit(50))).scalars()
    return {'notices': [{'id': r.id, 'text': r.text, 'post_id': r.post_id, 'read': bool(r.read), 'created_at': r.created_at} for r in rows]}


@router.put('/notices/{notice_id}/read')
async def read_notice(notice_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await db.execute(update(CommunityNotice).where(CommunityNotice.id == notice_id, CommunityNotice.user_id == user.id).values(read=1))
    await db.commit()
    return {'status': 'read'}


@router.get('/posts/{post_id}')
async def read_post(post_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    from app.routers.community import _serialize_post
    from app.models import CommunityPostLike
    post = await visible_post(db, user.id, post_id)
    author = await db.get(User, post.user_id)
    liked = (await db.execute(select(CommunityPostLike).where(CommunityPostLike.post_id == post.id, CommunityPostLike.user_id == user.id))).scalar_one_or_none()
    return _serialize_post(post, author=author, author_level=None, liked_by_me=liked is not None)


class LikeIn(BaseModel):
    enabled: bool


@router.put('/posts/{post_id}/like')
async def like(post_id: int, payload: LikeIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    from app.models import CommunityPostLike
    post = await visible_post(db, user.id, post_id)
    if payload.enabled:
        await db.execute(insert(db, CommunityPostLike).values(user_id=user.id, post_id=post_id).on_conflict_do_nothing())
        await notice(db, post.user_id, user.id, f'like:{post.id}:{user.id}', f'{name(user)}赞了你的帖子', post.id)
    else:
        await db.execute(delete(CommunityPostLike).where(CommunityPostLike.user_id == user.id, CommunityPostLike.post_id == post_id))
    post.like_count = await db.scalar(select(func.count()).select_from(CommunityPostLike).where(CommunityPostLike.post_id == post_id))
    await db.commit()
    return await read_post(post_id, user, db)


class NoticePreferenceIn(BaseModel):
    enabled: bool


@router.put('/notifications')
async def notice_preference(payload: NoticePreferenceIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await db.execute(insert(db, CommunityNoticePreference).values(user_id=user.id, enabled=int(payload.enabled)).on_conflict_do_update(index_elements=['user_id'], set_={'enabled': int(payload.enabled)}))
    await db.commit()
    return {'enabled': payload.enabled}
