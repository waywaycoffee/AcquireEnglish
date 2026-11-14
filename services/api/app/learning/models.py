from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


@dataclass
class TaskDefinition:
    id: str
    title: str
    goal: str
    prompt: str
    difficulty: str = 'B1'
    # Optional video grounding
    course_title: str = ''
    current_english: str = ''


@dataclass
class PracticeSession:
    id: str
    task_id: str
    created_at: datetime
    status: str = 'active'  # active | feedback_ready | closed
    turns: list[dict] = field(default_factory=list)


@dataclass
class FeedbackItem:
    """Must cite a real user utterance (ChatterPal invariant)."""

    quote: str
    suggestion: str
    reason: str
    verified: bool = True


@dataclass
class ReviewItem:
    id: str
    expression: str
    source_quote: str
    due_at: datetime
    interval_days: int = 1
    status: str = 'pending'  # pending | done | skipped
