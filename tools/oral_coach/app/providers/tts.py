from __future__ import annotations

import logging
import wave
from pathlib import Path

from ..config import Settings
from .base import TtsResult
from .qwen_audio_tts import BILINGUAL_VOICES, VOICES, QwenAudioTts

logger = logging.getLogger(__name__)


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

    async def synthesize(self, text: str, out_path: str, *, voice: str | None = None, digital_human_id: str | None = None, language: str | None = None) -> TtsResult:
        Path(out_path).parent.mkdir(parents=True, exist_ok=True)
        # Duration scales mildly with text length so UI can show a cue.
        seconds = min(4.0, 0.35 + 0.04 * max(1, len(text.split())))
        _write_silent_wav(out_path, seconds=seconds)
        return TtsResult(audio_path=out_path, provider=self.name)


class EdgeTts:
    name = 'edge'

    async def synthesize(self, text: str, out_path: str, *, voice: str | None = None, digital_human_id: str | None = None, language: str | None = None) -> TtsResult:
        try:
            import edge_tts  # type: ignore
        except ImportError as exc:
            raise RuntimeError('pip install edge-tts, or set TTS_PROVIDER=mock.') from exc
        communicate = edge_tts.Communicate(text, voice or ('zh-CN-XiaoxiaoNeural' if (language or '').startswith('zh') else 'en-US-JennyNeural'))
        await communicate.save(out_path)
        return TtsResult(audio_path=out_path, provider=self.name, mime='audio/mpeg')


class XttsTts:
    name = 'xtts'

    async def synthesize(self, text: str, out_path: str, *, voice: str | None = None, digital_human_id: str | None = None, language: str | None = None) -> TtsResult:
        raise RuntimeError(
            'XTTS scaffold: point to your Coqui XTTS server / local API, then implement synthesize().'
        )


class FishSpeechTts:
    name = 'fishspeech'

    async def synthesize(self, text: str, out_path: str, *, voice: str | None = None, digital_human_id: str | None = None, language: str | None = None) -> TtsResult:
        raise RuntimeError(
            'FishSpeech scaffold: call your FishSpeech HTTP endpoint here.'
        )


_MALE_PERSONAS = frozenset({
    'leo', 'arun', 'alexander', 'adrian', 'james', 'ryan', 'finley', 'miles',
})


def _is_cloud_voice(voice: str | None) -> bool:
    name = (voice or '').strip().lower()
    if not name:
        return False
    if name in VOICES or name in BILINGUAL_VOICES:
        return True
    # CosyVoice / Qwen ids must never be forwarded to edge-tts unchanged.
    return name.startswith('long') or name.startswith('qwen-') or '-loong' in name


def _edge_voice_for(*, voice: str | None, digital_human_id: str | None, language: str | None) -> str:
    chinese = (language or '').lower().startswith('zh')
    male = (digital_human_id or '').strip().lower() in _MALE_PERSONAS
    if chinese:
        return 'zh-CN-YunxiNeural' if male else 'zh-CN-XiaoxiaoNeural'
    return 'en-US-GuyNeural' if male else 'en-US-AriaNeural'


def _is_edge_voice(voice: str | None) -> bool:
    name = (voice or '').strip()
    if not name:
        return False
    lower = name.lower()
    return lower.endswith('neural') or lower.startswith('zh-') or lower.startswith('en-')


class CoachTts:
    def __init__(self, english: QwenAudioTts, edge: EdgeTts) -> None:
        self.english = english
        self.edge = edge

    async def synthesize(self, text: str, out_path: str, *, voice: str | None = None, digital_human_id: str | None = None, language: str | None = None) -> TtsResult:
        options = dict(voice=voice, digital_human_id=digital_human_id, language=language)
        chinese = (language or '').lower().startswith('zh')
        voice_name = (voice or '').strip()
        # English-only Qwen voices / explicit Edge ids: Chinese replies use Edge.
        if chinese and (voice_name in VOICES or _is_edge_voice(voice_name)):
            if voice_name in VOICES or _is_cloud_voice(voice_name):
                options['voice'] = _edge_voice_for(
                    voice=voice,
                    digital_human_id=digital_human_id,
                    language=language,
                )
            return await self.edge.synthesize(text, out_path, **options)
        if _is_edge_voice(voice_name) and not _is_cloud_voice(voice_name):
            return await self.edge.synthesize(text, out_path, **options)
        # Prefer Qwen: unknown ids are remapped to the persona default.
        try:
            return await self.english.synthesize(text, out_path, **options)
        except Exception as exc:
            logger.warning('Coach TTS fell back to Edge (%s)', type(exc).__name__)
        if _is_cloud_voice(voice):
            options['voice'] = _edge_voice_for(
                voice=voice,
                digital_human_id=digital_human_id,
                language=language,
            )
        return await self.edge.synthesize(text, out_path, **options)


def build_tts(settings: Settings):
    name = settings.tts_provider
    if name == 'qwen-audio':
        return CoachTts(QwenAudioTts(settings.dashscope_api_key), EdgeTts())
    if name == 'edge':
        return EdgeTts()
    if name == 'xtts':
        return XttsTts()
    if name == 'fishspeech':
        return FishSpeechTts()
    return MockTts()
