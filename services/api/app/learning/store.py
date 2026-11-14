from __future__ import annotations

import json
import sqlite3
import uuid
from datetime import datetime, timedelta
from pathlib import Path

from .feedback import validate_feedback_items
from .models import FeedbackItem, PracticeSession, ReviewItem, TaskDefinition, utcnow


def _parse_dt(value: str) -> datetime:
    return datetime.fromisoformat(value)

# Built-in seeds (ChatterPal-style scenarios + video-grounded template).
SEED_TASKS: list[TaskDefinition] = [
    TaskDefinition(
        id='weekend',
        title='描述周末',
        goal='说清过去的活动、同行的人以及自己的感受或原因',
        prompt='Tell me about your last weekend. What did you do, who with, and how did you feel?',
        difficulty='A2',
    ),
    TaskDefinition(
        id='restaurant',
        title='在餐厅点餐',
        goal='说明餐点和数量、饮品，再提出一个要求或问题',
        prompt='You are at a cafe. Order food and a drink, then ask one question.',
        difficulty='A2',
    ),
    TaskDefinition(
        id='hotel',
        title='办理酒店入住',
        goal='说明已有预订、提供必要信息，再询问一项住宿信息',
        prompt='Check in at a hotel. Mention your reservation and ask one question about the stay.',
        difficulty='B1',
    ),
    TaskDefinition(
        id='video_line',
        title='视频当前句对话',
        goal='围绕视频当前英文字幕自然多说几句，并回应外教追问',
        prompt='Talk about the current video line. Paraphrase it, then answer follow-ups.',
        difficulty='B1',
    ),
]


