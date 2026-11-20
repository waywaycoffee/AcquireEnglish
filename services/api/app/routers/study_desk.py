"""One-to-one study desks with revocable, default-private sharing."""
from datetime import datetime, timedelta, timezone
import re
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, or_, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import (DeskInvite, DeskMember, DeskBlock, DeskLibraryWord, DeskLibrarySnapshot,
                        LessonProgress, User, UserLinkCourse, UserStudyStatsDaily, UserAvatarLoadout)
from app.course_data import get_course


def no_store(response: Response):
    response.headers['Cache-Control'] = 'no-store'


router = APIRouter(prefix='/study-desk', tags=['study-desk'], dependencies=[Depends(no_store)])


def now():
    return datetime.now(timezone.utc)


def aware(value):
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value


def name(user):
    return (user.display_name or f'学员{user.id:04d}')[:40]


async def blocked(db, a, b):
    return (await db.execute(select(DeskBlock).where(or_(
        (DeskBlock.user_id == a) & (DeskBlock.blocked_id == b),
        (DeskBlock.user_id == b) & (DeskBlock.blocked_id == a),
    )))).first() is not None


async def pair(db, user_id):
    me = await db.get(DeskMember, user_id)
    if me is None:
        raise HTTPException(409, '尚未建立同桌关系')
    peer = (await db.execute(select(DeskMember).where(
        DeskMember.desk_id == me.desk_id, DeskMember.user_id != user_id))).scalar_one_or_none()
    if peer is None or await blocked(db, user_id, peer.user_id):
        raise HTTPException(409, '同桌关系已解除')
    return me, peer


class InviteIn(BaseModel):
    target_id: int = Field(gt=0)


class ConsentIn(BaseModel):
    share_activity: bool = False
    share_videos: bool = False
    share_library: bool = False


class LibraryIn(BaseModel):
    words: list[str] = Field(max_length=20000)


