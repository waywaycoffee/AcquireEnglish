import asyncio

import pytest

from app.config import Settings
from app.pipeline import OralCoachPipeline
from app.providers.base import VideoContext


class _SlowLlm:
    name = 'slow-test'

    async def coach_turn(self, **_kwargs):
        await asyncio.sleep(1)
        raise AssertionError('timeout should cancel the slow provider')


@pytest.mark.asyncio
async def test_llm_timeout_returns_topic_grounded_fallback(tmp_path):
    settings = Settings(
        data_dir=tmp_path,
        asr_provider='mock',
        pron_provider='simple',
        llm_provider='mock',
        tts_provider='mock',
        avatar_provider='none',
        llm_turn_timeout_seconds=0.01,
    )
    pipeline = OralCoachPipeline(settings)
    pipeline.llm = _SlowLlm()
    session = pipeline.create_session(
        VideoContext(topic_summary='weekend activities', difficulty='B1'),
    )
    session.drafts['draft'] = {
        'audio_path': '',
        'transcript': 'I played basketball yesterday.',
        'reference': 'I played basketball yesterday.',
        'pronunciation': {
            'overall': 1.0,
            'provider': 'simple',
            'notes': '',
            'word_scores': [],
            'phonemes': [],
        },
    }

    result = await pipeline.confirm_draft(
        session,
        'draft',
        text_only=True,
    )

    assert result.coach_text
    assert result.tts_url is None
    assert session.history[-1]['role'] == 'assistant'
