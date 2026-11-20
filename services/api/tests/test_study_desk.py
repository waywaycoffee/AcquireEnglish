"""Two-account privacy and lifecycle checks for real study desks."""
import os
os.environ['DATABASE_URL'] = 'sqlite+aiosqlite:///./test_study_desk.db'
os.environ['AUTH_SMS_MOCK'] = 'true'
os.environ['AUTH_WECHAT_MOCK'] = 'true'

from datetime import datetime, timedelta, timezone
import asyncio
import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.database import Base, SessionLocal, engine
from app.main import app
from app.models import DeskInvite, DeskMember, LessonProgress, UserStudyStatsDaily


@pytest_asyncio.fixture(autouse=True)
async def clean():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield


async def account(client, phone):
    sent = await client.post('/api/auth/sms/send', json={'phone': phone})
    login = await client.post('/api/auth/sms/login', json={'phone': phone, 'code': sent.json()['debug_code']})
    assert login.status_code == 200, login.text
    headers = {'Authorization': 'Bearer ' + login.json()['access_token']}
    me = await client.get('/api/study-desk', headers=headers)
    assert me.status_code == 200, me.text
    return headers, me.json()['my_id']


async def setup_pair(client):
    a, aid = await account(client, '13900001001')
    b, bid = await account(client, '13900001002')
    c, cid = await account(client, '13900001003')
    invite = await client.post('/api/study-desk/invites', headers=a, json={'target_id': bid})
    assert invite.status_code == 201, invite.text
    iid = invite.json()['id']
    accepted = await client.post(f'/api/study-desk/invites/{iid}/accept', headers=b)
    assert accepted.status_code == 200, accepted.text
    return a, aid, b, bid, c, cid


@pytest.mark.asyncio
async def test_invite_is_private_target_only_and_single_desk():
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        assert (await client.get('/api/study-desk')).status_code == 401
        a, aid = await account(client, '13900001001')
        b, bid = await account(client, '13900001002')
        c, _ = await account(client, '13900001003')
        assert (await client.post('/api/study-desk/invites', headers=a, json={'target_id': aid})).status_code == 400
        invite = await client.post('/api/study-desk/invites', headers=a, json={'target_id': bid})
        iid = invite.json()['id']
        duplicate = await client.post('/api/study-desk/invites', headers=a, json={'target_id': bid})
        assert duplicate.json()['id'] == iid
        assert (await client.post(f'/api/study-desk/invites/{iid}/accept', headers=c)).status_code == 404
        assert (await client.post(f'/api/study-desk/invites/{iid}/cancel', headers=b)).status_code == 404
        assert (await client.post(f'/api/study-desk/invites/{iid}/accept', headers=b)).status_code == 200
        assert (await client.post(f'/api/study-desk/invites/{iid}/accept', headers=b)).status_code == 409
        assert (await client.post('/api/study-desk/invites', headers=c, json={'target_id': bid})).status_code == 409
        me = await client.get('/api/study-desk', headers=a)
        assert me.headers['cache-control'] == 'no-store'
        assert not any(me.json()['sharing'].values())
        assert 'email' not in me.json()['peer']


@pytest.mark.asyncio
async def test_activity_consent_private_source_and_revoke():
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        a, aid, b, bid, c, _ = await setup_pair(client)
        async with SessionLocal() as db:
            day = (datetime.now(timezone.utc) + timedelta(hours=8)).date().isoformat()
            db.add(UserStudyStatsDaily(user_id=bid, day=day, study_seconds=1200))
            db.add(LessonProgress(user_id=bid, course_id='secret-private-video-url', lesson_id='private-id', position_sec=900))
            await db.commit()
        result = (await client.get('/api/study-desk/activity', headers=a)).json()
        assert result['summary'] is None and result['videos'] is None
        assert (await client.get('/api/study-desk/activity', headers=c)).status_code == 409
        await client.put('/api/study-desk/sharing', headers=b, json={'share_activity': True, 'share_videos': True})
        result = (await client.get('/api/study-desk/activity', headers=a)).json()
        assert result['summary']['study_seconds'] == 1200
        assert result['videos'][0]['title'].startswith('私有课程')
        assert 'secret' not in str(result) and 'private-id' not in str(result)
        await client.put('/api/study-desk/sharing', headers=b, json={})
        result = (await client.get('/api/study-desk/activity', headers=a)).json()
        assert result['summary'] is None and result['videos'] is None
        await client.delete('/api/study-desk', headers=b)
        assert (await client.get('/api/study-desk/activity', headers=a)).status_code == 409
        assert (await client.get('/api/study-desk', headers=a)).json()['peer'] is None


