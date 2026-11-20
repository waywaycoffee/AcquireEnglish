from __future__ import annotations

import tempfile
from pathlib import Path
from typing import Any

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field

from .config import Settings
from .pipeline import CoachSession, OralCoachPipeline, TurnResult
from .providers.base import VideoContext

settings = Settings.from_env()
pipeline = OralCoachPipeline(settings)
app = FastAPI(title='AcquireEnglish Oral Coach', version='0.1.0')

_DIFFICULTY = r'^(A2|B1|B2|C1)$'


class SessionFields(BaseModel):
    course_title: str = ''
    episode_title: str = ''
    current_english: str = ''
    current_chinese: str = ''
    previous_english: str = ''
    next_english: str = ''
    topic_summary: str = ''
    article_excerpt: str = ''
    talk_topics: list[str] = Field(default_factory=list)
    difficulty: str = Field(default='B1', pattern=_DIFFICULTY)
    digital_human_id: str = 'mia'
    tts_voice: str = ''
    reply_language: str = 'en'
    scenario_task_id: str = ''
    scenario_title: str = ''
    scenario_goal: str = ''
    scenario_prompt: str = ''


class SessionCreate(SessionFields):
    pass


class ContextUpdate(BaseModel):
    course_title: str | None = None
    episode_title: str | None = None
    current_english: str | None = None
    current_chinese: str | None = None
    previous_english: str | None = None
    next_english: str | None = None
    topic_summary: str | None = None
    article_excerpt: str | None = None
    talk_topics: list[str] | None = None
    difficulty: str | None = Field(default=None, pattern=_DIFFICULTY)
    digital_human_id: str | None = None
    tts_voice: str | None = None
    reply_language: str | None = None
    scenario_task_id: str | None = None
    scenario_title: str | None = None
    scenario_goal: str | None = None
    scenario_prompt: str | None = None


class TopicsBody(BaseModel):
    count: int = Field(default=8, ge=4, le=12)
    force: bool = False
    article_excerpt: str | None = None
    topic_summary: str | None = None


class ConfirmBody(BaseModel):
    draft_id: str
    confirmed_text: str | None = None
    tts_voice: str | None = None
    digital_human_id: str | None = None
    reply_language: str | None = None
    text_only: bool = False


class SpeakBody(BaseModel):
    text: str = Field(min_length=1, max_length=4000)
    digital_human_id: str = 'mia'
    tts_voice: str = ''
    language: str = 'en'


def _require_session(sid: str) -> CoachSession:
    session = pipeline.get(sid)
    if not session:
        raise HTTPException(404, 'Session not found.')
    return session


def _session_payload(
    session: CoachSession,
    *,
    context: dict[str, Any] | None = None,
    include_history: bool = False,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        'id': session.id,
        'difficulty': session.difficulty,
        'digital_human_id': session.digital_human_id,
        'tts_voice': session.tts_voice,
        'reply_language': session.reply_language,
        'context': context if context is not None else session.context.as_public_dict(),
    }
    if include_history:
        payload['history'] = session.history
    return payload


def _turn_payload(result: TurnResult) -> dict[str, Any]:
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
        'livetalking_url': settings.livetalking_client_url,
        'livetalking_internal_url': settings.livetalking_url,
        'webrtc_ice_servers': settings.webrtc_ice_servers(),
        'stack': {
            'asr': 'WhisperX / Deepgram / mock',
            'pronunciation': 'simple / phoneme / http / wav2vec2',
            'llm': 'deepseek / openai / ollama / mock',
            'tts': 'edge / xtts / fishspeech / mock',
            'avatar': 'livetalking / musetalk / liveportrait / none',
        },
    }


@app.get('/api/providers')
def providers() -> dict[str, Any]:
    return {
        'active': pipeline.provider_map(),
        'options': {
            'asr': ['mock', 'whisperx', 'deepgram'],
            'pronunciation': ['simple', 'phoneme', 'http', 'wav2vec2', 'mock'],
            'llm': ['mock', 'openai', 'deepseek', 'ollama'],
            'tts': ['mock', 'xtts', 'fishspeech', 'edge'],
            'avatar': ['none', 'livetalking', 'musetalk', 'liveportrait'],
        },
    }


