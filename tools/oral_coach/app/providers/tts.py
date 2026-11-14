from __future__ import annotations

import wave
from pathlib import Path

from ..config import Settings
from .base import TtsResult


def _write_silent_wav(path: str, seconds: float = 0.6) -> None:
    rate = 16000
    frames = int(rate * seconds)
    with wave.open(path, 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(b'\x00\x00' * frames)


class MockTts:
    name = 'mock'

    async def synthesize(self, text: str, out_path: str) -> TtsResult:
        Path(out_path).parent.mkdir(parents=True, exist_ok=True)
        # Duration scales mildly with text length so UI can show a cue.
        seconds = min(4.0, 0.35 + 0.04 * max(1, len(text.split())))
        _write_silent_wav(out_path, seconds=seconds)
        return TtsResult(audio_path=out_path, provider=self.name)


class EdgeTts:
    name = 'edge'

    async def synthesize(self, text: str, out_path: str) -> TtsResult:
        try:
            import edge_tts  # type: ignore
        except ImportError as exc:
            raise RuntimeError('pip install edge-tts, or set TTS_PROVIDER=mock.') from exc
        communicate = edge_tts.Communicate(text, 'en-US-JennyNeural')
        await communicate.save(out_path)
        return TtsResult(audio_path=out_path, provider=self.name, mime='audio/mpeg')


class XttsTts:
    name = 'xtts'

    async def synthesize(self, text: str, out_path: str) -> TtsResult:
        raise RuntimeError(
            'XTTS scaffold: point to your Coqui XTTS server / local API, then implement synthesize().'
        )


class FishSpeechTts:
    name = 'fishspeech'

    async def synthesize(self, text: str, out_path: str) -> TtsResult:
        raise RuntimeError(
            'FishSpeech scaffold: call your FishSpeech HTTP endpoint here.'
        )


def build_tts(settings: Settings):
    name = settings.tts_provider
    if name == 'edge':
        return EdgeTts()
    if name == 'xtts':
        return XttsTts()
    if name == 'fishspeech':
        return FishSpeechTts()
    return MockTts()
