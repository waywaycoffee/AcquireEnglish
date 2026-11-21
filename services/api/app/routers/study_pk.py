"""Recent learned-word quizzes: consent, server-held answers, atomic submissions."""
import json
import random
import re
from contextlib import closing
from datetime import datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import DeskPkPermission, DeskWordPk, DeskPkRun, DeskPkAnswer, ReviewBackup, User
from app.routers.public_lexicon import _connect
from app.routers.study_desk import pair, no_store, now, aware

router = APIRouter(prefix='/study-pk', tags=['study-pk'], dependencies=[Depends(no_store)])
SECONDS_PER_QUESTION = 20


class ConsentIn(BaseModel):
    enabled: bool


class CreateIn(BaseModel):
    days: Literal[7, 30] = 7
    count: Literal[5, 10] = 10
    # intersection = shared recent words; cafe = chapter public bank (agreed vocab)
    source: Literal["intersection", "cafe"] = "intersection"


class AnswerIn(BaseModel):
    index: int = Field(ge=0, le=9)
    choice: int | None = Field(default=None, ge=0, le=3)


async def permissions(db, user_id):
    me, peer = await pair(db, user_id)
    a = await db.get(DeskPkPermission, me.user_id)
    b = await db.get(DeskPkPermission, peer.user_id)
    return me, peer, bool(a and a.desk_id == me.desk_id and a.enabled), bool(b and b.desk_id == me.desk_id and b.enabled)


async def require_permission(db, user_id):
    me, peer, a, b = await permissions(db, user_id)
    if not (a and b):
        raise HTTPException(403, '双方需分别同意将近期已学单词用于PK')
    return me, peer


async def recent_words(db, user_id, days):
    backup = await db.get(ReviewBackup, user_id)
    if backup is None:
        return set()
    try:
        records = json.loads(backup.payload).get('records', [])
    except (ValueError, AttributeError):
        return set()
    words = set()
    for row in records:
        try:
            key = row['key']
            prefix, word = key.split(':', 1)
            if prefix == 'syllabus':
                word = word.rsplit(':', 1)[-1]
            last = datetime.fromisoformat(row['card']['lastReview'].replace('Z', '+00:00'))
            if prefix in {'word', 'recommended', 'syllabus'} and re.fullmatch('[a-z]+', word) and int(row['reviews']) > 0 and now() - timedelta(days=days) <= aware(last) <= now():
                words.add(word)
        except (ValueError, TypeError, KeyError, AttributeError):
            continue
    return words


def question_pool(words):
    rng = random.SystemRandom()
    with closing(_connect()) as lexicon:
        candidates = []
        for word in sorted(words)[:20000]:
            row = lexicon.execute('SELECT word, definition_cn FROM entries WHERE word = ?', (word,)).fetchone()
            if row and 1 <= len((row['definition_cn'] or '').strip()) <= 180:
                candidates.append({'word': word, 'definition': row['definition_cn'].strip()})
        distractors = [r['definition_cn'].strip() for r in lexicon.execute(
            "SELECT DISTINCT definition_cn FROM entries WHERE trim(definition_cn) <> '' AND length(definition_cn) <= 180 ORDER BY random() LIMIT 120")]
    rng.shuffle(candidates)
    questions = []
    for row in candidates:
        wrong = sorted(set(distractors) - {row['definition']})
        if len(wrong) < 3:
            continue
        choices = rng.sample(wrong, 3) + [row['definition']]
        rng.shuffle(choices)
        questions.append({'word': row['word'], 'choices': choices, 'answer': choices.index(row['definition'])})
    return questions


async def match_for(db, user_id, match_id):
    me, peer = await require_permission(db, user_id)
    match = await db.get(DeskWordPk, match_id)
    if match is None or match.desk_id != me.desk_id or user_id not in {match.sender_id, match.target_id}:
        raise HTTPException(404, '对局不存在')
    if match.status in {'pending', 'active'} and aware(match.expires_at) <= now():
        match.status = 'expired'
        match.active_desk_id = None
        await db.commit()
    return match


