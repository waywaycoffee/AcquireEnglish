from __future__ import annotations

import os

os.environ['DATABASE_URL'] = 'sqlite+aiosqlite:///./test_oral_match.db'
os.environ['AUTH_SMS_MOCK'] = 'true'
os.environ['AUTH_WECHAT_MOCK'] = 'true'

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import Base, engine
from app.main import app


@pytest_asyncio.fixture(autouse=True)
async def clean():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield


async def account(client: AsyncClient, phone: str) -> dict[str, str]:
    sent = await client.post('/api/auth/sms/send', json={'phone': phone})
    login = await client.post(
        '/api/auth/sms/login',
        json={'phone': phone, 'code': sent.json()['debug_code']},
    )
    assert login.status_code == 200, login.text
    return {'Authorization': 'Bearer ' + login.json()['access_token']}


@pytest.mark.asyncio
async def test_oral_match_pairs_two_users():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url='http://test') as client:
        a = await account(client, '13900002001')
        b = await account(client, '13900002002')

        first = await client.post('/api/oral-match/enqueue', headers=a)
        assert first.status_code == 200, first.text
        assert first.json()['status'] == 'waiting'

        second = await client.post('/api/oral-match/enqueue', headers=b)
        assert second.status_code == 200, second.text
        body = second.json()
        assert body['status'] == 'matched'
        room_id = body['room_id']
        assert room_id
        assert 'peer_online' in body

        status_a = await client.get('/api/oral-match/status', headers=a)
        assert status_a.json()['status'] == 'matched'
        assert status_a.json()['room_id'] == room_id

        beat = await client.post('/api/oral-match/heartbeat', headers=a)
        assert beat.status_code == 200
        assert beat.json()['status'] == 'matched'

        sent = await client.post(
            f'/api/oral-match/rooms/{room_id}/messages',
            headers=b,
            json={'text': 'I just popped to the supermarket.'},
        )
        assert sent.status_code == 200, sent.text

        inbox = await client.get(
            f'/api/oral-match/rooms/{room_id}/messages',
            headers=a,
        )
        assert inbox.status_code == 200, inbox.text
        messages = inbox.json()['messages']
        assert any(m['text'].startswith('I just popped') for m in messages)
        assert any(m['mine'] is False for m in messages)

        leave = await client.post('/api/oral-match/leave', headers=b)
        assert leave.status_code == 200
        left_status = await client.get('/api/oral-match/status', headers=a)
        assert left_status.json()['status'] == 'peer_left'


@pytest.mark.asyncio
async def test_oral_match_report():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url='http://test') as client:
        a = await account(client, '13900002011')
        b = await account(client, '13900002012')
        await client.post('/api/oral-match/enqueue', headers=a)
        matched = await client.post('/api/oral-match/enqueue', headers=b)
        room_id = matched.json()['room_id']
        reported = await client.post(
            f'/api/oral-match/rooms/{room_id}/report',
            headers=a,
            json={'reason': 'spam'},
        )
        assert reported.status_code == 200
        assert reported.json()['status'] == 'reported'
