"""Local-only usage dashboard. No prompts, responses or credentials are stored."""
import hashlib
import json
import os
import re
import sqlite3
import threading
import time
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SHANGHAI = timezone(timedelta(hours=8))

# Known App modules → Chinese labels (mirrored in platform_billing).
MODULE_LABELS_ZH = {
    "oral_coach": "口语陪练",
    "digital_human": "数字人对话",
    "peer_oral": "双人口语",
    "subtitle_asr": "字幕补全·ASR",
    "subtitle_translate": "字幕补全·翻译",
    "subtitle_resegment": "字幕重切分",
    "translation": "阅读/播放器翻译",
    "word_lookup": "查词",
    "grammar": "语法解析",
    "writing_grade": "写作批改",
    "reading_tts": "阅读配音 TTS",
    "fingerprint": "素材指纹 Embedding",
    "scene_vl": "场景识词 VL",
    "vocab_enrich": "词卡 enrichment",
    "local_ollama": "本地 Ollama（未标注模块）",
    "unknown": "未标注模块",
}


def normalize_module(raw: str) -> str:
    value = (raw or "").strip().lower().replace(" ", "_")
    if not value:
        return "unknown"
    # Keep a short stable token.
    value = re.sub(r"[^a-z0-9_\-]", "", value)[:48]
    return value or "unknown"


def normalize_json_response(text):
    """Honor json_object mode even when a small model emits JS-style keys."""
    text = re.sub(r'^```(?:json)?\s*', '', text.strip())
    text = re.sub(r'\s*```$', '', text)
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        text = re.sub(r'(^|\n)(\s*)([A-Za-z_][A-Za-z0-9_]*)(\s*:)',
                      r'\1\2"\3"\4', text)
        value = json.loads(text)
    if not isinstance(value, dict):
        raise ValueError('Expected a JSON object')
    if 'tag' in value and 'type' not in value:
        value['type'] = value.pop('tag')
    return json.dumps(value, ensure_ascii=False)


class UsageStore:
    def __init__(self, path):
        self.path = str(path)
        self.lock = threading.Lock()
        with self.connect() as db:
            db.execute('''CREATE TABLE IF NOT EXISTS requests (
                id INTEGER PRIMARY KEY, started REAL, day TEXT, client TEXT,
                kind TEXT, finished REAL, status INTEGER, input_tokens INTEGER DEFAULT 0,
                output_tokens INTEGER DEFAULT 0, estimated INTEGER DEFAULT 0)''')
            cols = {row[1] for row in db.execute('PRAGMA table_info(requests)')}
            if 'module' not in cols:
                db.execute("ALTER TABLE requests ADD COLUMN module TEXT DEFAULT 'unknown'")
            db.execute('''UPDATE requests SET finished=?, status=499, estimated=1
                          WHERE finished IS NULL''', (time.time(),))

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=10)
        try:
            with db:
                yield db
        finally:
            db.close()

    def begin(self, client, kind, module='unknown'):
        now = time.time()
        # Client identifiers are pseudonyms, not authenticated account identities.
        client = hashlib.sha256(client.encode()).hexdigest()[:12]
        module = normalize_module(module)
        with self.lock, self.connect() as db:
            cursor = db.execute(
                'INSERT INTO requests(started, day, client, kind, module) VALUES(?,?,?,?,?)',
                (now, datetime.now(SHANGHAI).date().isoformat(), client, kind, module),
            )
            return cursor.lastrowid

    def finish(self, request_id, status, usage):
        with self.lock, self.connect() as db:
            db.execute('''UPDATE requests SET finished=?, status=?, input_tokens=?,
                          output_tokens=?, estimated=? WHERE id=?''',
                       (time.time(), status, max(0, int(usage.get('prompt_tokens', 0))),
                        max(0, int(usage.get('completion_tokens', 0))),
                        int(not bool(usage)), request_id))

    def snapshot(self):
        day = datetime.now(SHANGHAI).date().isoformat()
        with self.lock, self.connect() as db:
            total, failed, inputs, outputs, unknown = db.execute('''SELECT COUNT(*),
                COALESCE(SUM(status>=400),0), COALESCE(SUM(input_tokens),0),
                COALESCE(SUM(output_tokens),0), COALESCE(SUM(estimated),0)
                FROM requests WHERE day=?''', (day,)).fetchone()
            rows = db.execute('''SELECT client, kind, module, COUNT(*), MAX(started),
                COALESCE(SUM(input_tokens+output_tokens),0),
                COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0),
                SUM(finished IS NULL)
                FROM requests WHERE day=? GROUP BY client, kind, module
                ORDER BY MAX(started) DESC''', (day,)).fetchall()
            module_rows = db.execute('''SELECT COALESCE(NULLIF(module,''),'unknown'),
                COUNT(*), COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0),
                COALESCE(SUM(input_tokens+output_tokens),0)
                FROM requests WHERE day=? GROUP BY COALESCE(NULLIF(module,''),'unknown')
                ORDER BY COALESCE(SUM(input_tokens+output_tokens),0) DESC''', (day,)).fetchall()
        now = time.time()
        by_module = [
            dict(
                module=r[0],
                label_zh=MODULE_LABELS_ZH.get(r[0], r[0]),
                requests=r[1],
                input_tokens=r[2],
                output_tokens=r[3],
                tokens=r[4],
            )
            for r in module_rows
        ]
        return dict(
            day=day,
            timezone='Asia/Shanghai',
            requests=total,
            failures=failed,
            input_tokens=inputs,
            output_tokens=outputs,
            total_tokens=inputs + outputs,
            requests_without_usage=unknown,
            active_clients=sum(row[4] > now - 300 for row in rows),
            by_module=by_module,
            clients=[
                dict(
                    client=r[0],
                    kind=r[1],
                    module=r[2] or 'unknown',
                    requests=r[3],
                    last_seen=r[4],
                    tokens=r[5],
                    input_tokens=r[6],
                    output_tokens=r[7],
                    in_flight=r[8],
                )
                for r in rows
            ],
        )