@app.post('/api/sessions', status_code=201)
def create_session(body: SessionCreate) -> dict[str, Any]:
    payload = body.model_dump()
    digital_human_id = str(payload.pop('digital_human_id', 'mia') or 'mia')
    tts_voice = str(payload.pop('tts_voice', '') or '')
    reply_language = str(payload.pop('reply_language', 'en') or 'en')
    session = pipeline.create_session(
        VideoContext(**payload),
        digital_human_id=digital_human_id,
        tts_voice=tts_voice,
        reply_language=reply_language,
    )
    return {
        **_session_payload(session, context=body.model_dump()),
        'providers': pipeline.provider_map(),
    }


@app.patch('/api/sessions/{sid}/context')
def patch_context(sid: str, body: ContextUpdate) -> dict[str, Any]:
    session = _require_session(sid)
    data = body.model_dump(exclude_unset=True)
    for key, value in data.items():
        if value is None:
            continue
        if key == 'digital_human_id':
            session.digital_human_id = str(value).strip().lower() or session.digital_human_id
        elif key == 'tts_voice':
            session.tts_voice = str(value).strip()
        elif key == 'reply_language':
            session.reply_language = str(value).strip().lower() or session.reply_language
        else:
            setattr(session.context, key, value)
            if key == 'difficulty':
                session.difficulty = value
    return _session_payload(session)


@app.post('/api/sessions/{sid}/topics')
async def generate_session_topics(sid: str, body: TopicsBody | None = None) -> dict[str, Any]:
    """Pre-read session transcript and generate oral Q&A topics."""
    session = _require_session(sid)
    payload = body or TopicsBody()
    if (payload.article_excerpt or '').strip():
        session.context.article_excerpt = payload.article_excerpt.strip()
    if (payload.topic_summary or '').strip():
        session.context.topic_summary = payload.topic_summary.strip()
    try:
        topics = await pipeline.ensure_talk_topics(
            session,
            count=payload.count,
            force=payload.force or not session.context.talk_topics,
        )
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(422, str(exc)) from None
    return {
        'session_id': session.id,
        'topics': topics,
        'count': len(topics),
        'topic_summary': session.context.topic_summary,
    }


@app.post('/api/sessions/{sid}/draft')
async def create_draft(
    sid: str,
    file: UploadFile = File(...),
    reference_text: str | None = Form(default=None),
) -> dict[str, Any]:
    """ASR + pronunciation only. Confirm before LLM."""
    session = _require_session(sid)
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


@app.post('/api/tts/speak')
async def speak_tts(body: SpeakBody) -> dict[str, Any]:
    """One-shot coach TTS with persona voice (greeting / local fallback)."""
    try:
        relative = await pipeline.synthesize_speech(
            body.text,
            digital_human_id=body.digital_human_id,
            tts_voice=body.tts_voice or None,
            language=body.language,
        )
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(422, str(exc)) from None
    if not relative:
        raise HTTPException(422, 'Empty speech text.')
    return {
        'tts_url': relative,
        'digital_human_id': (body.digital_human_id or 'mia').strip().lower(),
        'language': (body.language or 'en').strip().lower(),
    }


@app.post('/api/sessions/{sid}/confirm')
async def confirm_draft(sid: str, body: ConfirmBody) -> dict[str, Any]:
    session = _require_session(sid)
    try:
        result = await pipeline.confirm_draft(
            session,
            body.draft_id,
            confirmed_text=body.confirmed_text,
            tts_voice=body.tts_voice,
            digital_human_id=body.digital_human_id,
            reply_language=body.reply_language,
            text_only=body.text_only,
        )
    except KeyError:
        raise HTTPException(404, 'Draft not found or already used.') from None
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(422, str(exc)) from None
    return _turn_payload(result)


@app.post('/api/sessions/{sid}/turn')
async def turn(
    sid: str,
    file: UploadFile = File(...),
    reference_text: str | None = Form(default=None),
    confirmed_text: str | None = Form(default=None),
) -> dict[str, Any]:
    """One-shot turn (auto-confirm). Prefer /draft + /confirm."""
    session = _require_session(sid)
    try:
        stored = await _store_upload(sid, file)
        result = await pipeline.run_turn(
            session,
            str(stored),
            reference_override=reference_text,
            confirmed_text=confirmed_text,
            skip_confirm=True,
        )
        return _turn_payload(result)
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
    suffix = path.suffix.lower()
    media = 'audio/mpeg' if suffix in {'.mp3', '.mpeg'} else 'audio/wav'
    return FileResponse(path, media_type=media)


@app.get('/api/sessions/{sid}')
def get_session(sid: str) -> dict[str, Any]:
    session = _require_session(sid)
    return _session_payload(session, include_history=True)
