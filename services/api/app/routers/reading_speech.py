"""Aliyun Qwen TTS for reading / vocab, cached on ECS under media/reading/tts/."""

from __future__ import annotations

from pathlib import Path
from tempfile import NamedTemporaryFile

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.deps import get_current_user
from app.models import User
from app.services import api_usage as usage_svc
from app.services import reading_speech_cache as rsc
from app.services.reading_aliyun import BILINGUAL_VOICES, VOICES, QwenAudioTts

router = APIRouter(prefix="/reading/speech", tags=["reading-speech"])
voices_router = APIRouter(prefix="/reading", tags=["reading-speech"])

# Published voice catalog for settings + vocab pronunciation.
VOICE_LABELS: dict[str, str] = {
    "qwen-audio-3.0-tts-flash-loongolivialin": "Olivia Lin · 英音女声（推荐）",
    "qwen-audio-3.0-tts-flash-loonglunawang": "Luna Wang · 英音女声",
    "qwen-audio-3.0-tts-flash-loongnorahu": "Nora Hu · 英音女声",
    "qwen-audio-3.0-tts-flash-loongivyhu": "Ivy Hu · 英音女声",
    "qwen-audio-3.0-tts-flash-loongadriangao": "Adrian Gao · 英音男声",
    "qwen-audio-3.0-tts-flash-loongalexanderhu": "Alexander Hu · 英音男声",
    "qwen-audio-3.0-tts-flash-loongjameszhao": "James Zhao · 英音男声",
    "qwen-audio-3.0-tts-flash-loongryanma": "Ryan Ma · 英音男声",
    "longanfengyue": "龙安风悦 · 中英双语",
    "longanxiaoxin": "龙安小昕 · 中英双语",
    "longanlingxi": "龙安灵希 · 中英双语",
    "longshu_v3.1": "龙书 · 中英双语",
    "longxiaocheng_v3.1": "龙小诚 · 中英双语",
    "longsanshu_v3.1": "龙三叔 · 中英双语",
    "longze_v3.1": "龙泽 · 中英双语",
    "libai_v3.1": "李白 · 中英双语",
    "longanyang_v3.1": "龙安洋 · 中英双语",
    "longanlufeng": "龙安鲁风 · 中英双语",
    "longanhuan_v3.6": "龙安欢 · 中英双语",
}
NAMES = frozenset(VOICE_LABELS)
# English-first default for vocab / reading cards; bilingual voices stay selectable.
DEFAULT_VOICE = "qwen-audio-3.0-tts-flash-loongolivialin"


class SpeechLookupOut(BaseModel):
    hash: str
    voice: str
    language: str
    audio_url: str
    relative: str
    bytes: int


class Speech(BaseModel):
    text: str = Field(..., min_length=1, max_length=2000)
    voice: str = ""
    language: str = "en"


class SpeechHashIn(BaseModel):
    text: str = Field(..., min_length=1)
    voice: str = ""
    language: str = "en"


def _resolve_voice(raw: str) -> str:
    voice = (raw or "").strip()
    if voice in NAMES or voice in VOICES or voice in BILINGUAL_VOICES:
        return voice
    return DEFAULT_VOICE


def _configured() -> bool:
    return bool((settings.dashscope_api_key or "").strip())


@voices_router.get("/voices")
async def list_voices() -> dict:
    return {
        "voices": list(VOICE_LABELS.keys()),
        "labels": VOICE_LABELS,
        "default": DEFAULT_VOICE,
        "configured": _configured(),
    }


@router.post("")
@router.post("/")
async def speech(
    body: Speech,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    if not _configured():
        raise HTTPException(status_code=503, detail="阿里云配音尚未配置 DASHSCOPE_API_KEY")
    text = rsc.normalize_speech_text(body.text)
    if not text:
        raise HTTPException(status_code=400, detail="empty speech text")
    voice = _resolve_voice(body.voice)
    language = (body.language or "en").strip().lower() or "en"
    hit = rsc.lookup_url(text=text, voice=voice, language=language)
    if hit is not None:
        return {
            "audio_url": hit["audio_url"],
            "voice": voice,
            "provider": "aliyun-cache",
            "hash": hit["hash"],
        }
    tmp_path: str | None = None
    try:
        with NamedTemporaryFile(suffix=".mp3", delete=False) as tmp:
            tmp_path = tmp.name
        await QwenAudioTts(settings.dashscope_api_key).synthesize(
            text,
            tmp_path,
            voice=voice,
            language=language,
        )
        data = Path(tmp_path).read_bytes()
        saved = rsc.save_bytes(data, text=text, voice=voice, language=language)
        # TTS billed roughly by character; map chars → prompt_tokens for ledger.
        await usage_svc.record_usage(
            db,
            user_id=user.id,
            kind="tts",
            provider="dashscope",
            model=voice or "qwen-tts",
            module="reading_tts",
            prompt_tokens=max(1, len(text)),
            completion_tokens=0,
            api_key=settings.dashscope_api_key,
            key_owner="platform",
            note="reading_speech",
            audio_seconds=max(1.0, len(text.split()) * 0.35),
        )
        return {
            "audio_url": saved["audio_url"],
            "voice": voice,
            "provider": "aliyun-qwen",
            "hash": saved["hash"],
        }
    except Exception as exc:  # noqa: BLE001 — surface provider failures as 502
        raise HTTPException(status_code=502, detail=f"阿里云配音失败：{exc}") from exc
    finally:
        if tmp_path:
            Path(tmp_path).unlink(missing_ok=True)


@router.get("/lookup")
async def lookup_speech(
    text: str = Query(..., min_length=1),
    voice: str = Query(""),
    language: str = Query("en"),
) -> SpeechLookupOut:
    hit = rsc.lookup_url(text=text, voice=voice, language=language)
    if hit is None:
        raise HTTPException(status_code=404, detail="speech not cached")
    return SpeechLookupOut(**hit)


@router.post("/upload")
async def upload_speech(
    file: UploadFile = File(...),
    text: str = Form(...),
    voice: str = Form(""),
    language: str = Form("en"),
) -> dict:
    data = await file.read()
    try:
        return rsc.save_bytes(data, text=text, voice=voice, language=language)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/hash")
async def speech_hash(body: SpeechHashIn) -> dict:
    digest = rsc.speech_hash(body.text, voice=body.voice, language=body.language)
    return {
        "hash": digest,
        "voice": rsc.voice_segment(body.voice),
        "relative": rsc.cache_relative_path(voice=body.voice, digest=digest),
    }
