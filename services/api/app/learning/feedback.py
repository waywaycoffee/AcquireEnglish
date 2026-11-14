from __future__ import annotations

from .models import FeedbackItem


def validate_feedback_items(
    candidates: list[FeedbackItem],
    user_utterances: list[str],
    *,
    max_items: int = 2,
) -> list[FeedbackItem]:
    """Keep at most max_items feedback rows that cite a real user substring.

    ChatterPal invariant: every improvement must quote something the learner said.
    """
    out: list[FeedbackItem] = []
    for item in candidates:
        quote = (item.quote or '').strip()
        suggestion = (item.suggestion or '').strip()
        if not quote or not suggestion or quote == suggestion:
            continue
        if not any(quote in (u or '') for u in user_utterances):
            continue
        out.append(
            FeedbackItem(
                quote=quote,
                suggestion=suggestion,
                reason=(item.reason or '').strip(),
                verified=True,
            )
        )
        if len(out) >= max_items:
            break
    return out
