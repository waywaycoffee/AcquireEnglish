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
# Keep in sync with apps/mobile kReadingInteractivePageChars.
PAGE_CHARS = 1800
# Long-novel gate (word forms) — short articles skip book prep.
LONG_NOVEL_MIN_WORDS = 12000


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
    db.execute(
        """CREATE TABLE IF NOT EXISTS book_jobs (
      doc_id TEXT NOT NULL,
      voice TEXT NOT NULL,
      pages_total INTEGER NOT NULL,
      text_hash TEXT,
      state TEXT NOT NULL DEFAULT 'queued',
      error TEXT,
      updated REAL NOT NULL,
      PRIMARY KEY(doc_id, voice)
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


def split_reading_pages(text: str, max_chars: int = PAGE_CHARS) -> list[str]:
    """Mirror Flutter ``splitReadingPages`` so packs align with the reader."""
    trimmed = (text or "").replace("\r\n", "\n").strip()
    if not trimmed:
        return [""]
    if len(trimmed) <= max_chars:
        return [trimmed]
    by_heading = re.split(
        r"\n(?=(?:Chapter|CHAPTER|Part|PART|第[一二三四五六七八九十百零〇两\d]+[章节回幕])\b)",
        trimmed,
    )
    chunks: list[str] = []
    buf: list[str] = []

    def flush() -> None:
        piece = "\n\n".join(buf).strip() if buf else ""
        if piece:
            chunks.append(piece)
        buf.clear()

    def hard_cut(piece: str) -> None:
        start = 0
        while start < len(piece):
            end = min(start + max_chars, len(piece))
            if end < len(piece):
                para = piece.rfind("\n\n", start, end)
                sent = -1
                for i in range(end - 1, start + max_chars // 3, -1):
                    if piece[i] in ".!?。！？":
                        sent = i + 1
                        break
                cut = (
                    para
                    if para > start + max_chars // 3
                    else (sent if sent > start + max_chars // 3 else end)
                )
                end = cut
            chunk = piece[start:end].strip()
            if chunk:
                chunks.append(chunk)
            start = end
            while start < len(piece) and piece[start] in "\n ":
                start += 1

    def append_block(block: str) -> None:
        piece = (block or "").strip()
        if not piece:
            return
        if not buf:
            if len(piece) <= max_chars:
                buf.append(piece)
                return
            hard_cut(piece)
            return
        current = "\n\n".join(buf)
        if len(current) + 2 + len(piece) <= max_chars:
            buf.append(piece)
            return
        flush()
        if len(piece) <= max_chars:
            buf.append(piece)
            return
        hard_cut(piece)

    for block in by_heading:
        append_block(block)
    flush()
    return chunks or [trimmed]


def word_count(text: str) -> int:
    return len(re.findall(r"[A-Za-z]+(?:['’-][A-Za-z]+)*", text or ""))


def is_long_novel(text: str) -> bool:
    return word_count(text) >= LONG_NOVEL_MIN_WORDS


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


def requeue_stale_working(*, older_than_seconds: float = 120) -> int:
    """Return stuck ``working`` jobs to ``queued`` so drains can reclaim them.

    Detached CosyVoice drains often exit while a page is still leased; without
    this, ``claim_id`` keeps returning ``None`` and book progress freezes
    (commonly seen as 99% with one page left).
    """
    now = time.time()
    cutoff = now - max(30.0, float(older_than_seconds))
    with connection() as db:
        cur = db.execute(
            "UPDATE jobs SET state='queued', lease=NULL, deadline=NULL, updated=? "
            "WHERE state='working' AND ("
            "deadline IS NULL OR deadline < ? OR updated IS NULL OR updated < ?"
            ")",
            (now, now, cutoff),
        )
        return int(cur.rowcount or 0)


def claim(lease_seconds: float = 300) -> dict | None:
    now = time.time()
    with connection() as db:
        db.execute("BEGIN IMMEDIATE")
        # Expire stale leases (deadline) and abandoned workers (no heartbeat).
        db.execute(
            "UPDATE jobs SET state='queued', lease=NULL, deadline=NULL "
            "WHERE state='working' AND ("
            "deadline IS NULL OR deadline < ? OR updated IS NULL OR updated < ?"
            ")",
            (now, now - 120),
        )
        # Prefer emotional book-pair voices so long novels move first.
        row = db.execute(
            "SELECT * FROM jobs WHERE state='queued' "
            "ORDER BY CASE voice "
            "WHEN 'longanfengyue' THEN 0 "
            "WHEN 'longze_v3.1' THEN 1 "
            "ELSE 2 END, updated ASC LIMIT 1"
        ).fetchone()
        return _claim_row(db, row, lease_seconds=lease_seconds)


def claim_id(job_id: str, lease_seconds: float = 600) -> dict | None:
    """Claim one specific job (ECS background filler)."""
    now = time.time()
    with connection() as db:
        db.execute("BEGIN IMMEDIATE")
        db.execute(
            "UPDATE jobs SET state='queued', lease=NULL, deadline=NULL "
            "WHERE state='working' AND ("
            "deadline IS NULL OR deadline < ? OR updated IS NULL OR updated < ?"
            ")",
            (now, now - 120),
        )
        row = db.execute(
            "SELECT * FROM jobs WHERE id=? AND state IN ('queued','working')",
            (job_id,),
        ).fetchone()
        if row is None:
            return None
        if (
            row["state"] == "working"
            and row["deadline"]
            and row["deadline"] > now
            and row["updated"]
            and row["updated"] > now - 120
        ):
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


def _page_ready(*, doc_id: str, voice: str, page_index: int) -> bool:
    pack = load_shared_pack(doc_id=doc_id, voice=voice, page_index=page_index)
    if pack is None:
        return False
    sentences = pack.get("sentences") if isinstance(pack, dict) else None
    if not isinstance(sentences, list) or not sentences:
        return False
    return all(isinstance(s, dict) and s.get("ready") for s in sentences)


# Emotional book packs only — never queue a third CosyVoice for long novels.
BOOK_PACK_VOICES = frozenset({"longanfengyue", "longze_v3.1"})


def _find_ready_book_donor(
    *, text_hash: str, voice: str, exclude_doc: str = ""
) -> sqlite3.Row | None:
    """Another doc_id that already finished the same novel+voice packs."""
    digest = (text_hash or "").strip()
    voice_id = (voice or "").strip()
    if not digest or not voice_id:
        return None
    with connection() as db:
        row = db.execute(
            "SELECT doc_id, pages_total, text_hash FROM book_jobs "
            "WHERE text_hash=? AND voice=? AND state='ready' AND doc_id!=? "
            "ORDER BY updated DESC LIMIT 1",
            (digest, voice_id, (exclude_doc or "").strip()),
        ).fetchone()
    if row is None:
        return None
    pages_total = int(row["pages_total"] or 0)
    if pages_total <= 0:
        return None
    donor = str(row["doc_id"])
    # Require the shared pack files to actually exist.
    ready_pages = sum(
        1
        for idx in range(pages_total)
        if _page_ready(doc_id=donor, voice=voice_id, page_index=idx)
    )
    if ready_pages < pages_total:
        return None
    return row


def adopt_ready_book_packs(
    *,
    doc_id: str,
    voice: str,
    donor_doc_id: str,
    pages_total: int,
    text_hash: str,
) -> dict:
    """Copy finished packs under a new doc_id so shelf/status share one novel."""
    import shutil

    doc = (doc_id or "").strip()
    donor = (donor_doc_id or "").strip()
    voice_id = (voice or "").strip() or "longanfengyue"
    total = int(pages_total)
    if not doc or not donor or total <= 0:
        raise ValueError("adopt_ready_book_packs requires doc, donor, pages")
    src_dir = (
        cm.namespace_root("reading")
        / f"packs/{doc_segment(donor)}/{rsc.voice_segment(voice_id)}"
    )
    dst_dir = (
        cm.namespace_root("reading")
        / f"packs/{doc_segment(doc)}/{rsc.voice_segment(voice_id)}"
    )
    dst_dir.mkdir(parents=True, exist_ok=True)
    for idx in range(total):
        src = src_dir / f"page-{idx}.json"
        if not src.is_file():
            continue
        dst = dst_dir / f"page-{idx}.json"
        if dst.is_file():
            continue
        try:
            pack = json.loads(src.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            shutil.copy2(src, dst)
            continue
        if isinstance(pack, dict):
            pack = {**pack, "doc_id": doc, "adopted_from": donor}
            dst.write_text(
                json.dumps(pack, ensure_ascii=False, indent=2), encoding="utf-8"
            )
        else:
            shutil.copy2(src, dst)
    now = time.time()
    with connection() as db:
        db.execute(
            "INSERT INTO book_jobs(doc_id,voice,pages_total,text_hash,state,error,updated) "
            "VALUES(?,?,?,?,?,?,?) "
            "ON CONFLICT(doc_id,voice) DO UPDATE SET "
            "pages_total=excluded.pages_total, text_hash=excluded.text_hash, "
            "state='ready', error=NULL, updated=excluded.updated",
            (doc, voice_id, total, text_hash, "ready", None, now),
        )
    return book_status(doc_id=doc, voice=voice_id)


def enqueue_book(
    *,
    doc_id: str,
    voice: str,
    text: str,
    user_id: int | None = None,
) -> dict:
    """Split a long novel into pages and queue each for 5060 Ti / ECS TTS."""
    doc = (doc_id or "").strip()
    if not doc:
        raise ValueError("doc_id required")
    voice_id = (voice or "").strip() or "longanfengyue"
    if voice_id not in BOOK_PACK_VOICES:
        raise ValueError(
            f"book pregen voice must be one of {sorted(BOOK_PACK_VOICES)}, got {voice_id}"
        )
    pages = split_reading_pages(text)
    if not pages or (len(pages) == 1 and not pages[0].strip()):
        raise ValueError("empty book text")
    text_hash = rsc.speech_hash(text[:8000], voice=voice_id, language="en")

    # Same novel under another doc_id (catalog_* vs se:… / re-import) — reuse packs.
    donor = _find_ready_book_donor(
        text_hash=text_hash, voice=voice_id, exclude_doc=doc
    )
    if donor is not None:
        return adopt_ready_book_packs(
            doc_id=doc,
            voice=voice_id,
            donor_doc_id=str(donor["doc_id"]),
            pages_total=int(donor["pages_total"]),
            text_hash=text_hash,
        )

    # Already finished for this doc_id — do not reset to queued / re-upload.
    existing = book_status(doc_id=doc, voice=voice_id)
    if existing.get("ready") and int(existing.get("pages_total") or 0) >= len(pages):
        with connection() as db:
            db.execute(
                "INSERT INTO book_jobs(doc_id,voice,pages_total,text_hash,state,error,updated) "
                "VALUES(?,?,?,?,?,?,?) "
                "ON CONFLICT(doc_id,voice) DO UPDATE SET "
                "pages_total=excluded.pages_total, text_hash=excluded.text_hash, "
                "state='ready', error=NULL, updated=excluded.updated",
                (doc, voice_id, len(pages), text_hash, "ready", None, time.time()),
            )
        return {**existing, "text_hash": text_hash, "message": "already_ready"}

    job_ids: list[str] = []
    for index, page in enumerate(pages):
        job = enqueue(
            doc_id=doc,
            voice=voice_id,
            page_index=index,
            text=page,
            user_id=user_id,
        )
        job_ids.append(str(job.get("id") or ""))
    now = time.time()
    with connection() as db:
        db.execute(
            "INSERT INTO book_jobs(doc_id,voice,pages_total,text_hash,state,error,updated) "
            "VALUES(?,?,?,?,?,?,?) "
            "ON CONFLICT(doc_id,voice) DO UPDATE SET "
            "pages_total=excluded.pages_total, text_hash=excluded.text_hash, "
            "state=CASE WHEN book_jobs.state='ready' THEN 'ready' ELSE 'queued' END, "
            "error=NULL, updated=excluded.updated",
            (doc, voice_id, len(pages), text_hash, "queued", None, now),
        )
    return book_status(doc_id=doc, voice=voice_id)


def book_status(*, doc_id: str, voice: str) -> dict:
    doc = (doc_id or "").strip()
    voice_id = (voice or "").strip() or "longanfengyue"
    with connection() as db:
        book = db.execute(
            "SELECT * FROM book_jobs WHERE doc_id=? AND voice=?",
            (doc, voice_id),
        ).fetchone()
        page_rows = db.execute(
            "SELECT page_index, state FROM jobs WHERE doc_id=? AND voice=? "
            "ORDER BY page_index ASC",
            (doc, voice_id),
        ).fetchall()
    pages_total = int(book["pages_total"]) if book is not None else len(page_rows)
    if pages_total <= 0:
        pages_total = len(page_rows)
    ready = 0
    working = 0
    failed = 0
    queued = 0
    for row in page_rows:
        idx = int(row["page_index"])
        if _page_ready(doc_id=doc, voice=voice_id, page_index=idx) or row["state"] == "done":
            ready += 1
        elif row["state"] == "working":
            working += 1
        elif row["state"] == "failed":
            failed += 1
        else:
            queued += 1
    # Count pack files beyond job rows (re-opened books).
    if book is not None:
        for idx in range(pages_total):
            if _page_ready(doc_id=doc, voice=voice_id, page_index=idx):
                # already counted via jobs; ensure floor
                pass
        ready = sum(
            1
            for idx in range(pages_total)
            if _page_ready(doc_id=doc, voice=voice_id, page_index=idx)
        )
    percent = 0 if pages_total <= 0 else int(round(100.0 * ready / pages_total))
    is_ready = pages_total > 0 and ready >= pages_total
    if is_ready:
        state = "ready"
    elif failed and ready == 0 and working == 0 and queued == 0:
        state = "failed"
    elif working or queued:
        state = "working"
    elif book is None and pages_total == 0:
        state = "missing"
    else:
        state = "queued"
    if book is not None and is_ready and book["state"] != "ready":
        with connection() as db:
            db.execute(
                "UPDATE book_jobs SET state='ready', error=NULL, updated=? "
                "WHERE doc_id=? AND voice=?",
                (time.time(), doc, voice_id),
            )
    return {
        "doc_id": doc,
        "voice": voice_id,
        "pages_total": pages_total,
        "pages_ready": ready,
        "pages_working": working,
        "pages_queued": queued,
        "pages_failed": failed,
        "percent": percent,
        "ready": is_ready,
        "state": state,
        "error": (book["error"] if book is not None else None),
        # Jobs are claimed by tools/reading/tts_worker.py on the 5060 Ti when
        # that process is online; otherwise ECS drain_book_pregen_ecs fills.
        "processor": "shared-tts-queue",
        "long_novel": True,
    }


def unfinished_page_job_ids(*, doc_id: str, voice: str) -> list[str]:
    requeue_stale_working(older_than_seconds=120)
    doc = (doc_id or "").strip()
    voice_id = (voice or "").strip() or "longanfengyue"
    with connection() as db:
        rows = db.execute(
            "SELECT id, page_index, state FROM jobs WHERE doc_id=? AND voice=?",
            (doc, voice_id),
        ).fetchall()
    out: list[str] = []
    for row in rows:
        if row["state"] == "done" and _page_ready(
            doc_id=doc, voice=voice_id, page_index=int(row["page_index"])
        ):
            continue
        out.append(str(row["id"]))
    return out
