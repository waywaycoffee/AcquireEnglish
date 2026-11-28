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
        assert data['default'] == 'qwen-audio-3.0-tts-flash-loongolivialin'
        assert 'qwen-audio-3.0-tts-flash-loongolivialin' in data['voices']
        assert data['labels']['qwen-audio-3.0-tts-flash-loongolivialin']
        assert 'longanfengyue' in data['voices']

    asyncio.run(run())


def test_reading_source_limits_hosts_and_starters_have_text():
    from app.routers.reading_source import allowed, starter
    assert allowed('https://raw.githubusercontent.com/nishkalavallabhi/OneStopEnglishCorpus/master/a.txt')
    assert not allowed('https://raw.githubusercontent.com/other/repo/a.txt')
    assert not allowed('https://raw.githubusercontent.com/nishkalavallabhi/OneStopEnglishCorpus/%2e%2e/secret')
    assert not allowed('http://127.0.0.1/secret')
    data = asyncio.run(starter())
    assert len(data['documents']) == 5
    assert all(d['plainText'] for d in data['documents'])


def test_standard_ebooks_proxy_allows_only_book_archives():
    from app.routers.reading_source import allowed
    assert allowed('https://github.com/standardebooks/jane-austen_pride-and-prejudice/archive/refs/heads/master.zip')
    assert allowed('https://codeload.github.com/standardebooks/jane-austen_pride-and-prejudice/zip/refs/heads/master')
    assert not allowed('https://github.com/other/private/archive/refs/heads/master.zip')
    assert not allowed('https://codeload.github.com/standardebooks/repo/anything')
    assert allowed('https://standardebooks.org/ebooks?per-page=48&view=list&page=2')
    assert not allowed('https://standardebooks.org/ebooks?page=1&next=https://evil.example')
    assert allowed('https://api.github.com/repos/bookdash/bookdash-books/git/trees/gh-pages?recursive=1')
    assert not allowed('https://api.github.com/repos/bookdash/bookdash-books/zipball/gh-pages')
    assert allowed('https://raw.githubusercontent.com/bookdash/bookdash-books/gh-pages/sleepy-mr-sloth/en/index.md')
    assert not allowed('https://raw.githubusercontent.com/bookdash/bookdash-books/gh-pages/sleepy-mr-sloth/en/images/01.jpg')
    assert allowed('https://bookdash.org/books/sleepy-mr-sloth/')
    assert not allowed('https://bookdash.org/wp-admin/')
    assert allowed('https://learningenglish.voanews.com/api/zmypyl-vomx-tpeyry_')
    assert allowed('https://learningenglish.voanews.com/a/watching-the-grass-grow-is-not-fun/8003108.html')
    assert not allowed('https://learningenglish.voanews.com/p/5374.html')
    assert not allowed('https://www.voanews.com/a/watching-the-grass-grow-is-not-fun/8003108.html')
