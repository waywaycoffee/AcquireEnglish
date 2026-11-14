from __future__ import annotations

import tempfile
from pathlib import Path
from typing import Any

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field

from .config import Settings
from .pipeline import OralCoachPipeline
from .providers.base import VideoContext

settings = Settings.from_env()
pipeline = OralCoachPipeline(settings)
app = FastAPI(title='AcquireEnglish Oral Coach', version='0.1.0')


class SessionCreate(BaseModel):
    course_title: str = ''
    episode_title: str = ''
    current_english: str = ''
    current_chinese: str = ''
    previous_english: str = ''
    next_english: str = ''
    difficulty: str = Field(default='B1', pattern=r'^(A2|B1|B2|C1)$')


class ContextUpdate(BaseModel):
    course_title: str | None = None
    episode_title: str | None = None
    current_english: str | None = None
    current_chinese: str | None = None
    previous_english: str | None = None
    next_english: str | None = None
    difficulty: str | None = Field(default=None, pattern=r'^(A2|B1|B2|C1)$')


@app.middleware('http')
async def lan_guard(request: Request, call_next):
    if not settings.allow_lan:
        host = request.url.hostname or ''
        if host not in {'127.0.0.1', 'localhost', '::1', 'testserver'}:
            return JSONResponse({'detail': 'Only local access is allowed.'}, status_code=403)
    response = await call_next(request)
    response.headers['Cache-Control'] = 'no-store'
    return response


@app.get('/api/health')
def health() -> dict[str, Any]:
    return {
        'ready': True,
        'providers': pipeline.provider_map(),
        'allow_lan': settings.allow_lan,
        'livetalking_url': settings.livetalking_url,
        'stack': {
            'asr': 'WhisperX / Deepgram / mock',
            'pronunciation': 'wav2vec2 / phoneme / mock',
            'llm': 'openai / ollama / mock',
            'tts': 'xtts / fishspeech / edge / mock',
            'avatar': 'livetalking / musetalk / liveportrait / none',
        },
    }


@app.get('/api/providers')
def providers() -> dict[str, Any]:
    return {
        'active': pipeline.provider_map(),
        'options': {
            'asr': ['mock', 'whisperx', 'deepgram'],
            'pronunciation': ['mock', 'wav2vec2', 'phoneme'],
            'llm': ['mock', 'openai', 'ollama'],
            'tts': ['mock', 'xtts', 'fishspeech', 'edge'],
            'avatar': ['none', 'livetalking', 'musetalk', 'liveportrait'],
        },
    }


@app.post('/api/sessions', status_code=201)
def create_session(body: SessionCreate) -> dict[str, Any]:
    context = VideoContext(**body.model_dump())
    session = pipeline.create_session(context)
    return {
        'id': session.id,
        'difficulty': session.difficulty,
        'context': body.model_dump(),
        'providers': pipeline.provider_map(),
    }


@app.patch('/api/sessions/{sid}/context')
def patch_context(sid: str, body: ContextUpdate) -> dict[str, Any]:
    session = pipeline.get(sid)
    if not session:
        raise HTTPException(404, 'Session not found.')
    data = body.model_dump(exclude_unset=True)
    for key, value in data.items():
        if value is not None:
            setattr(session.context, key, value)
            if key == 'difficulty':
                session.difficulty = value
    return {
        'id': session.id,
        'difficulty': session.difficulty,
        'context': {
            'course_title': session.context.course_title,
            'episode_title': session.context.episode_title,
            'current_english': session.context.current_english,
            'current_chinese': session.context.current_chinese,
            'previous_english': session.context.previous_english,
            'next_english': session.context.next_english,
            'difficulty': session.context.difficulty,
        },
    }


async def _store_upload(sid: str, file: UploadFile) -> Path:
    suffix = Path(file.filename or 'turn.wav').suffix or '.wav'
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        while chunk := await file.read(1024 * 1024):
            tmp.write(chunk)
        tmp_path = Path(tmp.name)
    if tmp_path.stat().st_size == 0:
        raise HTTPException(422, 'Empty audio upload.')
    stored = pipeline.settings.data_dir / 'audio' / f'{sid}-{tmp_path.name}'
    stored.write_bytes(tmp_path.read_bytes())
    return stored


