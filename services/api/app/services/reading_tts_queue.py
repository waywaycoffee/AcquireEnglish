"""Durable ECS queue for reading-page TTS pregeneration (5060 Ti worker).

Jobs are keyed by (doc_id, voice, page_index). Sentence audio is content-
addressed under media/reading/tts/ (shared). Packs under media/reading/packs/
and media/reading/personal/{user_id}/ track readiness for shared / personal
libraries.
"""
from __future__ import annotations

from contextlib import contextmanager
import json
import re
import sqlite3
import time
import uuid
from pathlib import Path

from app.config import settings
from app.services import content_media as cm
from app.services import reading_speech_cache as rsc

_DOC_SAFE = re.compile(r"[^a-zA-Z0-9_\-]+")
MAX_SENTENCES = 120
MAX_SENTENCE_CHARS = 1800


def _db_path() -> Path:
    return Path(settings.media_cache_dir).expanduser() / "reading-tts-jobs.sqlite3"


@contextmanager
def connection():
    path = _db_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path, timeout=15)
    db.row_factory = sqlite3.Row
    db.execute(
        """CREATE TABLE IF NOT EXISTS jobs (
      id TEXT PRIMARY KEY,
      doc_id TEXT NOT NULL,
      voice TEXT NOT NULL,
      page_index INTEGER NOT NULL,
      state TEXT NOT NULL DEFAULT 'queued',
      attempts INTEGER NOT NULL DEFAULT 0,
      lease TEXT,
      deadline REAL,
      error TEXT,
      payload TEXT,
      requesters TEXT NOT NULL DEFAULT '[]',
      updated REAL NOT NULL,
      UNIQUE(doc_id, voice, page_index)
    )"""
    )
    try:
        with db:
            yield db
    finally:
        db.close()


def doc_segment(doc_id: str) -> str:
    cleaned = _DOC_SAFE.sub("-", (doc_id or "").strip().lower()).strip("-")
    return (cleaned or "doc")[:80]


def split_sentences(text: str) -> list[str]:
    raw = (text or "").replace("\r\n", "\n").strip()
    if not raw:
        return []
    parts = re.split(r"(?<=[.!?。！？])\s+", raw)
    out: list[str] = []
    for part in parts:
        sentence = rsc.normalize_speech_text(part)
        if not sentence:
            continue
        if len(sentence) > MAX_SENTENCE_CHARS:
            # Hard-cut oversized sentences so CosyVoice stays within limits.
            for i in range(0, len(sentence), MAX_SENTENCE_CHARS):
                chunk = sentence[i : i + MAX_SENTENCE_CHARS].strip()
                if chunk:
                    out.append(chunk)
        else:
            out.append(sentence)
        if len(out) >= MAX_SENTENCES:
            break
    return out


def _requesters(row) -> list[int]:
    try:
        values = json.loads(row["requesters"] or "[]")
    except (TypeError, json.JSONDecodeError, KeyError):
        return []
    out: list[int] = []
    for item in values if isinstance(values, list) else []:
        try:
            uid = int(item)
        except (TypeError, ValueError):
            continue
        if uid > 0 and uid not in out:
            out.append(uid)
    return out


def _add_requester(db, job_id: str, user_id: int | None) -> None:
    if not user_id or user_id <= 0:
        return
    row = db.execute("SELECT requesters FROM jobs WHERE id=?", (job_id,)).fetchone()
    if row is None:
        return
    users = _requesters(row)
    if user_id not in users:
        users.append(user_id)
        db.execute(
            "UPDATE jobs SET requesters=?, updated=? WHERE id=?",
            (json.dumps(users), time.time(), job_id),
        )


def public(row) -> dict:
    payload = {}
    try:
        payload = json.loads(row["payload"] or "{}")
    except (TypeError, json.JSONDecodeError):
        payload = {}
    sentences = payload.get("sentences") or []
    ready = 0
    for item in sentences if isinstance(sentences, list) else []:
        if isinstance(item, dict) and item.get("ready"):
            ready += 1
    total = len(sentences) if isinstance(sentences, list) else 0
    return {
        "id": row["id"],
        "doc_id": row["doc_id"],
        "voice": row["voice"],
        "page_index": int(row["page_index"]),
        "state": row["state"],
        "attempts": int(row["attempts"] or 0),
        "error": row["error"],
        "ready": ready,
        "total": total,
        "updated": row["updated"],
    }


