"""Durable ECS GPU queue. Worker access is through the existing SSH account.

Two job kinds share one row per (bvid, page):
- ``asr``: worker downloads Bilibili audio, runs Whisper, then EN→ZH.
- ``translate``: English already exists (official softsub / user upload); the
  worker only translates the stored cues to Chinese.
"""
from contextlib import contextmanager
import json
import re
import sqlite3
import time
import uuid
from pathlib import Path
from app.config import settings

MAX_TRANSLATE_CUES = 4000


@contextmanager
def connection():
    path=Path(settings.media_cache_dir).expanduser() / 'gpu-subtitle-jobs.sqlite3'
    path.parent.mkdir(parents=True,exist_ok=True)
    db=sqlite3.connect(path,timeout=15)
    db.row_factory=sqlite3.Row
    db.execute("""CREATE TABLE IF NOT EXISTS jobs (
      id TEXT PRIMARY KEY, bvid TEXT NOT NULL, page INTEGER NOT NULL,
      state TEXT NOT NULL DEFAULT 'queued', attempts INTEGER NOT NULL DEFAULT 0,
      lease TEXT, deadline REAL, error TEXT, updated REAL NOT NULL,
      UNIQUE(bvid,page))""")
    columns={row['name'] for row in db.execute('PRAGMA table_info(jobs)')}
    if 'kind' not in columns:
        db.execute("ALTER TABLE jobs ADD COLUMN kind TEXT NOT NULL DEFAULT 'asr'")
    if 'payload' not in columns:
        db.execute('ALTER TABLE jobs ADD COLUMN payload TEXT')
    if 'requesters' not in columns:
        db.execute("ALTER TABLE jobs ADD COLUMN requesters TEXT NOT NULL DEFAULT '[]'")
    try:
        with db:
            yield db
    finally:
        db.close()


def _check_identity(bvid, page):
    if not re.fullmatch(r'BV[0-9A-Za-z]{10}',bvid,re.I) or not 1<=page<=9999:
        raise ValueError('Invalid Bilibili identity')


def _requesters(row) -> list[int]:
    raw = row['requesters'] if 'requesters' in row.keys() else '[]'
    try:
        values = json.loads(raw or '[]')
    except json.JSONDecodeError:
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
    row = db.execute('SELECT requesters FROM jobs WHERE id=?', (job_id,)).fetchone()
    if row is None:
        return
    users = _requesters(row)
    if user_id not in users:
        users.append(user_id)
        db.execute(
            'UPDATE jobs SET requesters=?, updated=? WHERE id=?',
            (json.dumps(users), time.time(), job_id),
        )


def enqueue(bvid, page, *, user_id: int | None = None):
    _check_identity(bvid, page)
    with connection() as db:
        db.execute('BEGIN IMMEDIATE')
        row=db.execute('SELECT * FROM jobs WHERE upper(bvid)=upper(?) AND page=?',(bvid,page)).fetchone()
        if row is not None:
            # An English-only translate job cannot produce English; upgrade it.
            if row['kind']=='translate' and row['state'] in ('failed','retry'):
                db.execute("UPDATE jobs SET kind='asr',state='queued',attempts=0,error=NULL,updated=? WHERE id=?",
                  (time.time(),row['id']))
                row=db.execute('SELECT * FROM jobs WHERE id=?',(row['id'],)).fetchone()
            _add_requester(db, row['id'], user_id)
            return public(db.execute('SELECT * FROM jobs WHERE id=?', (row['id'],)).fetchone())
        job_id = uuid.uuid4().hex
        db.execute('INSERT OR IGNORE INTO jobs(id,bvid,page,updated) VALUES(?,?,?,?)',
          (job_id,bvid,page,time.time()))
        row=db.execute('SELECT * FROM jobs WHERE upper(bvid)=upper(?) AND page=?',(bvid,page)).fetchone()
        _add_requester(db, row['id'], user_id)
        return public(db.execute('SELECT * FROM jobs WHERE id=?', (row['id'],)).fetchone())


