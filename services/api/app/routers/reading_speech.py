"""Content-addressed reading TTS on ECS (media_cache_dir/reading/tts/)."""

from __future__ import annotations

from fastapi import APIRouter, File, Form, HTTPException, Query, UploadFile
from pydantic import BaseModel, Field

from app.services import reading_speech_cache as rsc

router = APIRouter(prefix="/reading/speech", tags=["reading-speech"])


class SpeechLookupOut(BaseModel):
    hash: str
    voice: str
    language: str
    audio_url: str
    relative: str
    bytes: int


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


class SpeechHashIn(BaseModel):
    text: str = Field(..., min_length=1)
    voice: str = ""
    language: str = "en"


@router.post("/hash")
async def speech_hash(body: SpeechHashIn) -> dict:
    digest = rsc.speech_hash(body.text, voice=body.voice, language=body.language)
    return {
        "hash": digest,
        "voice": rsc.voice_segment(body.voice),
        "relative": rsc.cache_relative_path(voice=body.voice, digest=digest),
    }