@router.get('')
async def overview(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    me = await db.get(DeskMember, user.id)
    peer = None
    if me:
        _, member = await pair(db, user.id)
        other = await db.get(User, member.user_id)
        avatar_rows = (await db.execute(select(UserAvatarLoadout).where(UserAvatarLoadout.user_id == other.id))).scalars().all()
        peer = {'id': other.id, 'name': name(other), 'avatar': {r.slot: r.sku for r in avatar_rows}, 'sharing': {
            'activity': bool(member.share_activity), 'videos': bool(member.share_videos),
            'library': bool(member.share_library)}}
    rows = (await db.execute(select(DeskInvite).where(
        or_(DeskInvite.sender_id == user.id, DeskInvite.target_id == user.id),
        DeskInvite.status == 'pending', DeskInvite.expires_at > now(),
    ).order_by(DeskInvite.id.desc()).limit(50))).scalars().all()
    invites = []
    for row in rows:
        other_id = row.target_id if row.sender_id == user.id else row.sender_id
        if await blocked(db, user.id, other_id):
            continue
        other = await db.get(User, other_id)
        invites.append({'id': row.id, 'incoming': row.target_id == user.id,
                        'name': name(other), 'expires_at': row.expires_at})
    return {'my_id': user.id, 'peer': peer, 'invites': invites,
            'sharing': {'activity': bool(me and me.share_activity),
                        'videos': bool(me and me.share_videos), 'library': bool(me and me.share_library)}}


@router.post('/invites', status_code=201)
async def invite(payload: InviteIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    if payload.target_id == user.id:
        raise HTTPException(400, '不能邀请自己')
    target = await db.get(User, payload.target_id)
    if target is None or await blocked(db, user.id, payload.target_id):
        raise HTTPException(404, '无法邀请该用户')
    if await db.get(DeskMember, user.id) or await db.get(DeskMember, target.id):
        raise HTTPException(409, '你或对方已拥有正式同桌')
    existing = (await db.execute(select(DeskInvite).where(
        DeskInvite.sender_id == user.id, DeskInvite.target_id == target.id,
        DeskInvite.status == 'pending', DeskInvite.expires_at > now()))).scalars().first()
    if existing:
        return {'id': existing.id}
    daily = await db.scalar(select(func.count()).select_from(DeskInvite).where(
        DeskInvite.sender_id == user.id, DeskInvite.created_at > now() - timedelta(days=1)))
    if daily >= 5:
        raise HTTPException(429, '每天最多发起5次邀请')
    row = DeskInvite(sender_id=user.id, target_id=target.id, status='pending', expires_at=now() + timedelta(hours=24))
    db.add(row)
    await db.flush()
    from app.routers.community_social import notice
    await notice(db, target.id, user.id, f'desk-invite:{row.id}', f'{name(user)}邀请你成为同桌，请进入一起练处理')
    await db.commit()
    return {'id': row.id}


@router.post('/invites/{invite_id}/{action}')
async def act(invite_id: int, action: Literal['accept', 'decline', 'cancel'], user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    row = await db.get(DeskInvite, invite_id)
    expected = row.sender_id if row and action == 'cancel' else row.target_id if row else None
    if row is None or expected != user.id:
        raise HTTPException(404, '邀请不存在')
    if row.status != 'pending' or aware(row.expires_at) <= now():
        raise HTTPException(409, '邀请已处理或过期')
    if await blocked(db, row.sender_id, row.target_id):
        raise HTTPException(403, '无法处理该邀请')
    status = {'accept': 'accepted', 'decline': 'declined', 'cancel': 'cancelled'}[action]
    try:
        changed = await db.execute(update(DeskInvite).where(DeskInvite.id == invite_id, DeskInvite.status == 'pending').values(status=status))
        if changed.rowcount != 1:
            raise HTTPException(409, '邀请已被处理')
        if action == 'accept':
            # user_id is a primary key: concurrent acceptances cannot create two desks.
            db.add_all([DeskMember(user_id=row.sender_id, desk_id=row.id), DeskMember(user_id=row.target_id, desk_id=row.id)])
            await db.flush()
            await db.execute(update(DeskInvite).where(DeskInvite.id != invite_id, DeskInvite.status == 'pending', or_(DeskInvite.sender_id.in_([row.sender_id, row.target_id]), DeskInvite.target_id.in_([row.sender_id, row.target_id]))).values(status='superseded'))
        if action == 'accept':
            from app.routers.community_social import notice
            await notice(db, row.sender_id, user.id, f'desk-accepted:{row.id}', '对方接受了同桌邀请，可以到一起练设置共享权限')
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(409, '你或对方已拥有正式同桌')
    return {'status': status}


@router.put('/sharing')
async def sharing(payload: ConsentIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    me, _ = await pair(db, user.id)
    me.share_activity = int(payload.share_activity)
    me.share_videos = int(payload.share_videos)
    me.share_library = int(payload.share_library)
    await db.commit()
    return {'status': 'saved'}


@router.delete('')
async def leave(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    me = await db.get(DeskMember, user.id)
    if me:
        other = (await db.execute(select(DeskMember).where(DeskMember.desk_id == me.desk_id, DeskMember.user_id != user.id))).scalar_one_or_none()
        if other:
            from app.routers.community_social import notice
            await notice(db, other.user_id, user.id, f'desk-left:{me.desk_id}', '对方已解除同桌关系，学习共享已停止')
        await db.execute(delete(DeskMember).where(DeskMember.desk_id == me.desk_id))
        await db.commit()
    return {'status': 'left'}


@router.post('/block')
async def block(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    me, peer = await pair(db, user.id)
    db.add(DeskBlock(user_id=user.id, blocked_id=peer.user_id))
    await db.execute(delete(DeskMember).where(DeskMember.desk_id == me.desk_id))
    await db.commit()
    return {'status': 'blocked'}


@router.get('/activity')
async def activity(days: int = Query(7, ge=1, le=30), user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    _, peer = await pair(db, user.id)
    cutoff = (now() + timedelta(hours=8)).date() - timedelta(days=days - 1)
    result = {'days': days, 'summary': None, 'videos': None,
              'data_note': '来自已同步学习记录；不作为可信奖励或比赛结算依据。'}
    if peer.share_activity:
        stats = (await db.execute(select(UserStudyStatsDaily).where(
            UserStudyStatsDaily.user_id == peer.user_id, UserStudyStatsDaily.day >= str(cutoff),
            UserStudyStatsDaily.day <= str((now() + timedelta(hours=8)).date())))).scalars().all()
        result['summary'] = {'study_seconds': sum(min(max(0, r.study_seconds), 86400) for r in stats),
                             'study_days': sum(r.study_seconds > 0 for r in stats),
                             'daily': [{'day': r.day, 'seconds': min(max(0, r.study_seconds), 86400)} for r in sorted(stats, key=lambda r: r.day)]}
    if peer.share_videos:
        rows = (await db.execute(select(LessonProgress).where(
            LessonProgress.user_id == peer.user_id, LessonProgress.updated_at >= now() - timedelta(days=days)
        ).order_by(LessonProgress.updated_at.desc()).limit(50))).scalars().all()
        videos = []
        for row in rows:
            # Unknown private course IDs and all source URLs are never returned.
            title = '私有课程（不公开标题与地址）'
            course = get_course(row.course_id)
            if course:
                title = course.titleZh or course.title
                lesson = next((l for l in course.lessons if l.id == row.lesson_id), None)
                if lesson:
                    title += ' · ' + lesson.title
            elif re.fullmatch(r'link-\d+', row.course_id):
                asset = await db.get(UserLinkCourse, int(row.course_id[5:]))
                if asset and asset.user_id == peer.user_id and asset.source in {'bilibili', 'youtube'}:
                    title = asset.title
            videos.append({'title': title, 'completed': bool(row.completed),
                           'day': (aware(row.updated_at) + timedelta(hours=8)).date().isoformat()})
        result['videos'] = videos
    return result


def normalize_word(word):
    return re.sub(r'\s+', ' ', word.strip().casefold())


@router.put('/library')
async def sync_library(payload: LibraryIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    words = {normalize_word(w) for w in payload.words}
    if any(not w or len(w) > 120 for w in words):
        raise HTTPException(400, '词条格式错误')
    await db.execute(delete(DeskLibraryWord).where(DeskLibraryWord.user_id == user.id))
    db.add_all([DeskLibraryWord(user_id=user.id, word=w) for w in words])
    snapshot = await db.get(DeskLibrarySnapshot, user.id)
    if snapshot is None:
        db.add(DeskLibrarySnapshot(user_id=user.id, updated_at=now()))
    else:
        snapshot.updated_at = now()
    await db.commit()
    return {'count': len(words)}


@router.get('/library')
async def library(category: Literal['common', 'mine', 'peer'] = 'common', q: str = Query('', max_length=120), offset: int = Query(0, ge=0), limit: int = Query(50, ge=1, le=100), user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    _, peer = await pair(db, user.id)
    if not peer.share_library:
        raise HTTPException(403, '对方尚未共享收藏词库')
    async def words(uid):
        return set((await db.execute(select(DeskLibraryWord.word).where(DeskLibraryWord.user_id == uid))).scalars())
    mine, theirs = await words(user.id), await words(peer.user_id)
    selected = {'common': mine & theirs, 'mine': mine - theirs, 'peer': theirs - mine}[category]
    matching = sorted(w for w in selected if normalize_word(q) in w)
    my_sync = await db.get(DeskLibrarySnapshot, user.id)
    peer_sync = await db.get(DeskLibrarySnapshot, peer.user_id)
    return {'snapshots': {'mine': my_sync.updated_at if my_sync else None, 'peer': peer_sync.updated_at if peer_sync else None},
            'counts': {'mine': len(mine), 'peer': len(theirs), 'common': len(mine & theirs),
                       'mine_only': len(mine - theirs), 'peer_only': len(theirs - mine)},
            'words': matching[offset:offset + limit], 'total': len(matching),
            'vocabulary_estimate': None, 'note': '收藏量不代表词汇量；仅比较双方最近同步的收藏单词，不包含私有原句。'}


@router.post('/encourage')
async def encourage(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    from app.services.study_rewards import day_key
    from app.routers.community_social import notice
    me, peer = await pair(db, user.id)
    sent = await notice(db, peer.user_id, user.id, f'encourage:{day_key()}:{user.id}', f'{name(user)}给你一个鼓励：今天也一起学一点吧！')
    await db.commit()
    return {'sent': sent}
