"""Unit tests for agent hooks without LiveKit."""

from __future__ import annotations

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

import pytest


@pytest.mark.asyncio
async def test_score_pronunciation_uses_oral_coach_text_endpoint():
    from agent import hooks

    response = MagicMock()
    response.status_code = 200
    response.json.return_value = {
        'transcript': 'hello world',
        'pronunciation': {'overall': 0.91, 'method': 'simple_text'},
        'providers': {'pronunciation': 'simple'},
    }

    client = AsyncMock()
    client.__aenter__.return_value = client
    client.__aexit__.return_value = None
    client.post = AsyncMock(return_value=response)

    with patch.object(hooks.httpx, 'AsyncClient', return_value=client):
        scored = await hooks.score_pronunciation(
            transcript='hello world',
            reference_text='hello world',
        )
    assert scored['pronunciation']['overall'] == 0.91
    assert scored['providers']['pronunciation'] == 'simple'
    client.post.assert_awaited()


@pytest.mark.asyncio
async def test_persist_skips_without_bearer_or_email():
    from agent import hooks

    out = await hooks.persist_learning_turn(
        learning_session_id=None,
        transcript='hi',
        coach_text='hello',
        user_email='',
    )
    assert out is None


def test_checklist_importable():
    # Ensure agent package loads under tools/digital_human_coach cwd.
    import agent.main as main

    assert callable(main.run)
