import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from test_study_desk import clean, setup_pair
from app.main import app
from app.database import SessionLocal
from app.models import CommunityPost
from app.config import settings

async def post(db, uid):
    row = CommunityPost(user_id=uid, kind='share_bilibili', title='咖啡店英语', body='学习分享', bvid='BV1GJ411x7h7', link_url='https://www.bilibili.com/video/BV1GJ411x7h7', status='visible')
    db.add(row)
    await db.commit()
    return row.id

@pytest.mark.asyncio
async def test_follow_bookmark_notices_and_owner_delete():
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        a, aid, b, bid, c, cid = await setup_pair(client)
        async with SessionLocal() as db: pid = await post(db, aid)
        assert (await client.put(f'/api/community-social/following/{aid}', headers=b)).status_code == 200
        await client.put(f'/api/community-social/following/{aid}', headers=b)
        assert (await client.put(f'/api/community-social/bookmarks/{pid}', headers=b)).status_code == 200
        saved = (await client.get('/api/community/feed?bookmarked=true', headers=b)).json()
        assert len(saved) == 1 and saved[0]['id'] == pid
        notices = (await client.get('/api/community-social/notices', headers=a)).json()['notices']
        assert len(notices) == 2
        nid = notices[0]['id']
        await client.put(f'/api/community-social/notices/{nid}/read', headers=b)
        notices = (await client.get('/api/community-social/notices', headers=a)).json()['notices']
        assert not notices[0]['read']
        await client.put(f'/api/community-social/notices/{nid}/read', headers=a)
        assert (await client.get('/api/community-social/notices', headers=a)).json()['notices'][0]['read']
        assert (await client.delete(f'/api/community-social/posts/{pid}', headers=b)).status_code == 404
        assert (await client.get(f'/api/community-social/posts/{pid}', headers=b)).status_code == 200
        assert (await client.delete(f'/api/community-social/posts/{pid}', headers=a)).status_code == 200
        assert (await client.get(f'/api/community-social/posts/{pid}', headers=b)).status_code == 404

@pytest.mark.asyncio
async def test_block_hides_content_and_prevents_legacy_interactions():
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        a, aid, b, bid, c, cid = await setup_pair(client)
        async with SessionLocal() as db: pid = await post(db, aid)
        await client.put(f'/api/community-social/blocks/{aid}', headers=b)
        assert (await client.get('/api/community/feed', headers=b)).json() == []
        assert (await client.post(f'/api/community/posts/{pid}/like', headers=b)).status_code == 404
        assert (await client.post(f'/api/community/posts/{pid}/comments', headers=b, json={'body': 'hello'})).status_code == 404
        assert (await client.get('/api/study-desk', headers=a)).json()['peer'] is None
        await client.delete(f'/api/community-social/blocks/{aid}', headers=b)
        assert len((await client.get('/api/community/feed', headers=b)).json()) == 1

@pytest.mark.asyncio
async def test_report_requires_admin_credential_and_hides_post(monkeypatch):
    monkeypatch.setattr(settings, 'community_admin_token', 'test-admin-only')
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        a, aid, b, bid, c, cid = await setup_pair(client)
        async with SessionLocal() as db: pid = await post(db, aid)
        assert (await client.post(f'/api/community-social/posts/{pid}/report', headers=b, json={'reason': '内容不实'})).status_code == 201
        assert (await client.get('/api/community-social/moderation', headers=a)).status_code == 403
        admin = {'X-Community-Admin-Token': 'test-admin-only'}
        rid = (await client.get('/api/community-social/moderation', headers=admin)).json()['reports'][0]['id']
        assert (await client.post(f'/api/community-social/moderation/{rid}', headers=admin, json={'action': 'hide', 'note': '核实后下架'})).status_code == 200
        assert (await client.get('/api/community/feed', headers=b)).json() == []
        assert (await client.get('/api/community-social/reports', headers=b)).json()['reports'][0]['status'] == 'hide'
        assert (await client.get('/api/community-social/reports', headers=c)).json()['reports'] == []

@pytest.mark.asyncio
async def test_public_learning_card_requires_confirmation_safe_source_and_revoke():
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        a, aid, b, bid, c, cid = await setup_pair(client)
        async with SessionLocal() as db: pid = await post(db, aid)
        card = await client.post('/api/learning-cards', headers=a, json={'post_id': pid, 'expression': '<script>alert(1)</script>', 'meaning': '慢慢来'})
        assert card.status_code == 201, card.text
        token = card.json()['token']
        public = await client.get(f'/api/public/learning-cards/{token}')
        assert public.status_code == 200
        assert '&lt;script&gt;' in public.text and '<script>alert' not in public.text
        assert 'Content-Security-Policy' in public.headers
        assert (await client.get(f'/api/learning-cards/{token}')).json()['watch_url'].startswith('https://www.bilibili.com/video/BV')
        assert (await client.delete(f'/api/learning-cards/{token}', headers=b)).status_code == 404
        assert (await client.delete(f'/api/learning-cards/{token}', headers=a)).status_code == 200
        assert (await client.get(f'/api/learning-cards/{token}')).status_code == 404

@pytest.mark.asyncio
async def test_like_target_state_is_idempotent_and_comment_sends_notice():
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        a, aid, b, bid, c, cid = await setup_pair(client)
        async with SessionLocal() as db: pid = await post(db, aid)
        for _ in range(2):
            liked = await client.put(f'/api/community-social/posts/{pid}/like', headers=b, json={'enabled': True})
            assert liked.status_code == 200, liked.text
            assert liked.json()['like_count'] == 1
        assert (await client.post(f'/api/community/posts/{pid}/comments', headers=b, json={'body': '很有帮助'})).status_code == 201
        notices = (await client.get('/api/community-social/notices', headers=a)).json()['notices']
        assert len(notices) == 3
        unliked = await client.put(f'/api/community-social/posts/{pid}/like', headers=b, json={'enabled': False})
        assert unliked.json()['like_count'] == 0


@pytest.mark.asyncio
async def test_production_seed_is_hidden_and_notification_optout_works(monkeypatch):
    from app.services.community_seed import ensure_community_seed
    from app.models import User
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as client:
        a, aid, b, bid, c, cid = await setup_pair(client)
        assert (await client.put('/api/community-social/notifications', headers=a, json={'enabled': False})).status_code == 200
        await client.put(f'/api/community-social/following/{aid}', headers=b)
        notices = (await client.get('/api/community-social/notices', headers=a)).json()['notices']
        assert len(notices) == 1 and '接受' in notices[0]['text']
        monkeypatch.setattr(settings, 'production_mode', True)
        async with SessionLocal() as db:
            await ensure_community_seed(db)
            assert not list((await db.execute(select(User).where(User.email == 'community.seed@acquire.local'))).scalars())
