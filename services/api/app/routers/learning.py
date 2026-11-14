"""ChatterPal-style learning loop mounted on the main API (JWT required)."""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.config import settings
from app.deps import get_current_user
from app.learning import FeedbackItem, LearningStore
from app.models import User

router = APIRouter(prefix="/learning", tags=["learning"])

_store: LearningStore | None = None


def _db_path() -> Path:
    raw = settings.database_url
    if "sqlite" in raw and ":///" in raw:
        file_part = raw.split(":///", 1)[1]
        if file_part and not file_part.startswith(":memory:"):
            return Path(file_part).expanduser().resolve().parent / "learning.db"
    return Path("~/.local/share/acquire-english/learning.db").expanduser()


def get_store() -> LearningStore:
    global _store
    if _store is None:
        _store = LearningStore(_db_path())
    return _store


class StartIn(BaseModel):
    task_id: str = "video_line"
    course_title: str = ""
    current_english: str = ""


class TurnIn(BaseModel):
    role: str = Field(pattern="^(user|assistant)$")
    text: str
    machine_transcript: str | None = None
    confirmed: bool = True
    scores: dict = Field(default_factory=dict)


class FeedbackIn(BaseModel):
    items: list[dict] = Field(default_factory=list)


class ReviewSaveIn(BaseModel):
    expression: str
    source_quote: str


class ReviewCompleteIn(BaseModel):
    independent_ok: bool = True


@router.get("/tasks")
async def tasks(_: User = Depends(get_current_user)) -> list[dict]:
    return [t.__dict__ for t in get_store().list_tasks()]


@router.post("/sessions")
async def start_session(body: StartIn, _: User = Depends(get_current_user)) -> dict:
    try:
        session = get_store().start_session(
            body.task_id,
            course_title=body.course_title,
            current_english=body.current_english,
        )
    except KeyError as exc:
        raise HTTPException(404, str(exc)) from exc
    return {
        "id": session.id,
        "task_id": session.task_id,
        "status": session.status,
        "created_at": session.created_at.isoformat(),
    }


@router.post("/sessions/{session_id}/turns")
async def append_turn(
    session_id: str,
    body: TurnIn,
    _: User = Depends(get_current_user),
) -> dict:
    try:
        get_store().append_turn(
            session_id,
            role=body.role,
            text=body.text,
            machine_transcript=body.machine_transcript,
            confirmed=body.confirmed,
            scores=body.scores,
        )
    except KeyError:
        raise HTTPException(404, "session not found") from None
    except RuntimeError as exc:
        raise HTTPException(409, str(exc)) from exc
    return {"ok": True}


@router.post("/sessions/{session_id}/feedback")
async def finalize_feedback(
    session_id: str,
    body: FeedbackIn,
    _: User = Depends(get_current_user),
) -> dict:
    candidates = [
        FeedbackItem(
            quote=str(i.get("quote", "")),
            suggestion=str(i.get("suggestion", "")),
            reason=str(i.get("reason", "")),
        )
        for i in body.items
    ]
    try:
        verified = get_store().finalize_feedback(session_id, candidates)
    except KeyError:
        raise HTTPException(404, "session not found") from None
    return {"items": [i.__dict__ for i in verified], "count": len(verified)}


@router.get("/wrong-items")
async def wrong_items(_: User = Depends(get_current_user)) -> list[dict]:
    return get_store().list_wrong_items()


@router.post("/reviews")
async def save_review(body: ReviewSaveIn, _: User = Depends(get_current_user)) -> dict:
    item = get_store().save_expression_for_review(body.expression, body.source_quote)
    return {
        "id": item.id,
        "due_at": item.due_at.isoformat(),
        "interval_days": item.interval_days,
    }


@router.get("/reviews/due")
async def due_reviews(_: User = Depends(get_current_user)) -> list[dict]:
    return [
        {
            "id": r.id,
            "expression": r.expression,
            "source_quote": r.source_quote,
            "due_at": r.due_at.isoformat(),
            "interval_days": r.interval_days,
        }
        for r in get_store().due_reviews()
    ]


@router.post("/reviews/{review_id}/complete")
async def complete_review(
    review_id: str,
    body: ReviewCompleteIn,
    _: User = Depends(get_current_user),
) -> dict:
    try:
        get_store().complete_review(review_id, independent_ok=body.independent_ok)
    except KeyError:
        raise HTTPException(404, "review not found") from None
    return {"ok": True}
