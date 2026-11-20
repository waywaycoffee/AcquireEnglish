"""Check-in and deterministic non-monetary study battles."""
import json
import math
import random
import secrets
from datetime import timedelta
from typing import Literal
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select, update, func, case
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.deps import get_current_user
from app.models import (StudyActivityClock, StudyRewardDay, StudyReviewEvidence, StudyCheckin,
                        DeskBattle, User, UserAvatarLoadout, UserReviewPoints, UserCosmeticInventory)
from app.routers.study_desk import pair, no_store
from app.services.study_rewards import now, aware, day_key, insert, ensure_day, grant_points

router = APIRouter(prefix='/study-play', tags=['study-play'], dependencies=[Depends(no_store)])


class TickIn(BaseModel):
    seconds: int = Field(ge=0, le=25)


@router.post('/activity')
async def tick(payload: TickIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    stamp = now()
    clock = await db.get(StudyActivityClock, user.id)
    if clock is None:
        await db.execute(insert(db, StudyActivityClock).values(user_id=user.id, first_seen=stamp, last_tick=stamp).on_conflict_do_nothing())
        await db.commit()
        return {'recorded_seconds': 0}
    delta = min(payload.seconds, 25, max(0, int((stamp - aware(clock.last_tick)).total_seconds())))
    # Don't credit the previous calendar day to today's reward total.
    day_start = (stamp + timedelta(hours=8)).replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(hours=8)
    delta = min(delta, max(0, int((stamp - day_start).total_seconds())))
    changed = await db.execute(update(StudyActivityClock).where(StudyActivityClock.user_id == user.id, StudyActivityClock.last_tick == clock.last_tick).values(last_tick=stamp, first_seen=stamp if stamp - aware(clock.last_tick) > timedelta(minutes=5) else clock.first_seen))
    if changed.rowcount != 1:
        await db.rollback()
        return {'recorded_seconds': 0}
    if delta:
        await ensure_day(db, user.id)
        await db.execute(update(StudyRewardDay).where(StudyRewardDay.user_id == user.id, StudyRewardDay.day == day_key()).values(seconds=case((StudyRewardDay.seconds + delta > 10800, 10800), else_=StudyRewardDay.seconds + delta)))
    await db.commit()
    return {'recorded_seconds': delta}


@router.get('/checkin')
async def checkin_state(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    row = await db.get(StudyRewardDay, (user.id, day_key()))
    reviews = await db.scalar(select(func.count()).select_from(StudyReviewEvidence).where(StudyReviewEvidence.user_id == user.id, StudyReviewEvidence.day == day_key()))
    claimed = await db.get(StudyCheckin, (user.id, day_key())) is not None
    target = row.review_target if row else 5
    seconds = row.seconds if row else 0
    history = (await db.execute(select(StudyCheckin.day).where(StudyCheckin.user_id == user.id).order_by(StudyCheckin.day.desc()).limit(30))).scalars().all()
    return {'day': day_key(), 'seconds': seconds, 'review_count': reviews, 'review_target': target, 'eligible': reviews >= target or seconds >= 600, 'claimed': claimed, 'history': history,
            'rule': '完成今日目标复习数量或600秒服务器限速记录的播放。离线和尚未同步的记录需联网核验，积分每日10分。'}


@router.post('/checkin')
async def claim(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    state = await checkin_state(user, db)
    if not state['eligible']:
        raise HTTPException(400, '尚未达到今日打卡条件，请完成学习并同步复习记录')
    await db.execute(insert(db, StudyCheckin).values(user_id=user.id, day=day_key()).on_conflict_do_nothing())
    awarded = await grant_points(db, user.id, 'checkin:' + day_key(), 10, 'study_checkin')
    # Pair bonus is granted once per user/day, even when switching desks.
    try:
        me, peer = await pair(db, user.id)
    except HTTPException:
        peer = None
    if peer and await db.get(StudyCheckin, (peer.user_id, day_key())):
        for uid in [user.id, peer.user_id]:
            await grant_points(db, uid, 'pair-checkin:' + day_key(), 2, 'pair_checkin')
    total = await db.scalar(select(func.count()).select_from(StudyCheckin).where(StudyCheckin.user_id == user.id))
    if total >= 7:
        await db.execute(insert(db, UserCosmeticInventory).values(user_id=user.id, sku='top.hoodie').on_conflict_do_nothing())
    await db.commit()
    return {'awarded': awarded, 'points': 10 if awarded else 0}


async def battle_pair(db, uid):
    me, peer = await pair(db, uid)
    if not (me.share_activity and peer.share_activity):
        raise HTTPException(403, '双方需先开启同桌学习统计共享')
    return me, peer


async def stats(db, uid):
    cutoff = day_key(now() - timedelta(days=6))
    days = list((await db.execute(select(StudyRewardDay).where(StudyRewardDay.user_id == uid, StudyRewardDay.day >= cutoff, StudyRewardDay.day <= day_key()))).scalars())
    count = await db.scalar(select(func.count(func.distinct(StudyReviewEvidence.card_key))).where(StudyReviewEvidence.user_id == uid, StudyReviewEvidence.day >= cutoff, StudyReviewEvidence.day <= day_key()))
    active = await db.scalar(select(func.count(func.distinct(StudyReviewEvidence.day))).where(StudyReviewEvidence.user_id == uid, StudyReviewEvidence.day >= cutoff, StudyReviewEvidence.day <= day_key()))
    m, n = min(210, sum(d.seconds for d in days) / 60), min(140, count)
    d = min(7, max(active, sum(r.seconds > 0 for r in days)))
    return {'minutes': round(m, 1), 'words': n, 'days': d, 'attack': 10 + 6 * math.sqrt(m / 210), 'armor': 2 + 4 * math.sqrt(n / 140), 'stability': d / 7}


async def avatars(db, ids):
    rows = list((await db.execute(select(UserAvatarLoadout).where(UserAvatarLoadout.user_id.in_(ids)))).scalars())
    return {str(uid): {r.slot: r.sku for r in rows if r.user_id == uid} for uid in ids}


def simulate(a, b, sa, sb, seed):
    rng = random.Random(seed)
    health = {str(a): 100, str(b): 100}
    values = {a: sa, b: sb}
    steps = []
    for round_no in range(1, 13):
        for attacker, target in ([(a, b), (b, a)] if round_no % 2 else [(b, a), (a, b)]):
            attack, defense = values[attacker], values[target]
            base = attack['attack'] + attack['stability']
            factor = rng.uniform(.9, 1.1)
            raw_damage = round(base * factor)
            blocked_damage = round(defense['armor'] * factor)
            damage = max(3, raw_damage - blocked_damage)
            actual = min(damage, health[str(target)])
            health[str(target)] -= actual
            steps.append({'round': round_no, 'attacker': attacker, 'target': target, 'action': '专注一击' if round_no % 2 else '记忆连招', 'damage': actual, 'armor': round(defense['armor'], 1), 'health': dict(health), 'text': f'学员{attacker}前移出手，原始攻击{raw_damage}；学员{target}格挡{blocked_damage}，实际扣血{actual}（不超过剩余血量）。'})
            if health[str(target)] == 0:
                break
        if min(health.values()) == 0:
            break
    winner = None if health[str(a)] == health[str(b)] else a if health[str(a)] > health[str(b)] else b
    return {'stats': {str(a): sa, str(b): sb}, 'steps': steps, 'health': health, 'winner': winner}


@router.get('/battles')
async def battles(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    me, peer = await pair(db, user.id)
    rows = (await db.execute(select(DeskBattle).where(DeskBattle.desk_id == me.desk_id).order_by(DeskBattle.id.desc()).limit(20))).scalars().all()
    for row in rows:
        if row.status == 'pending' and aware(row.expires_at) <= now():
            row.status, row.pending_desk_id = 'expired', None
    await db.commit()
    return {'my_id': user.id, 'peer_id': peer.user_id, 'can_battle': bool(me.share_activity and peer.share_activity), 'matches': [{'id': r.id, 'status': r.status, 'incoming': r.target_id == user.id} for r in rows]}


@router.post('/battles', status_code=201)
async def create_battle(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    me, peer = await battle_pair(db, user.id)
    current = (await db.execute(select(DeskBattle).where(DeskBattle.pending_desk_id == me.desk_id))).scalar_one_or_none()
    if current:
        if aware(current.expires_at) > now():
            raise HTTPException(409, '已有待处理挑战')
        current.status, current.pending_desk_id = 'expired', None
        await db.flush()
    count = await db.scalar(select(func.count()).select_from(DeskBattle).where(DeskBattle.sender_id == user.id, DeskBattle.created_at >= now() - timedelta(days=1)))
    if count >= 5:
        raise HTTPException(429, '每天最多发起5场切磋')
    row = DeskBattle(desk_id=me.desk_id, pending_desk_id=me.desk_id, sender_id=user.id, target_id=peer.user_id, status='pending', seed=secrets.token_hex(16), expires_at=now() + timedelta(hours=24))
    db.add(row)
    try:
        await db.flush()
        from app.routers.community_social import notice
        await notice(db, peer.user_id, user.id, f'battle-invite:{row.id}', '同桌邀请你进行学习力大比武，请到一起练处理')
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(409, '已有待处理挑战')
    return {'id': row.id}


@router.post('/battles/{mid}/{action}')
async def act_battle(mid: int, action: Literal['accept', 'decline', 'cancel'], user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    me, peer = await battle_pair(db, user.id)
    row = await db.get(DeskBattle, mid)
    if row is None or row.desk_id != me.desk_id:
        raise HTTPException(404, '挑战不存在')
    if (action == 'cancel' and row.sender_id != user.id) or (action != 'cancel' and row.target_id != user.id):
        raise HTTPException(403, '无法处理该挑战')
    if row.status != 'pending' or aware(row.expires_at) <= now():
        raise HTTPException(409, '挑战已处理或过期')
    result = None
    if action == 'accept':
        a, b = await stats(db, row.sender_id), await stats(db, row.target_id)
        if a['minutes'] + a['words'] == 0 or b['minutes'] + b['words'] == 0:
            raise HTTPException(400, '双方需先完成有效学习并同步记录，再进行切磋')
        result = simulate(row.sender_id, row.target_id, a, b, row.seed)
        result['avatars'] = await avatars(db, [row.sender_id, row.target_id])
    status = {'accept': 'completed', 'decline': 'declined', 'cancel': 'cancelled'}[action]
    changed = await db.execute(update(DeskBattle).where(DeskBattle.id == mid, DeskBattle.status == 'pending').values(status=status, pending_desk_id=None, result_json=json.dumps(result) if result else None))
    if changed.rowcount != 1:
        raise HTTPException(409, '挑战已处理')
    from app.routers.community_social import notice
    await notice(db, row.sender_id, user.id, f'battle-response:{row.id}', '同桌已处理大比武邀请，请到一起练查看战报')
    await db.commit()
    return {'status': status}


@router.get('/battles/{mid}')
async def battle(mid: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    me, peer = await battle_pair(db, user.id)
    row = await db.get(DeskBattle, mid)
    if row is None or row.desk_id != me.desk_id:
        raise HTTPException(404, '挑战不存在')
    return {'id': mid, 'my_id': user.id, 'peer_id': peer.user_id, 'status': row.status, 'result': json.loads(row.result_json) if row.result_json else None}


CHALLENGES = {'listen7': {'title': '7天精听坚持', 'reward': 'bg.campus'}, 'review7': {'title': '7天词句巩固', 'reward': 'accessory.headphones'}}


@router.get('/challenges')
async def challenges(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    from app.models import StudyChallengeMember
    result = []
    for cid, spec in CHALLENGES.items():
        member = await db.get(StudyChallengeMember, (user.id, cid))
        count = 0
        if member:
            count = await db.scalar(select(func.count()).select_from(StudyCheckin).where(StudyCheckin.user_id == user.id, StudyCheckin.day >= member.joined_day))
        result.append({'id': cid, **spec, 'joined': bool(member and member.active), 'progress': min(7, count), 'claimed': bool(member and member.reward_claimed), 'rule': '加入后累计7个不同打卡日，不要求连续。两条活动共用个人打卡记录，不额外要求公开发帖。'})
    return {'challenges': result}


@router.post('/challenges/{cid}/{action}')
async def challenge_action(cid: str, action: Literal['join', 'leave', 'claim'], user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    from app.models import StudyChallengeMember
    if cid not in CHALLENGES:
        raise HTTPException(404, '活动不存在')
    member = await db.get(StudyChallengeMember, (user.id, cid))
    if action == 'join':
        await db.execute(insert(db, StudyChallengeMember).values(user_id=user.id, challenge_id=cid, joined_day=day_key(), reward_claimed=0, active=1).on_conflict_do_update(index_elements=['user_id', 'challenge_id'], set_={'active': 1}))
    elif action == 'leave':
        if member:
            member.active = 0
    else:
        if member is None or not member.active:
            raise HTTPException(400, '请先加入活动')
        count = await db.scalar(select(func.count()).select_from(StudyCheckin).where(StudyCheckin.user_id == user.id, StudyCheckin.day >= member.joined_day))
        if count < 7:
            raise HTTPException(400, '尚未完成7个打卡日')
        await db.execute(insert(db, UserCosmeticInventory).values(user_id=user.id, sku=CHALLENGES[cid]['reward']).on_conflict_do_nothing())
        member.reward_claimed = 1
    await db.commit()
    return {'status': 'saved'}
