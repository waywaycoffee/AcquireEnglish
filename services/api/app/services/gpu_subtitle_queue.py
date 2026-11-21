"""Durable ECS GPU queue. Worker access is through the existing SSH account."""
from contextlib import contextmanager
import sqlite3
import time
import uuid
from pathlib import Path
from app.config import settings

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
    try:
        with db:
            yield db
    finally:
        db.close()

def enqueue(bvid, page):
    import re
    if not re.fullmatch(r'BV[0-9A-Za-z]{10}',bvid,re.I) or not 1<=page<=9999:
        raise ValueError('Invalid Bilibili identity')
    with connection() as db:
        db.execute('BEGIN IMMEDIATE')
        row=db.execute('SELECT * FROM jobs WHERE upper(bvid)=upper(?) AND page=?',(bvid,page)).fetchone()
        if row is not None:
            # Terminal failures used to stick forever: app re-scans treated the
            # existing row as "queued" while claim() permanently skipped them.
            if row['state'] == 'failed':
                db.execute(
                    "UPDATE jobs SET state='queued', attempts=0, error=NULL, "
                    "lease=NULL, deadline=NULL, updated=? WHERE id=?",
                    (time.time(), row['id']),
                )
                row = db.execute(
                    'SELECT * FROM jobs WHERE id=?', (row['id'],)
                ).fetchone()
            return public(row)
        db.execute('INSERT OR IGNORE INTO jobs(id,bvid,page,updated) VALUES(?,?,?,?)',
          (uuid.uuid4().hex,bvid,page,time.time()))
        row=db.execute('SELECT * FROM jobs WHERE upper(bvid)=upper(?) AND page=?',(bvid,page)).fetchone()
        return public(row)

def public(row):
    return {k:row[k] for k in ('id','bvid','page','state','attempts','error')}

def claim():
    with connection() as db:
        db.execute('BEGIN IMMEDIATE')
        db.execute("UPDATE jobs SET state='failed',error='Retry limit reached' WHERE attempts>=4 AND (state='retry' OR (state IN ('transcribing','translating') AND deadline<?))",(time.time(),))
        row=db.execute("""SELECT * FROM jobs WHERE
          (state IN ('queued','retry') OR (state IN ('transcribing','translating') AND deadline<?))
          AND attempts<4 ORDER BY updated LIMIT 1""",(time.time(),)).fetchone()
        if row is None: return None
        lease=uuid.uuid4().hex
        db.execute("UPDATE jobs SET state='transcribing', attempts=attempts+1,lease=?,deadline=?,updated=? WHERE id=?",
          (lease,time.time()+1200,time.time(),row['id']))
        return dict(db.execute('SELECT * FROM jobs WHERE id=?',(row['id'],)).fetchone())

def update(job, state, error=None):
    with connection() as db:
        result=db.execute('UPDATE jobs SET state=?,error=?,deadline=?,updated=? WHERE id=? AND lease=?',
          (state,error,time.time()+1200,time.time(),job['id'],job['lease']))
        if result.rowcount!=1: raise ValueError('Expired job lease')
