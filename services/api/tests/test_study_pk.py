import asyncio
import json
import sqlite3
from datetime import datetime, timedelta, timezone

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from test_study_desk import clean, setup_pair
from app.main import app
from app.database import SessionLocal
from app.models import DeskWordPk, DeskPkRun, ReviewBackup


@pytest_asyncio.fixture(autouse=True)
async def dictionary(tmp_path, monkeypatch):
    path = tmp_path / 'lexicon.db'
    with sqlite3.connect(path) as db:
        db.execute('CREATE TABLE entries(word TEXT PRIMARY KEY, definition_cn TEXT)')
        db.executemany('INSERT INTO entries VALUES(?, ?)', [(w, f'中文释义{i}') for i, w in enumerate(['apple', 'banana', 'coffee', 'desk', 'eager', 'friend', 'grape', 'hello', 'idea', 'juice', 'kind', 'lemon', 'moon', 'night', 'open'])])
    monkeypatch.setenv('PUBLIC_LEXICON_PATH', str(path))


async def prepare(client):
    a, aid, b, bid, c, cid = await setup_pair(client)
    words = ['apple', 'banana', 'coffee', 'desk', 'eager', 'friend', 'grape', 'hello', 'idea', 'juice']
    async with SessionLocal() as db:
        records = [{'key': 'word:' + word, 'reviews': 1, 'card': {'lastReview': datetime.now(timezone.utc).isoformat()}} for word in words]
        for uid in [aid, bid]:
            db.add(ReviewBackup(user_id=uid, revision=1, payload=json.dumps({'records': records})))
        await db.commit()
    for h in [a, b]:
        assert (await client.put('/api/study-pk/consent', headers=h, json={'enabled': True})).status_code == 200
    created = await client.post('/api/study-pk', headers=a, json={'days': 7, 'count': 5})
    assert created.status_code == 201, created.text
    mid = created.json()['id']
    assert (await client.post(f'/api/study-pk/{mid}/accept', headers=b)).status_code == 200
    return a, aid, b, bid, c, mid


@pytest.mark.asyncio
async def test_same_questions_no_early_answers_and_complete_result():
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        a, aid, b, bid, c, mid = await prepare(client)
        assert (await client.get(f'/api/study-pk/{mid}', headers=c)).status_code == 409
        async with SessionLocal() as db:
            questions = json.loads((await db.get(DeskWordPk, mid)).questions_json)
        for i in range(5):
            view = await client.get(f'/api/study-pk/{mid}', headers=a)
            assert view.status_code == 200
            q = view.json()['question']
            assert q['word'] == questions[i]['word'] and 'answer' not in q
            assert view.json()['result'] is None
            assert (await client.put(f'/api/study-pk/{mid}/answer', headers=a, json={'index': i, 'choice': questions[i]['answer']})).status_code == 200
            assert (await client.put(f'/api/study-pk/{mid}/answer', headers=a, json={'index': i, 'choice': 0})).status_code == 409
        waiting = (await client.get(f'/api/study-pk/{mid}', headers=a)).json()
        assert waiting['question'] is None and waiting['result'] is None
        for i in range(5):
            q = (await client.get(f'/api/study-pk/{mid}', headers=b)).json()['question']
            assert q['word'] == questions[i]['word']
            await client.put(f'/api/study-pk/{mid}/answer', headers=b, json={'index': i, 'choice': None})
        result = (await client.get(f'/api/study-pk/{mid}', headers=a)).json()['result']
        assert result['my_score'] == 5 and result['peer_score'] == 0
        assert len(result['review']) == 5
        assert (await client.get(f'/api/study-pk/{mid}', headers=b)).json()['result']['outcome'] == '对方获胜'


@pytest.mark.asyncio
async def test_timer_does_not_reset_timeout_is_not_correct_and_revoke_blocks_access():
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        a, aid, b, bid, c, mid = await prepare(client)
        await client.get(f'/api/study-pk/{mid}', headers=a)
        async with SessionLocal() as db:
            run = await db.get(DeskPkRun, (mid, aid))
            run.question_started_at = datetime.now(timezone.utc) - timedelta(seconds=25)
            correct = json.loads((await db.get(DeskWordPk, mid)).questions_json)[0]['answer']
            await db.commit()
        assert (await client.get(f'/api/study-pk/{mid}', headers=a)).json()['question']['seconds_remaining'] == 0
        assert (await client.put(f'/api/study-pk/{mid}/answer', headers=a, json={'index': 0, 'choice': correct})).status_code == 200
        await client.put('/api/study-pk/consent', headers=b, json={'enabled': False})
        assert (await client.get(f'/api/study-pk/{mid}', headers=a)).status_code == 403
        async with SessionLocal() as db:
            assert (await db.get(DeskWordPk, mid)).status == 'cancelled'


@pytest.mark.asyncio
async def test_no_unlearned_or_old_words_no_permission_no_match():
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        a, aid, b, bid, c, cid = await setup_pair(client)
        assert (await client.post('/api/study-pk', headers=a, json={})).status_code == 403
        for h in [a, b]:
            await client.put('/api/study-pk/consent', headers=h, json={'enabled': True})
        async with SessionLocal() as db:
            rows = [{'key': 'word:apple', 'reviews': 0, 'card': {'lastReview': datetime.now(timezone.utc).isoformat()}}, {'key': 'word:coffee', 'reviews': 5, 'card': {'lastReview': (datetime.now(timezone.utc) - timedelta(days=40)).isoformat()}}]
            for uid in [aid, bid]:
                db.add(ReviewBackup(user_id=uid, revision=1, payload=json.dumps({'records': rows})))
            await db.commit()
        assert (await client.post('/api/study-pk', headers=a, json={'count': 5})).status_code == 400
        async with SessionLocal() as db:
            assert not list((await db.execute(select(DeskWordPk))).scalars())


@pytest.mark.asyncio
async def test_parallel_answer_submits_once_and_invites_are_role_checked():
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        a, aid, b, bid, c, mid = await prepare(client)
        assert (await client.post(f'/api/study-pk/{mid}/accept', headers=a)).status_code == 403
        await client.get(f'/api/study-pk/{mid}', headers=a)
        replies = await asyncio.gather(*[client.put(f'/api/study-pk/{mid}/answer', headers=a, json={'index': 0, 'choice': 0}) for _ in range(2)])
        assert sorted(r.status_code for r in replies) == [200, 409]
        async with SessionLocal() as db:
            assert (await db.get(DeskPkRun, (mid, aid))).next_index == 1