def enqueue(
    *,
    doc_id: str,
    voice: str,
    page_index: int,
    text: str,
    user_id: int | None = None,
) -> dict:
    doc = (doc_id or "").strip()
    if not doc:
        raise ValueError("doc_id required")
    voice_id = (voice or "").strip() or "longanfengyue"
    page = int(page_index)
    if page < 0 or page > 9999:
        raise ValueError("invalid page_index")
    sentences = split_sentences(text)
    if not sentences:
        raise ValueError("empty page text")
    sentence_rows: list[dict] = []
    for s in sentences:
        hit = rsc.lookup_url(text=s, voice=voice_id, language="en")
        sentence_rows.append(
            {
                "text": s,
                "hash": (hit or {}).get("hash")
                or rsc.speech_hash(s, voice=voice_id, language="en"),
                "audio_url": (hit or {}).get("audio_url"),
                "ready": hit is not None,
            }
        )
    payload = {"sentences": sentence_rows}
    already = all(item["ready"] for item in sentence_rows)
    with connection() as db:
        db.execute("BEGIN IMMEDIATE")
        row = db.execute(
            "SELECT * FROM jobs WHERE doc_id=? AND voice=? AND page_index=?",
            (doc, voice_id, page),
        ).fetchone()
        now = time.time()
        if row is not None:
            if already:
                db.execute(
                    "UPDATE jobs SET state=?, payload=?, error=NULL, "
                    "lease=NULL, deadline=NULL, updated=? WHERE id=?",
                    ("done", json.dumps(payload), now, row["id"]),
                )
            elif row["state"] in ("failed", "done"):
                # Re-queue when cache was incomplete or user asks again.
                db.execute(
                    "UPDATE jobs SET state='queued', attempts=0, error=NULL, "
                    "lease=NULL, deadline=NULL, payload=?, updated=? WHERE id=?",
                    (json.dumps(payload), now, row["id"]),
                )
            else:
                db.execute(
                    "UPDATE jobs SET payload=?, updated=? WHERE id=?",
                    (json.dumps(payload), now, row["id"]),
                )
            _add_requester(db, row["id"], user_id)
            out = public(
                db.execute("SELECT * FROM jobs WHERE id=?", (row["id"],)).fetchone()
            )
            requesters = _requesters(
                db.execute("SELECT requesters FROM jobs WHERE id=?", (row["id"],)).fetchone()
            )
        else:
            job_id = uuid.uuid4().hex
            state = "done" if already else "queued"
            db.execute(
                "INSERT INTO jobs(id,doc_id,voice,page_index,state,payload,updated) "
                "VALUES(?,?,?,?,?,?,?)",
                (job_id, doc, voice_id, page, state, json.dumps(payload), now),
            )
            _add_requester(db, job_id, user_id)
            out = public(
                db.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
            )
            requesters = _requesters(
                db.execute(
                    "SELECT requesters FROM jobs WHERE id=?", (job_id,)
                ).fetchone()
            )
    if already:
        write_packs(
            doc_id=doc,
            voice=voice_id,
            page_index=page,
            payload=payload,
            user_ids=requesters,
        )
    return out


def status(job_id: str) -> dict | None:
    with connection() as db:
        row = db.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
        return public(row) if row else None


def _claim_row(db, row, *, lease_seconds: float) -> dict | None:
    if row is None:
        return None
    now = time.time()
    lease = uuid.uuid4().hex
    db.execute(
        "UPDATE jobs SET state='working', lease=?, deadline=?, "
        "attempts=attempts+1, updated=? WHERE id=?",
        (lease, now + lease_seconds, now, row["id"]),
    )
    fresh = db.execute("SELECT * FROM jobs WHERE id=?", (row["id"],)).fetchone()
    out = public(fresh)
    try:
        payload = json.loads(fresh["payload"] or "{}")
    except json.JSONDecodeError:
        payload = {}
    out["payload"] = payload
    out["lease"] = lease
    return out


def claim(lease_seconds: float = 300) -> dict | None:
    now = time.time()
    with connection() as db:
        db.execute("BEGIN IMMEDIATE")
        # Expire stale leases.
        db.execute(
            "UPDATE jobs SET state='queued', lease=NULL, deadline=NULL "
            "WHERE state='working' AND deadline IS NOT NULL AND deadline < ?",
            (now,),
        )
        row = db.execute(
            "SELECT * FROM jobs WHERE state='queued' "
            "ORDER BY updated ASC LIMIT 1"
        ).fetchone()
        return _claim_row(db, row, lease_seconds=lease_seconds)


