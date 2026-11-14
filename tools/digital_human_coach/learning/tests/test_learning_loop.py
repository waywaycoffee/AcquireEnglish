import tempfile
from pathlib import Path

from learning.feedback import validate_feedback_items
from learning.models import FeedbackItem
from learning.store import LearningStore


def test_feedback_must_cite_user_quote():
    items = validate_feedback_items(
        [
            FeedbackItem(quote='I go hiking', suggestion='I went hiking', reason='past tense'),
            FeedbackItem(quote='not said', suggestion='x', reason='x'),
            FeedbackItem(quote='friends', suggestion='friends', reason='same'),
        ],
        ['I go hiking with friends'],
    )
    assert len(items) == 1
    assert items[0].suggestion == 'I went hiking'


def test_session_wrong_items_and_review(tmp_path: Path):
    store = LearningStore(tmp_path / 't.db')
    session = store.start_session('weekend')
    store.append_turn(session.id, role='user', text='I go hiking with friends', confirmed=True)
    store.append_turn(session.id, role='assistant', text='Nice! When was that?', confirmed=True)
    verified = store.finalize_feedback(
        session.id,
        [
            FeedbackItem(
                quote='I go hiking',
                suggestion='I went hiking',
                reason='Use past tense for last weekend.',
            )
        ],
    )
    assert len(verified) == 1
    wrong = store.list_wrong_items()
    assert wrong[0]['quote'] == 'I go hiking'

    review = store.save_expression_for_review('I went hiking with friends', 'I go hiking')
    assert review.interval_days == 1
    # Force due
    import sqlite3

    with sqlite3.connect(store.path) as conn:
        conn.execute("UPDATE reviews SET due_at='2000-01-01T00:00:00+00:00'")
    due = store.due_reviews()
    assert len(due) == 1
    store.complete_review(due[0].id, independent_ok=True)
    # next interval 3 days, not immediately due
    assert store.due_reviews() == []