class LearningStore:
    def __init__(self, db_path: str | Path):
        self.path = Path(db_path).expanduser().resolve()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_db(self) -> None:
        with self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS tasks (
                  id TEXT PRIMARY KEY,
                  title TEXT NOT NULL,
                  goal TEXT NOT NULL,
                  prompt TEXT NOT NULL,
                  difficulty TEXT NOT NULL,
                  course_title TEXT,
                  current_english TEXT
                );
                CREATE TABLE IF NOT EXISTS sessions (
                  id TEXT PRIMARY KEY,
                  task_id TEXT NOT NULL,
                  status TEXT NOT NULL,
                  created_at TEXT NOT NULL,
                  turns_json TEXT NOT NULL DEFAULT '[]',
                  feedback_json TEXT,
                  user_id INTEGER,
                  context_json TEXT
                );
                CREATE TABLE IF NOT EXISTS wrong_items (
                  id TEXT PRIMARY KEY,
                  session_id TEXT NOT NULL,
                  quote TEXT NOT NULL,
                  suggestion TEXT NOT NULL,
                  reason TEXT NOT NULL,
                  created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS reviews (
                  id TEXT PRIMARY KEY,
                  expression TEXT NOT NULL,
                  source_quote TEXT NOT NULL,
                  due_at TEXT NOT NULL,
                  interval_days INTEGER NOT NULL,
                  status TEXT NOT NULL
                );
                """
            )
            existing = {
                row['id'] for row in conn.execute('SELECT id FROM tasks').fetchall()
            }
            for task in SEED_TASKS:
                if task.id in existing:
                    continue
                conn.execute(
                    'INSERT INTO tasks(id,title,goal,prompt,difficulty,course_title,current_english) '
                    'VALUES(?,?,?,?,?,?,?)',
                    (
                        task.id,
                        task.title,
                        task.goal,
                        task.prompt,
                        task.difficulty,
                        task.course_title,
                        task.current_english,
                    ),
                )
            cols = {
                row['name']
                for row in conn.execute('PRAGMA table_info(sessions)').fetchall()
            }
            if 'user_id' not in cols:
                conn.execute('ALTER TABLE sessions ADD COLUMN user_id INTEGER')
            if 'context_json' not in cols:
                conn.execute('ALTER TABLE sessions ADD COLUMN context_json TEXT')

    def list_tasks(self) -> list[TaskDefinition]:
        with self._connect() as conn:
            rows = conn.execute('SELECT * FROM tasks ORDER BY id').fetchall()
        return [
            TaskDefinition(
                id=r['id'],
                title=r['title'],
                goal=r['goal'],
                prompt=r['prompt'],
                difficulty=r['difficulty'],
                course_title=r['course_title'] or '',
                current_english=r['current_english'] or '',
            )
            for r in rows
        ]

    def start_session(
        self,
        task_id: str,
        *,
        user_id: int,
        course_title: str = '',
        current_english: str = '',
    ) -> PracticeSession:
        tasks = {t.id: t for t in self.list_tasks()}
        if task_id not in tasks:
            raise KeyError(f'unknown task: {task_id}')
        sid = uuid.uuid4().hex
        now = utcnow()
        # Keep video line context on the session — never mutate the shared seed task.
        context = json.dumps(
            {
                'course_title': course_title or '',
                'current_english': current_english or '',
            },
            ensure_ascii=False,
        )
        with self._connect() as conn:
            conn.execute(
                'INSERT INTO sessions(id,task_id,status,created_at,turns_json,user_id,context_json) '
                'VALUES(?,?,?,?,?,?,?)',
                (sid, task_id, 'active', now.isoformat(), '[]', user_id, context),
            )
        return PracticeSession(id=sid, task_id=task_id, created_at=now)

    def _require_session(self, conn: sqlite3.Connection, session_id: str, user_id: int):
        row = conn.execute(
            'SELECT * FROM sessions WHERE id=?', (session_id,)
        ).fetchone()
        if row is None:
            raise KeyError(session_id)
        owner = row['user_id']
        if owner is not None and int(owner) != int(user_id):
            raise KeyError(session_id)
        return row

    def append_turn(
        self,
        session_id: str,
        *,
        user_id: int,
        role: str,
        text: str,
        machine_transcript: str | None = None,
        confirmed: bool = True,
        scores: dict | None = None,
    ) -> None:
        with self._connect() as conn:
            row = self._require_session(conn, session_id, user_id)
            if row['status'] == 'closed':
                raise RuntimeError('session closed')
            turns = json.loads(row['turns_json'])
            turns.append(
                {
                    'role': role,
                    'text': text,
                    'machine_transcript': machine_transcript,
                    'confirmed': confirmed,
                    'scores': scores or {},
                    'at': utcnow().isoformat(),
                }
            )
            conn.execute(
                'UPDATE sessions SET turns_json=? WHERE id=?',
                (json.dumps(turns, ensure_ascii=False), session_id),
            )

    def finalize_feedback(
        self,
        session_id: str,
        candidates: list[FeedbackItem],
        *,
        user_id: int,
    ) -> list[FeedbackItem]:
        with self._connect() as conn:
            row = self._require_session(conn, session_id, user_id)
            turns = json.loads(row['turns_json'])
        user_texts = [
            t['text']
            for t in turns
            if t.get('role') == 'user' and t.get('confirmed') and t.get('text')
        ]
        verified = validate_feedback_items(candidates, user_texts)
        with self._connect() as conn:
            conn.execute(
                'UPDATE sessions SET status=?, feedback_json=? WHERE id=?',
                (
                    'feedback_ready',
                    json.dumps(
                        [
                            {
                                'quote': i.quote,
                                'suggestion': i.suggestion,
                                'reason': i.reason,
                                'verified': i.verified,
                            }
                            for i in verified
                        ],
                        ensure_ascii=False,
                    ),
                    session_id,
                ),
            )
            for item in verified:
                wid = uuid.uuid4().hex
                conn.execute(
                    'INSERT INTO wrong_items(id,session_id,quote,suggestion,reason,created_at) '
                    'VALUES(?,?,?,?,?,?)',
                    (
                        wid,
                        session_id,
                        item.quote,
                        item.suggestion,
                        item.reason,
                        utcnow().isoformat(),
                    ),
                )
        return verified

    def save_expression_for_review(self, expression: str, source_quote: str) -> ReviewItem:
        rid = uuid.uuid4().hex
        due = utcnow() + timedelta(days=1)
        item = ReviewItem(
            id=rid,
            expression=expression.strip(),
            source_quote=source_quote.strip(),
            due_at=due,
            interval_days=1,
        )
        with self._connect() as conn:
            conn.execute(
                'INSERT INTO reviews(id,expression,source_quote,due_at,interval_days,status) '
                'VALUES(?,?,?,?,?,?)',
                (
                    item.id,
                    item.expression,
                    item.source_quote,
                    item.due_at.isoformat(),
                    item.interval_days,
                    item.status,
                ),
            )
        return item

    def due_reviews(self) -> list[ReviewItem]:
        now = utcnow().isoformat()
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM reviews WHERE status='pending' AND due_at<=? ORDER BY due_at",
                (now,),
            ).fetchall()
        return [
            ReviewItem(
                id=r['id'],
                expression=r['expression'],
                source_quote=r['source_quote'],
                due_at=_parse_dt(r['due_at']),
                interval_days=r['interval_days'],
                status=r['status'],
            )
            for r in rows
        ]

    def complete_review(self, review_id: str, *, independent_ok: bool) -> None:
        """On independent success: 1d → 3d → 7d. Otherwise keep pending with +1d."""
        with self._connect() as conn:
            row = conn.execute(
                'SELECT interval_days FROM reviews WHERE id=?', (review_id,)
            ).fetchone()
            if row is None:
                raise KeyError(review_id)
            interval = int(row['interval_days'])
            if independent_ok:
                nxt = 3 if interval <= 1 else 7 if interval <= 3 else 7
                due = utcnow() + timedelta(days=nxt)
                conn.execute(
                    "UPDATE reviews SET interval_days=?, due_at=?, status='pending' WHERE id=?",
                    (nxt, due.isoformat(), review_id),
                )
            else:
                due = utcnow() + timedelta(days=1)
                conn.execute(
                    "UPDATE reviews SET due_at=?, status='pending' WHERE id=?",
                    (due.isoformat(), review_id),
                )

    def list_wrong_items(self, limit: int = 50) -> list[dict]:
        with self._connect() as conn:
            rows = conn.execute(
                'SELECT * FROM wrong_items ORDER BY created_at DESC LIMIT ?', (limit,)
            ).fetchall()
        return [dict(r) for r in rows]
