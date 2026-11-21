import asyncio
import sys
from types import SimpleNamespace
from app.providers.tts import MockTts, EdgeTts


def test_mock_accepts_pipeline_keywords(tmp_path):
    result = asyncio.run(MockTts().synthesize('Hello', str(tmp_path / 'audio.wav'), voice='en-US-JennyNeural', digital_human_id='mia', language='en'))
    assert result.provider == 'mock' and (tmp_path / 'audio.wav').exists()


def test_edge_uses_explicit_voice_and_accepts_character(monkeypatch, tmp_path):
    calls = []
    class Communicate:
        def __init__(self, text, voice): calls.append((text, voice))
        async def save(self, path): pass
    monkeypatch.setitem(sys.modules, 'edge_tts', SimpleNamespace(Communicate=Communicate))
    result = asyncio.run(EdgeTts().synthesize('Hello', str(tmp_path / 'audio.mp3'), voice='en-US-GuyNeural', digital_human_id='mia', language='en'))
    assert calls == [('Hello', 'en-US-GuyNeural')]
    assert result.mime == 'audio/mpeg'
