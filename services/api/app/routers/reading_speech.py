"""Aliyun Qwen TTS for reading / vocab, cached on ECS under media/reading/tts/."""

from __future__ import annotations

import asyncio
from pathlib import Path
from tempfile import NamedTemporaryFile

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, Query, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.deps import get_current_user
from app.models import User
from app.services import api_usage as usage_svc
from app.services import reading_speech_cache as rsc
from app.services import reading_tts_queue as rtq
from app.services.reading_aliyun import BILINGUAL_VOICES, VOICES, QwenAudioTts

router = APIRouter(prefix="/reading/speech", tags=["reading-speech"])
voices_router = APIRouter(prefix="/reading", tags=["reading-speech"])

# Published voice catalog for settings + vocab pronunciation.
# CosyVoice bilingual narrators first — richer prosody for reading aloud.
VOICE_LABELS: dict[str, str] = {
    "longanfengyue": "龙安风悦 · 温暖有感染力（推荐）",
    "longshu_v3.1": "龙书 · 朗读书卷感",
    "longanxiaoxin": "龙安小昕 · 亲切活泼",
    "longanlingxi": "龙安灵希 · 甜美轻快",
    "longanhuan_v3.6": "龙安欢 · 元气感染力",
    "longxiaocheng_v3.1": "龙小诚 · 沉稳男声",
    "libai_v3.1": "李白 · 文气旁白",
    "longze_v3.1": "龙泽 · 磁性男声",
    "longanyang_v3.1": "龙安洋 · 中英双语",
    "longsanshu_v3.1": "龙三叔 · 中英双语",
    "longanlufeng": "龙安鲁风 · 中英双语",
    "qwen-audio-3.0-tts-flash-loongolivialin": "Olivia Lin · 英音女声",
    "qwen-audio-3.0-tts-flash-loonglunawang": "Luna Wang · 英音女声",
    "qwen-audio-3.0-tts-flash-loongnorahu": "Nora Hu · 英音女声",
    "qwen-audio-3.0-tts-flash-loongivyhu": "Ivy Hu · 英音女声",
    "qwen-audio-3.0-tts-flash-loongadriangao": "Adrian Gao · 英音男声",
    "qwen-audio-3.0-tts-flash-loongalexanderhu": "Alexander Hu · 英音男声",
    "qwen-audio-3.0-tts-flash-loongjameszhao": "James Zhao · 英音男声",
    "qwen-audio-3.0-tts-flash-loongryanma": "Ryan Ma · 英音男声",
}
NAMES = frozenset(VOICE_LABELS)
# Expressive CosyVoice default for reading / vocab cards.
DEFAULT_VOICE = "longanfengyue"


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


class PregenIn(BaseModel):
    doc_id: str = Field(..., min_length=1, max_length=200)
    text: str = Field(..., min_length=1, max_length=200_000)
    voice: str = ""
    page_index: int = 0
    language: str = "en"
    ## When true, ECS fills missing sentences if the 5060 Ti worker is idle.
    process_on_ecs: bool = True


class BookPregenIn(BaseModel):
    doc_id: str = Field(..., min_length=1, max_length=200)
    text: str = Field(..., min_length=1, max_length=600_000)
    voice: str = ""
    language: str = "en"
    ## Prefer 5060 Ti worker; set true only as ECS fallback filler.
    process_on_ecs: bool = False


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


async def _synthesize_and_cache(
    *,
    text: str,
    voice: str,
    language: str,
    user_id: int | None,
) -> dict:
    hit = rsc.lookup_url(text=text, voice=voice, language=language)
    if hit is not None:
        return hit
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
        if user_id:
            from app.database import SessionLocal

            async with SessionLocal() as db:
                await usage_svc.record_usage(
                    db,
                    user_id=user_id,
                    kind="tts",
                    provider="dashscope",
                    model=voice or "qwen-tts",
                    module="reading_tts_pregen",
                    prompt_tokens=max(1, len(text)),
                    completion_tokens=0,
                    api_key=settings.dashscope_api_key,
                    key_owner="platform",
                    note="reading_speech_pregen",
                    audio_seconds=max(1.0, len(text.split()) * 0.35),
                )
        return saved
    finally:
        if tmp_path:
            Path(tmp_path).unlink(missing_ok=True)


async def process_pregen_job(job_id: str, *, user_id: int | None = None) -> None:
    """ECS fallback filler when the 5060 Ti worker is not claiming jobs."""
    if not _configured():
        return
    claimed = rtq.claim_id(job_id, lease_seconds=600)
    if claimed is None:
        return
    lease = claimed.get("lease") or ""
    voice = claimed.get("voice") or DEFAULT_VOICE
    language = "en"
    payload = claimed.get("payload") or {}
    sentences = list(payload.get("sentences") or [])
    try:
        for i, item in enumerate(sentences):
            if not isinstance(item, dict):
                continue
            text = rsc.normalize_speech_text(str(item.get("text") or ""))
            if not text:
                continue
            existing = rsc.lookup_url(text=text, voice=voice, language=language)
            if existing is not None:
                sentences[i] = {
                    "text": text,
                    "hash": existing.get("hash"),
                    "audio_url": existing.get("audio_url"),
                    "ready": True,
                }
                continue
            saved = await _synthesize_and_cache(
                text=text,
                voice=voice,
                language=language,
                user_id=user_id,
            )
            sentences[i] = {
                "text": text,
                "hash": saved.get("hash")
                or rsc.speech_hash(text, voice=voice, language=language),
                "audio_url": saved.get("audio_url"),
                "ready": True,
            }
            rtq.heartbeat(job_id, lease, state="working")
            await asyncio.sleep(0)
        rtq.complete(job_id, lease, payload={"sentences": sentences})
    except Exception as exc:  # noqa: BLE001
        rtq.fail(job_id, lease, str(exc))


