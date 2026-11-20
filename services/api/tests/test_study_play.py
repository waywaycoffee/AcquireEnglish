import asyncio
from datetime import datetime, timedelta, timezone
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from test_study_desk import clean, setup_pair, account
from app.database import SessionLocal
from app.main import app
from app.models import (StudyRewardDay, StudyReviewEvidence, UserReviewPoints, StudyActivityClock, DeskBattle)
from app.services.study_rewards import day_key
from app.routers.study_play import simulate


@pytest.mark.asyncio
async def test_checkin_and_pair_bonus_are_once_per_user_day():
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        a, aid, b, bid, c, _ = await setup_pair(client)
        assert (await client.post('/api/study-play/checkin', headers=a)).status_code == 400
        async with SessionLocal() as db:
            for uid in [aid, bid]: db.add(StudyRewardDay(user_id=uid, day=day_key(), seconds=600))
            await db.commit()
        requests = await asyncio.gather(*[client.post('/api/study-play/checkin', headers=a) for _ in range(2)])
        assert all(r.status_code == 200 for r in requests)
        assert sum(r.json()['points'] for r in requests) == 10
        assert (await client.post('/api/study-play/checkin', headers=b)).status_code == 200
        await client.post('/api/study-play/checkin', headers=b)
        async with SessionLocal() as db:
            assert (await db.get(UserReviewPoints, aid)).balance == 12
            assert (await db.get(UserReviewPoints, bid)).balance == 12
        assert (await client.get('/api/study-play/checkin', headers=a)).json()['claimed']


@pytest.mark.asyncio
async def test_activity_is_wall_clock_bounded_and_cannot_backfill():
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        a, aid = await account(client, '13900001001')
        assert (await client.post('/api/study-play/activity', headers=a, json={'seconds': 25})).json()['recorded_seconds'] == 0
        assert (await client.post('/api/study-play/activity', headers=a, json={'seconds': 25})).json()['recorded_seconds'] == 0
        async with SessionLocal() as db:
            clock = await db.get(StudyActivityClock, aid)
            clock.last_tick = datetime.now(timezone.utc) - timedelta(seconds=12)
            await db.commit()
        result = (await client.post('/api/study-play/activity', headers=a, json={'seconds': 25})).json()
        assert 12 <= result['recorded_seconds'] <= 13
        assert (await client.post('/api/study-play/activity', headers=a, json={'seconds': 9999})).status_code == 422


def test_simulation_is_deterministic_damage_matches_and_cosmetics_do_not_affect():
    stats = {'minutes': 100, 'words': 50, 'days': 4, 'attack': 14, 'armor': 4, 'stability': .5}
    a = simulate(1, 2, stats, stats, 'fixed-seed')
    assert a == simulate(1, 2, stats, stats, 'fixed-seed')
    health = {'1': 100, '2': 100}
    for step in a['steps']:
        health[str(step['target'])] -= step['damage']
        assert step['health'] == health
    assert min(health.values()) >= 0 and len(a['steps']) <= 24


@pytest.mark.asyncio
async def test_battle_invitation_consent_and_replay():
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        a, aid, b, bid, c, cid = await setup_pair(client)
        assert (await client.post('/api/study-play/battles', headers=a)).status_code == 403
        for h in [a, b]: await client.put('/api/study-desk/sharing', headers=h, json={'share_activity': True})
        async with SessionLocal() as db:
            for uid in [aid, bid]: db.add(StudyRewardDay(user_id=uid, day=day_key(), seconds=600))
            await db.commit()
        mid = (await client.post('/api/study-play/battles', headers=a)).json()['id']
        assert (await client.post(f'/api/study-play/battles/{mid}/accept', headers=a)).status_code == 403
        assert (await client.post(f'/api/study-play/battles/{mid}/accept', headers=b)).status_code == 200
        first = (await client.get(f'/api/study-play/battles/{mid}', headers=a)).json()['result']
        second = (await client.get(f'/api/study-play/battles/{mid}', headers=a)).json()['result']
        assert first == second and first['steps']
        assert (await client.post(f'/api/study-play/battles/{mid}/accept', headers=b)).status_code == 409
        assert (await client.get(f'/api/study-play/battles/{mid}', headers=c)).status_code == 409
        await client.delete('/api/study-desk', headers=b)
        assert (await client.get(f'/api/study-play/battles/{mid}', headers=a)).status_code == 409


@pytest.mark.asyncio
async def test_synced_review_evidence_requires_activity_and_deduplicates():
    from app.services.study_rewards import record_review_evidence
    a_id = None
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        a, aid = await account(client, '13900001001')
        state = {'records': [{'key': 'word:apple', 'reviews': 1, 'card': {'lastReview': datetime.now(timezone.utc).isoformat()}}]}
        async with SessionLocal() as db:
            await record_review_evidence(db, aid, state)
            await db.commit()
            assert not list((await db.execute(select(StudyReviewEvidence))).scalars())
        await client.post('/api/study-play/activity', headers=a, json={'seconds': 0})
        async with SessionLocal() as db:
            await record_review_evidence(db, aid, state)
            await record_review_evidence(db, aid, state)
            await db.commit()
            assert len(list((await db.execute(select(StudyReviewEvidence))).scalars())) == 1
        status = (await client.get('/api/study-play/checkin', headers=a)).json()
        assert status['review_target'] == 1 and status['eligible']


@pytest.mark.asyncio
async def test_challenge_join_leave_and_reward_are_idempotent():
    from app.models import StudyCheckin, UserCosmeticInventory
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        a, aid = await account(client, '13900001001')
        assert (await client.post('/api/study-play/challenges/review7/claim', headers=a)).status_code == 400
        await client.post('/api/study-play/challenges/review7/join', headers=a)
        from app.models import StudyChallengeMember
        async with SessionLocal() as db:
            member = await db.get(StudyChallengeMember, (aid, 'review7'))
            member.joined_day = day_key(datetime.now(timezone.utc) - timedelta(days=6))
            for i in range(7):
                db.add(StudyCheckin(user_id=aid, day=day_key(datetime.now(timezone.utc) - timedelta(days=i))))
            await db.commit()
        for _ in range(2):
            assert (await client.post('/api/study-play/challenges/review7/claim', headers=a)).status_code == 200
        await client.post('/api/study-play/challenges/review7/leave', headers=a)
        await client.post('/api/study-play/challenges/review7/join', headers=a)
        row = next(r for r in (await client.get('/api/study-play/challenges', headers=a)).json()['challenges'] if r['id'] == 'review7')
        assert row['progress'] == 7 and row['claimed']
        async with SessionLocal() as db:
            rewards = list((await db.execute(select(UserCosmeticInventory).where(UserCosmeticInventory.user_id == aid, UserCosmeticInventory.sku == 'accessory.headphones'))).scalars())
            assert len(rewards) == 1
