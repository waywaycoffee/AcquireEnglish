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
from app.services.virtual_deskmate import is_virtual_user

router = APIRouter(prefix='/study-pk', tags=['study-pk'], dependencies=[Depends(no_store)])
SECONDS_PER_QUESTION = 20


class ConsentIn(BaseModel):
    enabled: bool


class CreateIn(BaseModel):
    days: Literal[7, 30] = 7
    count: Literal[5, 10] = 10
    # intersection = shared recent words; cafe = chapter bank; syllabus = agreed book unit
    source: Literal["intersection", "cafe", "syllabus"] = "intersection"
    book_id: str | None = Field(default=None, max_length=64)
    unit_index: int = Field(default=0, ge=0, le=200)


def _pack_questions(
    questions: list[dict],
    *,
    source: str,
    meta: dict | None = None,
) -> str:
    if source == "intersection":
        return json.dumps(questions, ensure_ascii=False)
    return json.dumps(
        {
            "source": source,
            "meta": meta or {},
            "questions": questions,
        },
        ensure_ascii=False,
    )


def _unpack_questions(raw: str, *, days: int) -> tuple[list[dict], str, dict]:
    data = json.loads(raw)
    if isinstance(data, list):
        source = "cafe" if days == 0 else "intersection"
        return data, source, {}
    questions = data.get("questions") or []
    if not isinstance(questions, list):
        questions = []
    source = str(data.get("source") or ("cafe" if days == 0 else "intersection"))
    meta = data.get("meta") if isinstance(data.get("meta"), dict) else {}
    return questions, source, meta


def _match_source(row) -> tuple[list[dict], str, dict]:
    return _unpack_questions(row.questions_json, days=row.days)


class AnswerIn(BaseModel):
    index: int = Field(ge=0, le=9)
    choice: int | None = Field(default=None, ge=0, le=3)


async def permissions(db, user_id):
    me, peer = await pair(db, user_id)
    a = await db.get(DeskPkPermission, me.user_id)
    b = await db.get(DeskPkPermission, peer.user_id)
    peer_user = await db.get(User, peer.user_id)
    peer_ok = bool(b and b.desk_id == me.desk_id and b.enabled) or is_virtual_user(peer_user)
    return me, peer, bool(a and a.desk_id == me.desk_id and a.enabled), peer_ok


async def require_permission(db, user_id):
    me, peer, a, b = await permissions(db, user_id)
    peer_user = await db.get(User, peer.user_id)
    # Cafe / syllabus PK only needs the human's consent when peer is virtual.
    if is_virtual_user(peer_user):
        if not a:
            raise HTTPException(403, '请先同意将近期已学单词用于PK（虚拟同桌已默认参加）')
        return me, peer
    if not (a and b):
        raise HTTPException(403, '双方需分别同意将近期已学单词用于PK')
    return me, peer


async def _auto_finish_virtual(db, row, questions: list[dict]):
    """Fill remaining answers for a virtual peer so the match can settle."""
    virtual_id = None
    for uid in (row.sender_id, row.target_id):
        u = await db.get(User, uid)
        if is_virtual_user(u):
            virtual_id = uid
            break
    if virtual_id is None:
        return
    run = await db.get(DeskPkRun, (row.id, virtual_id))
    if run is None:
        return
    rng = random.Random(f'vpk:{row.id}:{virtual_id}')
    while run.next_index < len(questions):
        idx = run.next_index
        correct_choice = questions[idx]['answer']
        # ~70% accuracy — competitive but beatable.
        choice = correct_choice if rng.random() < 0.7 else (correct_choice + 1) % 4
        db.add(
            DeskPkAnswer(
                match_id=row.id,
                user_id=virtual_id,
                question_index=idx,
                choice=choice,
                correct=int(choice == correct_choice),
            )
        )
        run.next_index = idx + 1
        run.question_started_at = None
    await db.flush()


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
        questions, source, meta = _match_source(row)
        matches.append({
            'id': row.id,
            'status': row.status,
            'incoming': row.target_id == user.id,
            'count': len(questions),
            'days': row.days if source == 'intersection' else 0,
            'source': source,
            'book_id': meta.get('book_id'),
            'unit_index': meta.get('unit_index'),
            'unit_label': meta.get('unit_label'),
            'book_title': meta.get('book_title'),
        })
    await db.commit()
    return {'my_consent': a, 'peer_consent': b, 'matches': matches if a and b else []}


@router.get('/syllabus-units')
async def syllabus_units(user: User = Depends(get_current_user)):
    from app.services.syllabus_pk import list_syllabus_pk_units

    _ = user
    return {'units': list_syllabus_pk_units()}


