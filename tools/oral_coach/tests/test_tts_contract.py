import asyncio
import sys
from types import SimpleNamespace
from app.providers.qwen_audio_tts import PERSONA_VOICES, resolve_persona_speaker
from app.providers.tts import EdgeTts, MockTts, _edge_voice_for


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


def test_resolve_persona_speaker_follows_selected_avatar():
    assert resolve_persona_speaker(voice='', digital_human_id='leo') == PERSONA_VOICES['leo']
    assert resolve_persona_speaker(voice='', digital_human_id='emma') == PERSONA_VOICES['emma']
    assert resolve_persona_speaker(voice='longshu_v3.1', digital_human_id='mia') == 'longshu_v3.1'
    assert resolve_persona_speaker(voice='', digital_human_id='leo') != PERSONA_VOICES['mia']


def test_edge_fallback_uses_catalog_voice_per_persona(monkeypatch, tmp_path):
    calls = []
    class Communicate:
        def __init__(self, text, voice): calls.append(voice)
        async def save(self, path): pass
    monkeypatch.setitem(sys.modules, 'edge_tts', SimpleNamespace(Communicate=Communicate))
    asyncio.run(EdgeTts().synthesize('Hi', str(tmp_path / 'e.mp3'), voice='longanfengyue', digital_human_id='emma', language='en'))
    assert calls[-1] == 'en-US-JennyNeural'
    assert _edge_voice_for(voice=None, digital_human_id='leo', language='en') == 'en-US-GuyNeural'
    assert _edge_voice_for(voice=None, digital_human_id='arun', language='en') == 'en-IN-PrabhatNeural'