class UsageMiddleware:
    def __init__(self, app, store):
        self.app, self.store = app, store

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http' or not scope['path'].endswith('/chat/completions'):
            return await self.app(scope, receive, send)
        headers = dict(scope.get('headers', []))
        client = headers.get(b'x-acquire-client-id', b'').decode(errors='replace')[:128]
        kind = 'self-reported account' if headers.get(b'x-acquire-client-kind') == b'account' else 'anonymous client'
        module = headers.get(b'x-acquire-module', b'').decode(errors='replace')
        if not module:
            # Optional query-ish fallback via custom header aliases.
            module = headers.get(b'x-ae-module', b'').decode(errors='replace')
        if not client:
            client = str(scope.get('client', ('unknown',))[0])
        request_id = self.store.begin(client, kind, module=module or 'unknown')
        chunks, status = bytearray(), 500

        async def observed(message):
            nonlocal status
            if message['type'] == 'http.response.start':
                status = message['status']
            elif message['type'] == 'http.response.body' and len(chunks) < 262144:
                chunks.extend(message.get('body', b''))
            await send(message)

        try:
            await self.app(scope, receive, observed)
        finally:
            try:
                usage = json.loads(chunks).get('usage', {})
            except (ValueError, AttributeError):
                usage = {}
            self.store.finish(request_id, status, usage)


def install_monitor(app):
    path = Path(os.getenv('ACQUIRE_USAGE_DB', str(Path(__file__).with_name('usage.sqlite3'))))
    store = UsageStore(path)
    app.add_middleware(UsageMiddleware, store=store)

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != '/stats':
                self.send_error(404)
                return
            body = json.dumps(store.snapshot()).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_):
            pass

    @app.on_event('startup')
    def start():
        # Bind beyond loopback so ECS can scrape over Tailscale.
        # Do NOT put this port behind the public nginx ollama proxy.
        host = os.getenv('ACQUIRE_USAGE_STATS_HOST', '0.0.0.0')
        port = int(os.getenv('ACQUIRE_USAGE_STATS_PORT', '11435'))
        server = ThreadingHTTPServer((host, port), Handler)
        app.state.usage_server = server
        threading.Thread(target=server.serve_forever, daemon=True).start()

    @app.on_event('shutdown')
    def stop():
        server = getattr(app.state, 'usage_server', None)
        if server:
            server.shutdown()
            server.server_close()

    return store
