"""One-to-one study desks with revocable, default-private sharing."""
from datetime import datetime, timedelta, timezone
import json
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
                        DeskQuestWeek, ChallengeFirstClear, ChallengeRetest, LessonProgress, User,
                        UserLinkCourse, UserStudyStatsDaily, UserAvatarLoadout, CommunityProfile)
from app.course_data import get_course
from app.services.virtual_deskmate import (
    VIRTUAL_EMAIL_PREFIX,
    bind_desk,
    create_virtual_user,
    ensure_virtual_daily_stats,
    is_virtual_email,
    is_virtual_user,
    peer_progress_nudge,
)


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


class WeeklyQuestIn(BaseModel):
    chapter: str = Field(default="desk", max_length=32)
    level: int = Field(ge=0, le=31)


class RetestIn(BaseModel):
    chapter: str = Field(default="desk", max_length=32)
    level: int = Field(ge=0, le=31)
    passed: bool = True


WEEKLY_TARGET = 3
# desk = study desk weekly co-op; cafe kept for legacy rows.
_ALLOWED_CHAPTERS = frozenset({"desk", "cafe", "general"})


def week_id(moment: datetime | None = None) -> str:
    """ISO week id, e.g. 2026-W47."""
    moment = moment or now()
    iso = moment.isocalendar()
    return f"{iso.year}-W{iso.week:02d}"


def _levels_of(row: DeskQuestWeek | None) -> list[int]:
    if row is None:
        return []
    try:
        data = json.loads(row.levels_json or "[]")
    except json.JSONDecodeError:
        return []
    if not isinstance(data, list):
        return []
    out: list[int] = []
    for item in data:
        if isinstance(item, int):
            out.append(item)
        elif isinstance(item, str) and item.isdigit():
            out.append(int(item))
    return sorted(set(out))


async def _quest_row(db: AsyncSession, user_id: int, week: str, chapter: str) -> DeskQuestWeek | None:
    return await db.get(DeskQuestWeek, (user_id, week, chapter))


async def _peer_payload(db: AsyncSession, member: DeskMember, me_id: int) -> dict:
    other = await db.get(User, member.user_id)
    if is_virtual_user(other):
        await ensure_virtual_daily_stats(db, other, paired_user_id=me_id)
    avatar_rows = (await db.execute(select(UserAvatarLoadout).where(UserAvatarLoadout.user_id == other.id))).scalars().all()
    return {
        'id': other.id,
        'name': name(other),
        'virtual': is_virtual_user(other),
        'avatar': {r.slot: r.sku for r in avatar_rows},
        'sharing': {
            'activity': bool(member.share_activity),
            'videos': bool(member.share_videos),
            'library': bool(member.share_library),
        },
    }