@app.post('/api/sessions/{sid}/draft')
async def create_draft(
    sid: str,
    file: UploadFile = File(...),
    reference_text: str | None = Form(default=None),
) -> dict[str, Any]:
    """ASR + pronunciation only. Confirm before LLM."""
    session = pipeline.get(sid)
    if not session:
        raise HTTPException(404, 'Session not found.')
    try:
        stored = await _store_upload(sid, file)
        draft = await pipeline.create_draft(
            session,
            str(stored),
            reference_override=reference_text,
        )
        return {
            'session_id': draft.session_id,
            'draft_id': draft.draft_id,
            'transcript': draft.transcript,
            'pronunciation': draft.pronunciation,
            'providers': draft.providers,
            'needs_confirm': True,
        }
    except HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(422, str(exc)) from None
    finally:
        await file.close()


class ConfirmBody(BaseModel):
    draft_id: str
    confirmed_text: str | None = None


@app.post('/api/sessions/{sid}/confirm')
async def confirm_draft(sid: str, body: ConfirmBody) -> dict[str, Any]:
    session = pipeline.get(sid)
    if not session:
        raise HTTPException(404, 'Session not found.')
    try:
        result = await pipeline.confirm_draft(
            session,
            body.draft_id,
            confirmed_text=body.confirmed_text,
        )
    except KeyError:
        raise HTTPException(404, 'Draft not found or already used.') from None
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(422, str(exc)) from None
    return {
        'session_id': result.session_id,
        'transcript': result.transcript,
        'pronunciation': result.pronunciation,
        'coach_text': result.coach_text,
        'corrections': result.corrections,
        'difficulty': result.difficulty,
        'tts_url': result.tts_url,
        'avatar': result.avatar,
        'providers': result.providers,
    }


@app.post('/api/sessions/{sid}/turn')
async def turn(
    sid: str,
    file: UploadFile = File(...),
    reference_text: str | None = Form(default=None),
    confirmed_text: str | None = Form(default=None),
) -> dict[str, Any]:
    """One-shot turn (auto-confirm). Prefer /draft + /confirm."""
    session = pipeline.get(sid)
    if not session:
        raise HTTPException(404, 'Session not found.')
    try:
        stored = await _store_upload(sid, file)
        result = await pipeline.run_turn(
            session,
            str(stored),
            reference_override=reference_text,
            confirmed_text=confirmed_text,
            skip_confirm=True,
        )
        return {
            'session_id': result.session_id,
            'transcript': result.transcript,
            'pronunciation': result.pronunciation,
            'coach_text': result.coach_text,
            'corrections': result.corrections,
            'difficulty': result.difficulty,
            'tts_url': result.tts_url,
            'avatar': result.avatar,
            'providers': result.providers,
        }
    except HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001 — surface provider setup errors to app
        raise HTTPException(422, str(exc)) from None
    finally:
        await file.close()


@app.get('/api/tts/{name}')
def get_tts(name: str):
    safe = Path(name).name
    path = settings.data_dir / 'tts' / safe
    if not path.is_file():
        raise HTTPException(404, 'TTS audio not found.')
    return FileResponse(path, media_type='audio/wav')


@app.get('/api/sessions/{sid}')
def get_session(sid: str) -> dict[str, Any]:
    session = pipeline.get(sid)
    if not session:
        raise HTTPException(404, 'Session not found.')
    return {
        'id': session.id,
        'difficulty': session.difficulty,
        'history': session.history,
        'context': {
            'course_title': session.context.course_title,
            'episode_title': session.context.episode_title,
            'current_english': session.context.current_english,
            'current_chinese': session.context.current_chinese,
            'previous_english': session.context.previous_english,
            'next_english': session.context.next_english,
            'difficulty': session.context.difficulty,
        },
    }