def parse_srt_cues(raw):
    """SRT text → [{start,end,text}] seconds; drops empty / malformed cues."""
    def seconds(stamp):
        h,m,rest=stamp.strip().replace('.',',').split(':')
        s,ms=(rest.split(',')+['0'])[:2]
        return int(h)*3600+int(m)*60+int(s)+int(ms.ljust(3,'0')[:3])/1000
    cues=[]
    for block in re.split(r'\r?\n\s*\r?\n',raw.strip()):
        lines=[l for l in block.splitlines() if l.strip()]
        arrow=next((i for i,l in enumerate(lines) if '-->' in l),None)
        if arrow is None: continue
        try:
            a,b=lines[arrow].split('-->')
            start,end=seconds(a),seconds(b.split()[0])
        except (ValueError,IndexError):
            continue
        text=' '.join(l.strip() for l in lines[arrow+1:]).strip()
        if text and end>start:
            cues.append({'start':start,'end':end,'text':text})
    return cues


def enqueue_translate(
    bvid,
    page,
    *,
    en_srt,
    title=None,
    cid=None,
    duration=None,
    user_id: int | None = None,
):
    """Queue EN→ZH for an episode whose English already exists."""
    _check_identity(bvid, page)
    cues=parse_srt_cues(en_srt or '')
    if len(cues)<2:
        raise ValueError('English subtitle has too few cues')
    if len(cues)>MAX_TRANSLATE_CUES:
        raise ValueError('English subtitle too long')
    payload=json.dumps({'cues':cues,'title':title,'cid':cid,'duration':duration},ensure_ascii=False)
    with connection() as db:
        db.execute('BEGIN IMMEDIATE')
        row=db.execute('SELECT * FROM jobs WHERE upper(bvid)=upper(?) AND page=?',(bvid,page)).fetchone()
        if row is None:
            job_id = uuid.uuid4().hex
            db.execute("INSERT INTO jobs(id,bvid,page,kind,payload,updated) VALUES(?,?,?,'translate',?,?)",
              (job_id,bvid,page,payload,time.time()))
        elif row['state']=='completed' or (row['kind']=='asr' and row['state'] not in ('failed',)):
            # Done already, or a full ASR run will produce both languages.
            _add_requester(db, row['id'], user_id)
            return public(db.execute('SELECT * FROM jobs WHERE id=?', (row['id'],)).fetchone())
        else:
            db.execute("UPDATE jobs SET kind='translate',payload=?,state='queued',attempts=0,error=NULL,updated=? WHERE id=?",
              (payload,time.time(),row['id']))
        row=db.execute('SELECT * FROM jobs WHERE upper(bvid)=upper(?) AND page=?',(bvid,page)).fetchone()
        _add_requester(db, row['id'], user_id)
        return public(db.execute('SELECT * FROM jobs WHERE id=?', (row['id'],)).fetchone())


def public(row):
    out={k:row[k] for k in ('id','bvid','page','state','attempts','error')}
    out['kind']=row['kind'] if 'kind' in row.keys() else 'asr'
    out['requesters']=_requesters(row)
    return out


def job_requesters(job_id: str) -> list[int]:
    with connection() as db:
        row = db.execute('SELECT * FROM jobs WHERE id=?', (job_id,)).fetchone()
        return _requesters(row) if row is not None else []


def claim():
    with connection() as db:
        db.execute('BEGIN IMMEDIATE')
        db.execute("UPDATE jobs SET state='failed',error='Retry limit reached' WHERE attempts>=4 AND (state='retry' OR (state IN ('transcribing','translating') AND deadline<?))",(time.time(),))
        # Translate-only jobs take seconds on the GPU; run them ahead of ASR.
        row=db.execute("""SELECT * FROM jobs WHERE
          (state IN ('queued','retry') OR (state IN ('transcribing','translating') AND deadline<?))
          AND attempts<4 ORDER BY (kind='translate') DESC, updated LIMIT 1""",(time.time(),)).fetchone()
        if row is None: return None
        lease=uuid.uuid4().hex
        state='translating' if row['kind']=='translate' else 'transcribing'
        db.execute("UPDATE jobs SET state=?, attempts=attempts+1,lease=?,deadline=?,updated=? WHERE id=?",
          (state,lease,time.time()+1200,time.time(),row['id']))
        return dict(db.execute('SELECT * FROM jobs WHERE id=?',(row['id'],)).fetchone())


def update(job, state, error=None):
    with connection() as db:
        result=db.execute('UPDATE jobs SET state=?,error=?,deadline=?,updated=? WHERE id=? AND lease=?',
          (state,error,time.time()+1200,time.time(),job['id'],job['lease']))
        if result.rowcount!=1: raise ValueError('Expired job lease')