@router.put('/consent')
async def consent(payload: ConsentIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    me, _ = await pair(db, user.id)
    permission = await db.get(DeskPkPermission, user.id)
    if permission is None:
        db.add(DeskPkPermission(user_id=user.id, desk_id=me.desk_id, enabled=int(payload.enabled)))
    else:
        permission.desk_id, permission.enabled = me.desk_id, int(payload.enabled)
    if not payload.enabled:
        await db.execute(update(DeskWordPk).where(DeskWordPk.active_desk_id == me.desk_id).values(status='cancelled', active_desk_id=None))
    await db.commit()
    return {'enabled': payload.enabled}


@router.get('')
async def lobby(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    me, peer, a, b = await permissions(db, user.id)
    rows = (await db.execute(select(DeskWordPk).where(DeskWordPk.desk_id == me.desk_id).order_by(DeskWordPk.id.desc()).limit(20))).scalars().all()
    matches = []
    for row in rows:
        if row.status in {'pending', 'active'} and aware(row.expires_at) <= now():
            row.status, row.active_desk_id = 'expired', None
        matches.append({
            'id': row.id,
            'status': row.status,
            'incoming': row.target_id == user.id,
            'count': len(json.loads(row.questions_json)),
            'days': row.days,
            'source': 'cafe' if row.days == 0 else 'intersection',
        })
    await db.commit()
    return {'my_consent': a, 'peer_consent': b, 'matches': matches if a and b else []}


@router.post('', status_code=201)
async def create(payload: CreateIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    me, peer = await require_permission(db, user.id)
    current = (await db.execute(select(DeskWordPk).where(DeskWordPk.active_desk_id == me.desk_id))).scalar_one_or_none()
    if current:
        if aware(current.expires_at) > now():
            raise HTTPException(409, '已有待处理或进行中的对局，请先继续或取消')
        current.status, current.active_desk_id = 'expired', None
        await db.flush()
    if payload.source == 'cafe':
        from app.services.cafe_challenge import cafe_pk_questions

        try:
            questions = cafe_pk_questions(payload.count, seed=me.desk_id * 1000 + payload.count)
        except ValueError as exc:
            raise HTTPException(400, '咖啡店章节词表不足，请改用共同词或减少题量') from exc
        # days column reused as marker: 0 = cafe chapter bank
        days_marker = 0
    else:
        recent = await recent_words(db, user.id, payload.days) & await recent_words(db, peer.user_id, payload.days)
        if len(recent) < payload.count:
            raise HTTPException(400, f'双方近{payload.days}天共同学过的词不足{payload.count}个，请同步复习记录、扩大至30天、选5题，或改用「咖啡店章节词表」')
        questions = question_pool(recent)
        if len(questions) < payload.count:
            raise HTTPException(400, '可用释义题不足，请先学习更多共同单词或改用章节词表')
        days_marker = payload.days
    row = DeskWordPk(desk_id=me.desk_id, active_desk_id=me.desk_id, sender_id=user.id, target_id=peer.user_id, status='pending', days=days_marker, questions_json=json.dumps(questions[:payload.count], ensure_ascii=False), expires_at=now() + timedelta(hours=24))
    db.add(row)
    try:
        await db.flush()
        from app.routers.community_social import notice
        await notice(db, peer.user_id, user.id, f'pk-invite:{row.id}', '同桌邀请你进行近期学习单词PK，请到一起练处理')
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(409, '对局已创建，请刷新后继续')
    return {'id': row.id}


@router.post('/{match_id}/{action}')
async def invitation(match_id: int, action: Literal['accept', 'decline', 'cancel'], user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    row = await match_for(db, user.id, match_id)
    if (action == 'cancel' and row.sender_id != user.id) or (action != 'cancel' and row.target_id != user.id):
        raise HTTPException(403, '无法处理此邀请')
    if row.status != 'pending':
        raise HTTPException(409, '邀请已处理或过期')
    status = {'accept': 'active', 'decline': 'declined', 'cancel': 'cancelled'}[action]
    changed = await db.execute(update(DeskWordPk).where(DeskWordPk.id == match_id, DeskWordPk.status == 'pending').values(status=status, active_desk_id=row.desk_id if status == 'active' else None, expires_at=now() + timedelta(hours=24)))
    if changed.rowcount != 1:
        raise HTTPException(409, '邀请已被处理')
    if status == 'active':
        from app.routers.community_social import notice
        await notice(db, row.sender_id, user.id, f'pk-accepted:{row.id}', '同桌已接受单词PK，请到一起练开始答题')
        db.add_all([DeskPkRun(match_id=match_id, user_id=row.sender_id), DeskPkRun(match_id=match_id, user_id=row.target_id)])
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(409, '邀请已被处理')
    return {'status': status}


async def completed_notices(db, row):
    from app.routers.community_social import notice
    for recipient, actor in [(row.sender_id, row.target_id), (row.target_id, row.sender_id)]:
        await notice(db, recipient, actor, f'pk-result:{row.id}', '单词PK双方已完成，请到一起练查看成绩与逐题复盘')


@router.get('/{match_id}')
async def view(match_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    row = await match_for(db, user.id, match_id)
    questions = json.loads(row.questions_json)
    if row.status == 'active':
        finished = await db.scalar(select(func.count()).select_from(DeskPkRun).where(DeskPkRun.match_id == match_id, DeskPkRun.next_index == len(questions)))
        if finished == 2:
            row.status, row.active_desk_id = 'completed', None
            await completed_notices(db, row)
            await db.commit()
    result = {'id': row.id, 'status': row.status, 'count': len(questions), 'question': None, 'result': None}
    if row.status == 'completed':
        answers = (await db.execute(select(DeskPkAnswer).where(DeskPkAnswer.match_id == match_id))).scalars().all()
        own = {a.question_index: a for a in answers if a.user_id == user.id}
        my_score = sum(a.correct for a in own.values())
        peer_score = sum(a.correct for a in answers if a.user_id != user.id)
        result['result'] = {'my_score': my_score, 'peer_score': peer_score, 'outcome': '平局' if my_score == peer_score else '你获胜' if my_score > peer_score else '对方获胜',
            'review': [{'word': q['word'], 'definition': q['choices'][q['answer']], 'correct': bool(own[i].correct)} for i, q in enumerate(questions)]}
    elif row.status == 'active':
        run = await db.get(DeskPkRun, (match_id, user.id))
        result['answered'] = run.next_index
        if run.next_index < len(questions):
            if run.question_started_at is None:
                await db.execute(update(DeskPkRun).where(DeskPkRun.match_id == match_id, DeskPkRun.user_id == user.id, DeskPkRun.next_index == run.next_index, DeskPkRun.question_started_at.is_(None)).values(question_started_at=now()))
                await db.commit()
                await db.refresh(run)
            q = questions[run.next_index]
            remaining = max(0, SECONDS_PER_QUESTION - int((now() - aware(run.question_started_at)).total_seconds()))
            result['question'] = {'index': run.next_index, 'word': q['word'], 'choices': q['choices'], 'seconds_remaining': remaining}
    return result


@router.put('/{match_id}/answer')
async def answer(match_id: int, payload: AnswerIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    row = await match_for(db, user.id, match_id)
    run = await db.get(DeskPkRun, (match_id, user.id))
    questions = json.loads(row.questions_json)
    if row.status != 'active' or run is None or run.next_index != payload.index or run.question_started_at is None or payload.index >= len(questions):
        raise HTTPException(409, '题目状态已更新，请刷新对局')
    selected = payload.choice if (now() - aware(run.question_started_at)).total_seconds() < SECONDS_PER_QUESTION else None
    changed = await db.execute(update(DeskPkRun).where(DeskPkRun.match_id == match_id, DeskPkRun.user_id == user.id, DeskPkRun.next_index == payload.index).values(next_index=payload.index + 1, question_started_at=None))
    if changed.rowcount != 1:
        raise HTTPException(409, '此题已经提交')
    db.add(DeskPkAnswer(match_id=match_id, user_id=user.id, question_index=payload.index, choice=selected, correct=int(selected == questions[payload.index]['answer'])))
    try:
        await db.flush()
        finished = await db.scalar(select(func.count()).select_from(DeskPkRun).where(DeskPkRun.match_id == match_id, DeskPkRun.next_index == len(questions)))
        if finished == 2:
            await db.execute(update(DeskWordPk).where(DeskWordPk.id == match_id).values(status='completed', active_desk_id=None))
            await completed_notices(db, row)
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(409, '此题已经提交')
    return {'status': 'saved'}