@router.get('')
async def overview(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    me = await db.get(DeskMember, user.id)
    peer = None
    nudge = None
    if me:
        _, member = await pair(db, user.id)
        other = await db.get(User, member.user_id)
        peer = await _peer_payload(db, member, user.id)
        nudge = await peer_progress_nudge(db, user.id, other, member)
        await db.commit()
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
        if other is None or is_virtual_user(other):
            continue
        invites.append({'id': row.id, 'incoming': row.target_id == user.id,
                        'name': name(other), 'expires_at': row.expires_at})
    return {'my_id': user.id, 'peer': peer, 'invites': invites,
            'nudge': nudge,
            'can_find_deskmate': peer is None,
            'sharing': {'activity': bool(me and me.share_activity),
                        'videos': bool(me and me.share_videos), 'library': bool(me and me.share_library)}}


@router.post('/match')
async def match_deskmate(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """寻找同桌：优先配对正在找搭子的真人；无人可配则分配虚拟同桌。"""
    if await db.get(DeskMember, user.id):
        body = await overview(user=user, db=db)
        body['matched'] = True
        body['source'] = 'existing'
        return body

    # Prefer real seekers who opted into looking_for_partner and have no desk yet.
    candidates = (await db.execute(
        select(User).join(CommunityProfile, CommunityProfile.user_id == User.id).where(
            CommunityProfile.looking_for_partner == 1,
            User.id != user.id,
            ~User.email.like(f'{VIRTUAL_EMAIL_PREFIX}%'),
        ).order_by(CommunityProfile.updated_at.asc()).limit(40)
    )).scalars().all()
    chosen: User | None = None
    for candidate in candidates:
        if is_virtual_email(candidate.email):
            continue
        if await db.get(DeskMember, candidate.id):
            continue
        if await blocked(db, user.id, candidate.id):
            continue
        chosen = candidate
        break

    source = 'real'
    peer_user: User
    if chosen is not None:
        peer_user = chosen
        await bind_desk(db, user.id, peer_user.id)
        for uid in (user.id, peer_user.id):
            profile = await db.get(CommunityProfile, uid)
            if profile:
                profile.looking_for_partner = 0
    else:
        source = 'virtual'
        peer_user = await create_virtual_user(db, user.id)
        await bind_desk(db, user.id, peer_user.id)
        await ensure_virtual_daily_stats(db, peer_user, paired_user_id=user.id)

    # Supersede any pending invites involving the seeker.
    await db.execute(update(DeskInvite).where(
        DeskInvite.status == 'pending',
        or_(DeskInvite.sender_id == user.id, DeskInvite.target_id == user.id),
    ).values(status='superseded'))
    await db.commit()
    body = await overview(user=user, db=db)
    body['matched'] = True
    body['source'] = source
    return body


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
            other_user = await db.get(User, other.user_id)
            if not is_virtual_user(other_user):
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
    peer_user = await db.get(User, peer.user_id)
    if is_virtual_user(peer_user):
        await ensure_virtual_daily_stats(db, peer_user, paired_user_id=user.id, days=max(days, 7))
        await db.commit()
        # Virtual peers always expose activity.
        peer.share_activity = 1
    cutoff = (now() + timedelta(hours=8)).date() - timedelta(days=days - 1)
    result = {'days': days, 'summary': None, 'videos': None,
              'data_note': '来自已同步学习记录；不作为可信奖励或比赛结算依据。',
              'virtual': is_virtual_user(peer_user)}
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
    peer_user = await db.get(User, peer.user_id)
    if is_virtual_user(peer_user):
        await db.commit()
        return {'sent': True, 'virtual': True}
    sent = await notice(db, peer.user_id, user.id, f'encourage:{day_key()}:{user.id}', f'{name(user)}给你一个鼓励：今天也一起学一点吧！')
    await db.commit()
    return {'sent': sent}


@router.get('/weekly-quest')
async def weekly_quest_state(
    chapter: str = Query('cafe'),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    chapter = (chapter or 'cafe').strip().lower()
    if chapter not in _ALLOWED_CHAPTERS:
        raise HTTPException(400, 'unsupported chapter')
    week = week_id()
    me_row = await _quest_row(db, user.id, week, chapter)
    me_levels = _levels_of(me_row)
    peer_levels: list[int] | None = None
    peer_count = None
    try:
        _, peer = await pair(db, user.id)
        peer_row = await _quest_row(db, peer.user_id, week, chapter)
        peer_levels = _levels_of(peer_row)
        peer_count = len(peer_levels)
    except HTTPException:
        peer_levels = None
        peer_count = None
    me_count = len(me_levels)
    together = (
        peer_count is not None
        and me_count >= WEEKLY_TARGET
        and peer_count >= WEEKLY_TARGET
    )
    return {
        'week_id': week,
        'chapter': chapter,
        'target': WEEKLY_TARGET,
        'me_count': me_count,
        'me_levels': me_levels,
        'peer_count': peer_count,
        'peer_levels': peer_levels,
        'together': together,
    }


@router.post('/weekly-quest')
async def weekly_quest_report(
    payload: WeeklyQuestIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    chapter = (payload.chapter or 'cafe').strip().lower()
    if chapter not in _ALLOWED_CHAPTERS:
        raise HTTPException(400, 'unsupported chapter')
    week = week_id()
    row = await _quest_row(db, user.id, week, chapter)
    levels = _levels_of(row)
    if payload.level not in levels:
        levels.append(payload.level)
        levels = sorted(set(levels))
    blob = json.dumps(levels)
    if row is None:
        db.add(
            DeskQuestWeek(
                user_id=user.id,
                week_id=week,
                chapter=chapter,
                levels_json=blob,
            )
        )
    else:
        row.levels_json = blob
    # Record first clear for delayed retest baseline.
    first = await db.get(ChallengeFirstClear, (user.id, chapter, payload.level))
    if first is None:
        db.add(
            ChallengeFirstClear(
                user_id=user.id,
                chapter=chapter,
                level=payload.level,
                cleared_at=now(),
            )
        )
    await db.commit()
    return await weekly_quest_state(chapter=chapter, user=user, db=db)


@router.get('/retest-stats')
async def retest_stats(
    chapter: str = Query('cafe'),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    chapter = (chapter or 'cafe').strip().lower()
    if chapter not in _ALLOWED_CHAPTERS:
        raise HTTPException(400, 'unsupported chapter')
    rows = (
        await db.execute(
            select(ChallengeRetest).where(
                ChallengeRetest.user_id == user.id,
                ChallengeRetest.chapter == chapter,
            )
        )
    ).scalars().all()
    attempts = len(rows)
    passes = sum(1 for r in rows if r.passed)
    return {
        'chapter': chapter,
        'attempts': attempts,
        'passes': passes,
        'pass_rate': (passes / attempts) if attempts else None,
    }


@router.post('/retest')
async def report_retest(
    payload: RetestIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    chapter = (payload.chapter or 'cafe').strip().lower()
    if chapter not in _ALLOWED_CHAPTERS:
        raise HTTPException(400, 'unsupported chapter')
    first = await db.get(ChallengeFirstClear, (user.id, chapter, payload.level))
    if first is None:
        raise HTTPException(400, '请先完成该关首次通关，再记录延迟复测')
    if aware(first.cleared_at) > now() - timedelta(days=1):
        raise HTTPException(400, '距首次通关未满24小时，暂不计入延迟复测')
    db.add(
        ChallengeRetest(
            user_id=user.id,
            chapter=chapter,
            level=payload.level,
            passed=int(payload.passed),
        )
    )
    await db.commit()
    return await retest_stats(chapter=chapter, user=user, db=db)
