import asyncio
from pathlib import Path
from types import SimpleNamespace


def test_reading_speech_uses_published_aliyun_voice_and_cache(tmp_path, monkeypatch):
    from app.routers import reading_speech as r

    calls: list[str] = []

    class FakeAliyun:
        def __init__(self, key: str) -> None:
            assert key == 'test-only'

        async def synthesize(self, text: str, path: str, **kwargs: object) -> str:
            calls.append(str(kwargs.get('voice') or ''))
            Path(path).write_bytes(b'test-audio-bytes-' + (b'x' * 80))
            return path

    monkeypatch.setattr(r, 'QwenAudioTts', FakeAliyun)
    monkeypatch.setattr(r.settings, 'dashscope_api_key', 'test-only')
    monkeypatch.setattr(r.settings, 'media_cache_dir', str(tmp_path))
    monkeypatch.setattr(r.settings, 'media_public_base', 'https://example.test')

    async def run() -> None:
        voice = next(iter(r.NAMES))
        body = r.Speech(text='Hello.', voice=voice)
        user = SimpleNamespace(id=1)
        first = await r.speech(body, user)
        second = await r.speech(body, user)
        assert first['audio_url'] == second['audio_url']
        assert first['voice'] == second['voice'] == voice
        assert first['provider'] == 'aliyun-qwen'
        assert second['provider'] == 'aliyun-cache'
        assert len(calls) == 1
        assert list((tmp_path / 'reading' / 'tts').rglob('*.mp3'))

    asyncio.run(run())


def test_reading_voices_lists_default_bilingual() -> None:
    from app.routers import reading_speech as r

    async def run() -> None:
        data = await r.list_voices()
        assert data['default'] == 'longanfengyue'
        assert 'longanfengyue' in data['voices']
        assert data['labels']['longanfengyue']

    asyncio.run(run())
