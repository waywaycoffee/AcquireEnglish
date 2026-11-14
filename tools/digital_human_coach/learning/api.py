"""Thin FastAPI for learning loop (can run beside LiveKit agent)."""

from __future__ import annotations

import os
from pathlib import Path

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from .models import FeedbackItem
from .store import LearningStore

DB = Path(
    os.getenv('LEARNING_DB_PATH', '~/.local/share/acquire-dh-coach/learning.db')
).expanduser()
store = LearningStore(DB)
app = FastAPI(title='Acquire Digital Human Learning', version='0.1.0')


class StartIn(BaseModel):
    task_id: str
    course_title: str = ''
    current_english: str = ''


class TurnIn(BaseModel):
    role: str = Field(pattern='^(user|assistant)$')
    text: str
    machine_transcript: str | None = None
    confirmed: bool = True
    scores: dict = Field(default_factory=dict)


class FeedbackIn(BaseModel):
    items: list[dict]


class ReviewSaveIn(BaseModel):
    expression: str
    source_quote: str


class ReviewCompleteIn(BaseModel):
    independent_ok: bool = True


@app.get('/health')
def health() -> dict:
    return {'status': 'ok', 'db': str(DB)}


@app.get('/tasks')
def tasks() -> list[dict]:
    return [t.__dict__ for t in store.list_tasks()]


@app.post('/sessions')
def start(body: StartIn) -> dict:
    try:
        session = store.start_session(
            body.task_id,
            course_title=body.course_title,
            current_english=body.current_english,
        )
    except KeyError as exc:
        raise HTTPException(404, str(exc)) from exc
    return {
        'id': session.id,
        'task_id': session.task_id,
        'status': session.status,
        'created_at': session.created_at.isoformat(),
    }


@app.post('/sessions/{session_id}/turns')
def turn(session_id: str, body: TurnIn) -> dict:
    try:
        store.append_turn(
            session_id,
            role=body.role,
            text=body.text,
            machine_transcript=body.machine_transcript,
            confirmed=body.confirmed,
            scores=body.scores,
        )
    except KeyError:
        raise HTTPException(404, 'session not found') from None
    except RuntimeError as exc:
        raise HTTPException(409, str(exc)) from exc
    return {'ok': True}


@app.post('/sessions/{session_id}/feedback')
def feedback(session_id: str, body: FeedbackIn) -> dict:
    candidates = [
        FeedbackItem(
            quote=str(i.get('quote', '')),
            suggestion=str(i.get('suggestion', '')),
            reason=str(i.get('reason', '')),
        )
        for i in body.items
    ]
    try:
        verified = store.finalize_feedback(session_id, candidates)
    except KeyError:
        raise HTTPException(404, 'session not found') from None
    return {
        'items': [i.__dict__ for i in verified],
        'count': len(verified),
    }


@app.get('/wrong-items')
def wrong_items() -> list[dict]:
    return store.list_wrong_items()


@app.post('/reviews')
def save_review(body: ReviewSaveIn) -> dict:
    item = store.save_expression_for_review(body.expression, body.source_quote)
    return {
        'id': item.id,
        'due_at': item.due_at.isoformat(),
        'interval_days': item.interval_days,
    }


@app.get('/reviews/due')
def due() -> list[dict]:
    return [
        {
            'id': r.id,
            'expression': r.expression,
            'source_quote': r.source_quote,
            'due_at': r.due_at.isoformat(),
            'interval_days': r.interval_days,
        }
        for r in store.due_reviews()
    ]


@app.post('/reviews/{review_id}/complete')
def complete(review_id: str, body: ReviewCompleteIn) -> dict:
    try:
        store.complete_review(review_id, independent_ok=body.independent_ok)
    except KeyError:
        raise HTTPException(404, 'review not found') from None
    return {'ok': True}