def claim_id(job_id: str, lease_seconds: float = 600) -> dict | None:
    """Claim one specific job (ECS background filler)."""
    now = time.time()
    with connection() as db:
        db.execute("BEGIN IMMEDIATE")
        db.execute(
            "UPDATE jobs SET state='queued', lease=NULL, deadline=NULL "
            "WHERE state='working' AND deadline IS NOT NULL AND deadline < ?",
            (now,),
        )
        row = db.execute(
            "SELECT * FROM jobs WHERE id=? AND state IN ('queued','working')",
            (job_id,),
        ).fetchone()
        if row is None:
            return None
        if row["state"] == "working" and row["deadline"] and row["deadline"] > now:
            return None
        return _claim_row(db, row, lease_seconds=lease_seconds)


def heartbeat(job_id: str, lease: str, *, state: str = "working") -> bool:
    now = time.time()
    with connection() as db:
        cur = db.execute(
            "UPDATE jobs SET state=?, deadline=?, updated=? "
            "WHERE id=? AND lease=?",
            (state, now + 300, now, job_id, lease),
        )
        return cur.rowcount > 0


def complete(job_id: str, lease: str, *, payload: dict) -> dict:
    now = time.time()
    with connection() as db:
        row = db.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
        if row is None:
            raise ValueError("job not found")
        if row["lease"] and row["lease"] != lease:
            raise ValueError("lease mismatch")
        db.execute(
            "UPDATE jobs SET state='done', payload=?, error=NULL, "
            "lease=NULL, deadline=NULL, updated=? WHERE id=?",
            (json.dumps(payload), now, job_id),
        )
        requesters = _requesters(row)
        fresh = db.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
    write_packs(
        doc_id=fresh["doc_id"],
        voice=fresh["voice"],
        page_index=int(fresh["page_index"]),
        payload=payload,
        user_ids=requesters,
    )
    return public(fresh)


def fail(job_id: str, lease: str, error: str) -> dict:
    now = time.time()
    with connection() as db:
        row = db.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
        if row is None:
            raise ValueError("job not found")
        attempts = int(row["attempts"] or 0)
        state = "failed" if attempts >= 5 else "queued"
        db.execute(
            "UPDATE jobs SET state=?, error=?, lease=NULL, deadline=NULL, updated=? "
            "WHERE id=? AND (lease=? OR lease IS NULL)",
            (state, (error or "")[:500], now, job_id, lease),
        )
        return public(
            db.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
        )


def write_packs(
    *,
    doc_id: str,
    voice: str,
    page_index: int,
    payload: dict,
    user_ids: list[int],
) -> None:
    """Shared pack + personal pointers so next open can stream cached audio."""
    sentences = payload.get("sentences") if isinstance(payload, dict) else None
    if not isinstance(sentences, list):
        return
    pack = {
        "doc_id": doc_id,
        "voice": voice,
        "page_index": page_index,
        "sentences": sentences,
        "updated": time.time(),
    }
    shared_rel = (
        f"packs/{doc_segment(doc_id)}/{rsc.voice_segment(voice)}/page-{page_index}.json"
    )
    shared_path = cm.namespace_root("reading") / shared_rel
    shared_path.parent.mkdir(parents=True, exist_ok=True)
    shared_path.write_text(
        json.dumps(pack, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    for uid in user_ids:
        personal_rel = (
            f"personal/{uid}/packs/{doc_segment(doc_id)}/"
            f"{rsc.voice_segment(voice)}/page-{page_index}.json"
        )
        personal_path = cm.namespace_root("reading") / personal_rel
        personal_path.parent.mkdir(parents=True, exist_ok=True)
        personal_path.write_text(
            json.dumps(
                {
                    **pack,
                    "shared_relative": shared_rel,
                    "shared_audio_namespace": "reading",
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )


def load_shared_pack(*, doc_id: str, voice: str, page_index: int) -> dict | None:
    path = (
        cm.namespace_root("reading")
        / f"packs/{doc_segment(doc_id)}/{rsc.voice_segment(voice)}/page-{page_index}.json"
    )
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
