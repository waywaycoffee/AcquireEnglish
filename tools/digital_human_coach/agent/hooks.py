"""Bridge LiveKit turns → oral_coach providers + learning API."""

from __future__ import annotations

import json
import os
from typing import Any

import httpx

ORAL_COACH_URL = os.getenv(
    'ORAL_COACH_URL',
    'https://acquireenglish.curlhairai.com/coach',
).rstrip('/')
LEARNING_API_URL = os.getenv(
    'LEARNING_API_URL',
    'https://acquireenglish.curlhairai.com/api/learning',
).rstrip('/')
LEARNING_BEARER = os.getenv('LEARNING_API_BEARER', '').strip()


def _learning_headers(*, user_email: str = '') -> dict[str, str]:
    headers: dict[str, str] = {'Content-Type': 'application/json'}
    if LEARNING_BEARER:
        headers['Authorization'] = f'Bearer {LEARNING_BEARER}'
    email = (user_email or '').strip().lower()
    if email:
        headers['X-Acquire-User-Email'] = email
    return headers


async def score_pronunciation(
    *,
    transcript: str,
    reference_text: str,
    audio_path: str | None = None,
) -> dict[str, Any]:
    """Prefer oral_coach draft (audio) or /api/score/text; else overlap heuristic."""
    if audio_path:
        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                session = await client.post(
                    f'{ORAL_COACH_URL}/api/sessions',
                    json={
                        'current_english': reference_text,
                        'difficulty': os.getenv('ORAL_COACH_DIFFICULTY', 'B1'),
                    },
                )
                session.raise_for_status()
                sid = session.json()['id']
                with open(audio_path, 'rb') as fh:
                    draft = await client.post(
                        f'{ORAL_COACH_URL}/api/sessions/{sid}/draft',
                        files={'file': ('turn.wav', fh, 'audio/wav')},
                        data={'reference_text': reference_text},
                    )
                draft.raise_for_status()
                body = draft.json()
                return {
                    'transcript': body.get('transcript') or transcript,
                    'pronunciation': body.get('pronunciation') or {},
                    'providers': body.get('providers') or {},
                    'draft_id': body.get('draft_id'),
                    'session_id': sid,
                }
        except Exception as exc:  # noqa: BLE001
            return {
                'transcript': transcript,
                'pronunciation': {'error': str(exc)},
                'providers': {'fallback': 'error'},
            }

    # Text-only path: oral_coach simple scorer (no GPU).
    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            scored = await client.post(
                f'{ORAL_COACH_URL}/api/score/text',
                json={
                    'transcript': transcript,
                    'reference_text': reference_text,
                },
            )
            if scored.status_code < 400:
                body = scored.json()
                return {
                    'transcript': body.get('transcript') or transcript,
                    'pronunciation': body.get('pronunciation') or {},
                    'providers': body.get('providers')
                    or {'pronunciation': 'oral_coach_text'},
                }
    except Exception:  # noqa: BLE001
        pass

    words = [w for w in reference_text.lower().split() if w]
    hit = sum(1 for w in words if w in transcript.lower())
    overlap = (hit / len(words)) if words else 0.0
    return {
        'transcript': transcript,
        'pronunciation': {
            'overall': round(overlap, 3),
            'method': 'overlap_heuristic',
        },
        'providers': {'pronunciation': 'heuristic'},
    }


async def persist_learning_turn(
    *,
    learning_session_id: str | None,
    transcript: str,
    coach_text: str,
    pronunciation: dict[str, Any] | None = None,
    task_id: str = 'livekit-oral',
    user_email: str = '',
    course_title: str = '',
    current_english: str = '',
) -> str | None:
    """Append a turn to /api/learning; create a session when needed."""
    if not LEARNING_BEARER or not (user_email or '').strip():
        # Without service token + learner email, prod JWT endpoints reject us.
        return learning_session_id

    headers = _learning_headers(user_email=user_email)
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            sid = learning_session_id
            if not sid:
                created = await client.post(
                    f'{LEARNING_API_URL}/sessions',
                    headers=headers,
                    json={
                        'task_id': task_id,
                        'course_title': course_title,
                        'current_english': current_english,
                    },
                )
                if created.status_code >= 400:
                    return None
                sid = str(created.json().get('id') or '')
                if not sid:
                    return None
            if transcript.strip():
                await client.post(
                    f'{LEARNING_API_URL}/sessions/{sid}/turns',
                    headers=headers,
                    json={
                        'role': 'user',
                        'text': transcript,
                        'confirmed': True,
                        'scores': pronunciation or {},
                    },
                )
            if coach_text.strip():
                await client.post(
                    f'{LEARNING_API_URL}/sessions/{sid}/turns',
                    headers=headers,
                    json={
                        'role': 'assistant',
                        'text': coach_text,
                        'confirmed': True,
                        'scores': {},
                    },
                )
            return sid
    except Exception:  # noqa: BLE001
        return learning_session_id


def score_payload_bytes(score: dict[str, Any]) -> bytes:
    return json.dumps(
        {'topic': 'score.partial', **score},
        ensure_ascii=False,
    ).encode('utf-8')
