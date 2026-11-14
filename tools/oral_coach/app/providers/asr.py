from __future__ import annotations

from pathlib import Path

import httpx

from ..config import Settings
from .base import AsrResult


class MockAsr:
    name = 'mock'

    async def transcribe(self, audio_path: str, language: str = 'en') -> AsrResult:
        # Deterministic mock — never echo temp filenames as speech.
        _ = (audio_path, language)
        return AsrResult(
            transcript='I am practicing this line from the video.',
            provider=self.name,
            confidence=0.66,
        )


class DeepgramAsr:
    name = 'deepgram'

    def __init__(self, api_key: str):
        self.api_key = api_key

    async def transcribe(self, audio_path: str, language: str = 'en') -> AsrResult:
        if not self.api_key:
            raise RuntimeError('DEEPGRAM_API_KEY is empty.')
        path = Path(audio_path)
        data = path.read_bytes()
        suffix = path.suffix.lower()
        content_type = {
            '.wav': 'audio/wav',
            '.mp3': 'audio/mpeg',
            '.m4a': 'audio/mp4',
            '.ogg': 'audio/ogg',
            '.webm': 'audio/webm',
            '.flac': 'audio/flac',
        }.get(suffix, 'application/octet-stream')
        async with httpx.AsyncClient(timeout=90) as client:
            response = await client.post(
                'https://api.deepgram.com/v1/listen',
                params={
                    'model': 'nova-2',
                    'language': language or 'en',
                    'punctuate': 'true',
                    'smart_format': 'true',
                },
                content=data,
                headers={
                    'Authorization': f'Token {self.api_key}',
                    'Content-Type': content_type,
                },
            )
            response.raise_for_status()
            body = response.json()
        alt = (
            body.get('results', {})
            .get('channels', [{}])[0]
            .get('alternatives', [{}])[0]
        )
        transcript = (alt.get('transcript') or '').strip()
        confidence = alt.get('confidence')
        words = alt.get('words') or []
        return AsrResult(
            transcript=transcript or '(empty)',
            provider=self.name,
            confidence=float(confidence) if confidence is not None else None,
            words=words if isinstance(words, list) else [],
        )


class WhisperXAsr:
    """Adapter shell — install whisperx locally, then flesh out load/transcribe."""

    name = 'whisperx'

    def __init__(self, model: str):
        self.model = model

    async def transcribe(self, audio_path: str, language: str = 'en') -> AsrResult:
        try:
            import whisperx  # type: ignore
        except ImportError as exc:
            raise RuntimeError(
                'WhisperX not installed. pip install whisperx, or set ASR_PROVIDER=mock|deepgram.'
            ) from exc
        # Minimal sync call inside async boundary for v1 scaffold.
        device = 'cpu'
        model = whisperx.load_model(self.model, device, compute_type='int8')
        audio = whisperx.load_audio(audio_path)
        result = model.transcribe(audio, batch_size=8, language=language)
        parts = [seg.get('text', '').strip() for seg in result.get('segments', [])]
        transcript = ' '.join(p for p in parts if p).strip()
        return AsrResult(transcript=transcript or '(empty)', provider=self.name)


def build_asr(settings: Settings):
    name = settings.asr_provider
    if name == 'deepgram':
        return DeepgramAsr(settings.deepgram_api_key)
    if name == 'whisperx':
        return WhisperXAsr(settings.whisperx_model)
    return MockAsr()