@pytest.mark.asyncio
async def test_library_snapshot_intersections_search_and_replacement():
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        a, _, b, _, c, _ = await setup_pair(client)
        await client.put('/api/study-desk/library', headers=a, json={'words': ['Hello', 'hello', 'world']})
        await client.put('/api/study-desk/library', headers=b, json={'words': ['HELLO', 'coffee']})
        assert (await client.get('/api/study-desk/library', headers=a)).status_code == 403
        await client.put('/api/study-desk/sharing', headers=b, json={'share_library': True})
        result = (await client.get('/api/study-desk/library', headers=a)).json()
        assert result['counts'] == {'mine': 2, 'peer': 2, 'common': 1, 'mine_only': 1, 'peer_only': 1}
        assert result['words'] == ['hello']
        assert result['vocabulary_estimate'] is None
        only = (await client.get('/api/study-desk/library?category=peer&q=COF', headers=a)).json()
        assert only['words'] == ['coffee']
        assert (await client.get('/api/study-desk/library', headers=c)).status_code == 409
        await client.put('/api/study-desk/library', headers=b, json={'words': []})
        assert (await client.get('/api/study-desk/library', headers=a)).json()['counts']['peer'] == 0
        await client.put('/api/study-desk/sharing', headers=b, json={})
        assert (await client.get('/api/study-desk/library', headers=a)).status_code == 403


@pytest.mark.asyncio
async def test_expiry_decline_cancel_and_block():
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        a, aid = await account(client, '13900001001')
        b, bid = await account(client, '13900001002')
        iid = (await client.post('/api/study-desk/invites', headers=a, json={'target_id': bid})).json()['id']
        assert (await client.post(f'/api/study-desk/invites/{iid}/decline', headers=b)).status_code == 200
        iid = (await client.post('/api/study-desk/invites', headers=a, json={'target_id': bid})).json()['id']
        assert (await client.post(f'/api/study-desk/invites/{iid}/cancel', headers=a)).status_code == 200
        iid = (await client.post('/api/study-desk/invites', headers=a, json={'target_id': bid})).json()['id']
        async with SessionLocal() as db:
            row = await db.get(DeskInvite, iid)
            row.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
            await db.commit()
        assert (await client.post(f'/api/study-desk/invites/{iid}/accept', headers=b)).status_code == 409
        iid = (await client.post('/api/study-desk/invites', headers=a, json={'target_id': bid})).json()['id']
        assert (await client.post(f'/api/study-desk/invites/{iid}/accept', headers=b)).status_code == 200
        assert (await client.post('/api/study-desk/block', headers=a)).status_code == 200
        assert (await client.post('/api/study-desk/invites', headers=b, json={'target_id': aid})).status_code == 404
        assert (await client.get('/api/study-desk/library', headers=b)).status_code == 409


@pytest.mark.asyncio
async def test_parallel_accepts_cannot_give_user_two_desks():
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        a, aid = await account(client, '13900001001')
        b, bid = await account(client, '13900001002')
        c, cid = await account(client, '13900001003')
        i1 = (await client.post('/api/study-desk/invites', headers=a, json={'target_id': bid})).json()['id']
        i2 = (await client.post('/api/study-desk/invites', headers=c, json={'target_id': bid})).json()['id']
        results = await asyncio.gather(client.post(f'/api/study-desk/invites/{i1}/accept', headers=b), client.post(f'/api/study-desk/invites/{i2}/accept', headers=b))
        assert sorted(r.status_code for r in results) == [200, 409]
        async with SessionLocal() as db:
            members = list((await db.execute(select(DeskMember))).scalars())
            assert len(members) == 2
            assert len({m.desk_id for m in members}) == 1