@router.post('', status_code=201)
async def create(payload: CreateIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    me, peer = await require_permission(db, user.id)
    current = (await db.execute(select(DeskWordPk).where(DeskWordPk.active_desk_id == me.desk_id))).scalar_one_or_none()
    if current:
        if aware(current.expires_at) > now():
            raise HTTPException(409, '已有待处理或进行中的对局，请先继续或取消')
        current.status, current.active_desk_id = 'expired', None
        await db.flush()
    meta: dict | None = None
    if payload.source == 'cafe':
        from app.services.cafe_challenge import cafe_pk_questions

        try:
            questions = cafe_pk_questions(payload.count, seed=me.desk_id * 1000 + payload.count)
        except ValueError as exc:
            raise HTTPException(400, '咖啡店章节词表不足，请改用共同词、词书单元或减少题量') from exc
        # days column reused as marker: 0 = cafe chapter bank
        days_marker = 0
    elif payload.source == 'syllabus':
        from app.services.syllabus_pk import list_syllabus_pk_units, syllabus_pk_questions

        book_id = (payload.book_id or '').strip()
        if not book_id:
            raise HTTPException(400, '请选择词书单元')
        try:
            questions = syllabus_pk_questions(
                book_id,
                payload.unit_index,
                payload.count,
                seed=me.desk_id * 1000 + payload.unit_index * 17 + payload.count,
            )
        except (FileNotFoundError, ValueError) as exc:
            raise HTTPException(400, '词书单元不足或不可用，请换一本词书或减少题量') from exc
        unit_meta = next(
            (
                u
                for u in list_syllabus_pk_units()
                if u['book_id'] == book_id and u['unit_index'] == payload.unit_index
            ),
            None,
        )
        meta = {
            'book_id': book_id,
            'unit_index': payload.unit_index,
            'book_title': (unit_meta or {}).get('book_title') or book_id,
            'unit_label': (unit_meta or {}).get('unit_label')
            or f'第{payload.unit_index + 1}单元',
        }
        # days < 0 marks syllabus-backed matches for legacy readers
        days_marker = -1
    else:
        peer_user_early = await db.get(User, peer.user_id)
        recent = await recent_words(db, user.id, payload.days) & await recent_words(db, peer.user_id, payload.days)
        if len(recent) < payload.count and is_virtual_user(peer_user_early):
            # Virtual peers have no review backup — fall back to chapter bank.
            from app.services.cafe_challenge import cafe_pk_questions
            try:
                questions = cafe_pk_questions(payload.count, seed=me.desk_id * 1000 + payload.count)
            except ValueError as exc:
                raise HTTPException(400, '可用词表不足，请改用词书单元') from exc
            days_marker = 0
            meta = {'fallback': 'cafe', 'reason': 'virtual_peer'}
        elif len(recent) < payload.count:
            raise HTTPException(
                400,
                f'双方近{payload.days}天共同学过的词不足{payload.count}个，请同步复习记录、扩大至30天、选5题，或改用「咖啡店章节词表 / 词书单元」',
            )
        else:
            questions = question_pool(recent)
            if len(questions) < payload.count:
                raise HTTPException(400, '可用释义题不足，请先学习更多共同单词或改用约定词表')
            days_marker = payload.days
    packed = _pack_questions(
        questions[: payload.count],
        source=payload.source,
        meta=meta,
    )
    peer_user = await db.get(User, peer.user_id)
    auto_virtual = is_virtual_user(peer_user)
    row = DeskWordPk(
        desk_id=me.desk_id,
        active_desk_id=me.desk_id,
        sender_id=user.id,
        target_id=peer.user_id,
        status='active' if auto_virtual else 'pending',
        days=days_marker,
        questions_json=packed,
        expires_at=now() + timedelta(hours=24),
    )
    db.add(row)
    try:
        await db.flush()
        if auto_virtual:
            db.add_all(
                [
                    DeskPkRun(match_id=row.id, user_id=user.id),
                    DeskPkRun(match_id=row.id, user_id=peer.user_id),
                ]
            )
        else:
            from app.routers.community_social import notice
            await notice(db, peer.user_id, user.id, f'pk-invite:{row.id}', '同桌邀请你进行近期学习单词PK，请到一起练处理')
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(409, '对局已创建，请刷新后继续')
    return {'id': row.id, 'status': row.status, 'auto': auto_virtual}


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
    questions, source, meta = _match_source(row)
    if row.status == 'active':
        finished = await db.scalar(select(func.count()).select_from(DeskPkRun).where(DeskPkRun.match_id == match_id, DeskPkRun.next_index == len(questions)))
        if finished == 2:
            row.status, row.active_desk_id = 'completed', None
            await completed_notices(db, row)
            await db.commit()
    result = {
        'id': row.id,
        'status': row.status,
        'count': len(questions),
        'source': source,
        'book_title': meta.get('book_title'),
        'unit_label': meta.get('unit_label'),
        'question': None,
        'result': None,
    }
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
    questions, _, _ = _match_source(row)
    if row.status != 'active' or run is None or run.next_index != payload.index or run.question_started_at is None or payload.index >= len(questions):
        raise HTTPException(409, '题目状态已更新，请刷新对局')
    selected = payload.choice if (now() - aware(run.question_started_at)).total_seconds() < SECONDS_PER_QUESTION else None
    changed = await db.execute(update(DeskPkRun).where(DeskPkRun.match_id == match_id, DeskPkRun.user_id == user.id, DeskPkRun.next_index == payload.index).values(next_index=payload.index + 1, question_started_at=None))
    if changed.rowcount != 1:
        raise HTTPException(409, '此题已经提交')
    db.add(DeskPkAnswer(match_id=match_id, user_id=user.id, question_index=payload.index, choice=selected, correct=int(selected == questions[payload.index]['answer'])))
    try:
        await db.flush()
        # After the human finishes, settle the virtual peer immediately.
        human_done = (await db.get(DeskPkRun, (match_id, user.id))).next_index >= len(questions)
        if human_done:
            await _auto_finish_virtual(db, row, questions)
        finished = await db.scalar(select(func.count()).select_from(DeskPkRun).where(DeskPkRun.match_id == match_id, DeskPkRun.next_index == len(questions)))
        if finished == 2:
            await db.execute(update(DeskWordPk).where(DeskWordPk.id == match_id).values(status='completed', active_desk_id=None))
            await completed_notices(db, row)
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(409, '此题已经提交')
    return {'status': 'saved'}