@router.post("/pregen")
async def enqueue_pregen(
    body: PregenIn,
    background: BackgroundTasks,
    user: User = Depends(get_current_user),
) -> dict:
    """Queue one reading page for background TTS → ECS shared + personal packs."""
    voice = _resolve_voice(body.voice)
    try:
        job = rtq.enqueue(
            doc_id=body.doc_id.strip(),
            voice=voice,
            page_index=body.page_index,
            text=body.text,
            user_id=user.id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    pack = rtq.load_shared_pack(
        doc_id=body.doc_id.strip(),
        voice=voice,
        page_index=body.page_index,
    )
    if job.get("state") != "done" and body.process_on_ecs and _configured():
        background.add_task(process_pregen_job, job["id"], user_id=user.id)
    return {
        "job": job,
        "pack": pack,
        "voice": voice,
        "message": "queued" if job.get("state") != "done" else "ready",
    }


@router.get("/pregen/{job_id}")
async def pregen_status(
    job_id: str,
    user: User = Depends(get_current_user),
) -> dict:
    del user  # auth gate only
    job = rtq.status(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="job not found")
    pack = rtq.load_shared_pack(
        doc_id=job["doc_id"],
        voice=job["voice"],
        page_index=job["page_index"],
    )
    return {"job": job, "pack": pack}


@router.get("/pack")
async def get_speech_pack(
    doc_id: str = Query(..., min_length=1),
    voice: str = Query(""),
    page_index: int = Query(0),
    user: User = Depends(get_current_user),
) -> dict:
    del user
    voice_id = _resolve_voice(voice)
    pack = rtq.load_shared_pack(
        doc_id=doc_id.strip(),
        voice=voice_id,
        page_index=page_index,
    )
    if pack is None:
        raise HTTPException(status_code=404, detail="pack not ready")
    return pack


@router.post("/book-pregen")
async def enqueue_book_pregen(
    body: BookPregenIn,
    background: BackgroundTasks,
    user: User = Depends(get_current_user),
) -> dict:
    """Queue an entire long novel for cloud TTS (5060 Ti preferred)."""
    voice = _resolve_voice(body.voice)
    text = body.text.replace("\r\n", "\n")
    if not rtq.is_long_novel(text):
        # Short articles stay open-immediately; no book gate.
        return {
            "ready": True,
            "state": "skipped",
            "percent": 100,
            "pages_total": 0,
            "pages_ready": 0,
            "long_novel": False,
            "processor": "none",
            "message": "short_article",
        }
    try:
        status = rtq.enqueue_book(
            doc_id=body.doc_id.strip(),
            voice=voice,
            text=text,
            user_id=user.id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if body.process_on_ecs and _configured() and not status.get("ready"):
        for job_id in rtq.unfinished_page_job_ids(
            doc_id=body.doc_id.strip(), voice=voice
        ):
            background.add_task(process_pregen_job, job_id, user_id=user.id)
    return {
        **status,
        "message": "ready" if status.get("ready") else "queued_for_gpu",
    }


@router.get("/book-pregen")
async def book_pregen_status(
    doc_id: str = Query(..., min_length=1),
    voice: str = Query(""),
    user: User = Depends(get_current_user),
) -> dict:
    del user
    return rtq.book_status(doc_id=doc_id.strip(), voice=_resolve_voice(voice))


@router.post("/book-pregen/fallback")
async def book_pregen_ecs_fallback(
    body: BookPregenIn,
    background: BackgroundTasks,
    user: User = Depends(get_current_user),
) -> dict:
    """Kick ECS filler for unfinished pages when the 5060 Ti worker is offline."""
    voice = _resolve_voice(body.voice)
    if body.text.strip():
        try:
            rtq.enqueue_book(
                doc_id=body.doc_id.strip(),
                voice=voice,
                text=body.text,
                user_id=user.id,
            )
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
    if not _configured():
        raise HTTPException(status_code=503, detail="阿里云配音尚未配置")
    job_ids = rtq.unfinished_page_job_ids(doc_id=body.doc_id.strip(), voice=voice)
    for job_id in job_ids:
        background.add_task(process_pregen_job, job_id, user_id=user.id)
    status = rtq.book_status(doc_id=body.doc_id.strip(), voice=voice)
    return {
        **status,
        "fallback": "ecs",
        "kicked": len(job_ids),
        "message": "ecs_fallback_started",
    }
