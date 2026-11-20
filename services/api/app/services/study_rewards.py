"""Bounded server-wall-clock accounting and idempotent check-in rewards."""
from datetime import datetime, timedelta, timezone
import json
import re
from sqlalchemy import select, update, func
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.dialects.postgresql import insert as postgres_insert
from app.models import (StudyActivityClock, StudyRewardDay, StudyReviewEvidence,
                        UserReviewPoints, ReviewPointsLedger)


def now():
    return datetime.now(timezone.utc)


def aware(dt):
    return dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt


def day_key(dt=None):
    return ((dt or now()) + timedelta(hours=8)).date().isoformat()


def insert(db, model):
    return (sqlite_insert if db.bind.dialect.name == 'sqlite' else postgres_insert)(model)


async def ensure_day(db, uid):
    await db.execute(insert(db, StudyRewardDay).values(user_id=uid, day=day_key(), seconds=0, review_target=5, target_locked=0).on_conflict_do_nothing())


async def grant_points(db, uid, event, delta, reason):
    added = (await db.execute(insert(db, ReviewPointsLedger).values(
        user_id=uid, client_event_id=event, delta=delta, reason=reason, meta_json='{}'
    ).on_conflict_do_nothing().returning(ReviewPointsLedger.id))).scalar_one_or_none()
    if added is None:
        return False
    await db.execute(insert(db, UserReviewPoints).values(user_id=uid, balance=0).on_conflict_do_nothing())
    await db.execute(update(UserReviewPoints).where(UserReviewPoints.user_id == uid).values(balance=UserReviewPoints.balance + delta))
    return True


async def record_review_evidence(db, uid, state, previous_payload=None):
    clock = await db.get(StudyActivityClock, uid)
    if clock is None or now() - aware(clock.last_tick) > timedelta(minutes=5):
        return
    records = state.get('records', [])
    valid = []
    for row in records:
        try:
            key = row['key']
            reviewed = aware(datetime.fromisoformat(row['card']['lastReview'].replace('Z', '+00:00')))
            if isinstance(key, str) and re.match(r'^(word|phrase|recommended|syllabus):', key) and 1 <= len(key) <= 240 and int(row['reviews']) > 0 and aware(clock.first_seen) - timedelta(seconds=5) <= reviewed <= now() + timedelta(seconds=5) and now() - reviewed <= timedelta(minutes=5):
                valid.append({'user_id': uid, 'day': day_key(), 'card_key': key})
        except (KeyError, ValueError, TypeError, AttributeError):
            continue
    if not valid:
        return
    await ensure_day(db, uid)
    try:
        prior = json.loads(previous_payload or '{}')
        due = 0
        fresh = 0
        for r in prior.get('records', []):
            if r.get('firstLearnedAt') is None:
                fresh += 1
            elif aware(datetime.fromisoformat(r['card']['due'].replace('Z', '+00:00'))) <= now():
                due += 1
        target = min(5, max(1, due + min(fresh, int(prior.get('dailyNewLimit', 5))))) if prior.get('records') else min(5, max(1, len(records)))
    except (ValueError, TypeError, KeyError, AttributeError):
        target = 5
    await db.execute(update(StudyRewardDay).where(StudyRewardDay.user_id == uid, StudyRewardDay.day == day_key(), StudyRewardDay.target_locked == 0).values(review_target=target, target_locked=1))
    await db.execute(insert(db, StudyReviewEvidence).values(valid).on_conflict_do_nothing())
