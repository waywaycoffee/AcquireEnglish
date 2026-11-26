"""Local-only usage dashboard. No prompts, responses or credentials are stored."""
import asyncio
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


OUTCOME_OK = 'ok'
OUTCOME_HTTP_ERROR = 'http_error'
OUTCOME_CLIENT_ABORT = 'client_abort'
OUTCOME_MISSING_USAGE = 'missing_usage'


def classify_outcome(status, usage):
    """Split true errors / barge-in / missing usage so failure rate is not inflated."""
    status = int(status or 0)
    has_usage = bool(usage)
    if status in (499, 408):
        return OUTCOME_CLIENT_ABORT
    if status >= 400:
        return OUTCOME_HTTP_ERROR
    if status >= 200 and status < 300 and not has_usage:
        return OUTCOME_MISSING_USAGE
    return OUTCOME_OK


def _percentile(sorted_values, pct):
    if not sorted_values:
        return 0
    if len(sorted_values) == 1:
        return int(sorted_values[0])
    rank = (len(sorted_values) - 1) * (pct / 100.0)
    low = int(rank)
    high = min(low + 1, len(sorted_values) - 1)
    frac = rank - low
    return int(sorted_values[low] * (1 - frac) + sorted_values[high] * frac)


class UsageStore:
    def __init__(self, path):
        self.path = str(path)
        self.lock = threading.Lock()
        self._last_remote_scrape = 0.0
        self._last_remote_scrape_peer = ''
        with self.connect() as db:
            db.execute('''CREATE TABLE IF NOT EXISTS requests (
                id INTEGER PRIMARY KEY, started REAL, day TEXT, client TEXT,
                kind TEXT, finished REAL, status INTEGER, input_tokens INTEGER DEFAULT 0,
                output_tokens INTEGER DEFAULT 0, estimated INTEGER DEFAULT 0)''')
            cols = {row[1] for row in db.execute('PRAGMA table_info(requests)')}
            if 'module' not in cols:
                db.execute("ALTER TABLE requests ADD COLUMN module TEXT DEFAULT 'unknown'")
            for col, decl in (
                ('session', "TEXT DEFAULT ''"),
                ('latency_ms', 'INTEGER DEFAULT 0'),
                ('outcome', "TEXT DEFAULT ''"),
                ('error_detail', "TEXT DEFAULT ''"),
            ):
                if col not in cols:
                    db.execute(f'ALTER TABLE requests ADD COLUMN {col} {decl}')
            db.execute('''UPDATE requests SET finished=?, status=499, estimated=1,
                          outcome=? WHERE finished IS NULL''',
                       (time.time(), OUTCOME_CLIENT_ABORT))

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=10)
        try:
            with db:
                yield db
        finally:
            db.close()

    def note_remote_scrape(self, peer=''):
        """ECS→本机回程：记录非本机拉取 /stats 的时间。"""
        with self.lock:
            self._last_remote_scrape = time.time()
            if peer:
                self._last_remote_scrape_peer = str(peer)[:64]

    def reverse_path_info(self):
        with self.lock:
            last = self._last_remote_scrape
            peer = self._last_remote_scrape_peer
        age = None if not last else max(0, int(time.time() - last))
        return dict(
            last_remote_scrape_at=last or 0,
            last_remote_scrape_peer=peer,
            age_seconds=age,
            ok=age is not None and age < 600,
            detail=(
                '尚无 ECS/远端拉取记录'
                if age is None
                else f'最近远端拉取 /stats {age}s 前' + (f' · {peer}' if peer else '')
            ),
        )

    def begin(self, client, kind, module='unknown', session=''):
        now = time.time()
        # Client identifiers are pseudonyms, not authenticated account identities.
        client = hashlib.sha256(client.encode()).hexdigest()[:12]
        session = hashlib.sha256(session.encode()).hexdigest()[:10] if session else ''
        module = normalize_module(module)
        with self.lock, self.connect() as db:
            cursor = db.execute(
                'INSERT INTO requests(started, day, client, kind, module, session) '
                'VALUES(?,?,?,?,?,?)',
                (now, datetime.now(SHANGHAI).date().isoformat(), client, kind, module, session),
            )
            return cursor.lastrowid

    def finish(self, request_id, status, usage, error_detail=''):
        now = time.time()
        usage = usage or {}
        outcome = classify_outcome(status, usage)
        with self.lock, self.connect() as db:
            started = db.execute(
                'SELECT started FROM requests WHERE id=?', (request_id,)
            ).fetchone()
            latency_ms = 0
            if started and started[0]:
                latency_ms = max(0, int((now - float(started[0])) * 1000))
            db.execute(
                '''UPDATE requests SET finished=?, status=?, input_tokens=?,
                   output_tokens=?, estimated=?, latency_ms=?, outcome=?,
                   error_detail=? WHERE id=?''',
                (
                    now,
                    status,
                    max(0, int(usage.get('prompt_tokens', 0))),
                    max(0, int(usage.get('completion_tokens', 0))),
                    int(outcome == OUTCOME_MISSING_USAGE or not bool(usage)),
                    latency_ms,
                    outcome,
                    (error_detail or '')[:160],
                    request_id,
                ),
            )

    def snapshot(self):
        day = datetime.now(SHANGHAI).date().isoformat()
        with self.lock, self.connect() as db:
            total, failed, inputs, outputs, unknown = db.execute('''SELECT COUNT(*),
                COALESCE(SUM(status>=400),0), COALESCE(SUM(input_tokens),0),
                COALESCE(SUM(output_tokens),0), COALESCE(SUM(estimated),0)
                FROM requests WHERE day=?''', (day,)).fetchone()
            outcome_rows = db.execute(
                '''SELECT COALESCE(NULLIF(outcome,''),'unknown'), COUNT(*)
                   FROM requests WHERE day=? AND finished IS NOT NULL
                   GROUP BY COALESCE(NULLIF(outcome,''),'unknown')''',
                (day,),
            ).fetchall()
            latencies = [
                int(r[0])
                for r in db.execute(
                    '''SELECT latency_ms FROM requests
                       WHERE day=? AND finished IS NOT NULL AND latency_ms>0
                       ORDER BY latency_ms''',
                    (day,),
                ).fetchall()
            ]
            recent = db.execute(
                '''SELECT finished, module, outcome, status, error_detail, latency_ms
                   FROM requests
                   WHERE day=? AND finished IS NOT NULL
                     AND outcome IN (?,?,?)
                   ORDER BY finished DESC LIMIT 8''',
                (day, OUTCOME_HTTP_ERROR, OUTCOME_CLIENT_ABORT, OUTCOME_MISSING_USAGE),
            ).fetchall()
            rows = db.execute('''SELECT client, kind, module, COUNT(*), MAX(started),
                COALESCE(SUM(input_tokens+output_tokens),0),
                COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0),
                SUM(finished IS NULL),
                MAX(session)
                FROM requests WHERE day=? GROUP BY client, kind, module
                ORDER BY MAX(started) DESC''', (day,)).fetchall()
            module_rows = db.execute('''SELECT COALESCE(NULLIF(module,''),'unknown'),
                COUNT(*), COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0),
                COALESCE(SUM(input_tokens+output_tokens),0)
                FROM requests WHERE day=? GROUP BY COALESCE(NULLIF(module,''),'unknown')
                ORDER BY COALESCE(SUM(input_tokens+output_tokens),0) DESC''', (day,)).fetchall()
        now = time.time()
        by_outcome = {r[0]: int(r[1]) for r in outcome_rows}
        true_errors = by_outcome.get(OUTCOME_HTTP_ERROR, 0)
        client_aborts = by_outcome.get(OUTCOME_CLIENT_ABORT, 0)
        missing_usage = by_outcome.get(OUTCOME_MISSING_USAGE, 0)
        # Keep legacy `failures` as HTTP>=400 for compatibility; expose classified counts.
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
        refreshed = datetime.now(SHANGHAI).strftime('%Y-%m-%d %H:%M:%S')
        reverse = self.reverse_path_info()
        return dict(
            day=day,
            timezone='Asia/Shanghai',
            refreshed_at=refreshed,
            collected_at=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            requests=total,
            failures=failed,
            true_errors=true_errors,
            client_aborts=client_aborts,
            missing_usage=missing_usage,
            by_outcome=by_outcome,
            input_tokens=inputs,
            output_tokens=outputs,
            total_tokens=inputs + outputs,
            requests_without_usage=unknown,
            latency_ms=dict(
                p50=_percentile(latencies, 50),
                p95=_percentile(latencies, 95),
                max=int(latencies[-1]) if latencies else 0,
                samples=len(latencies),
            ),
            recent_errors=[
                dict(
                    at=datetime.fromtimestamp(float(r[0]), SHANGHAI).strftime('%H:%M:%S'),
                    module=r[1] or 'unknown',
                    outcome=r[2] or '',
                    status=int(r[3] or 0),
                    detail=r[4] or '',
                    latency_ms=int(r[5] or 0),
                )
                for r in recent
            ],
            reverse_path=reverse,
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
                    session=r[9] or '',
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
        if not client:
            # Prefer stable user/session pseudonyms when client-id is absent.
            client = headers.get(b'x-acquire-user-id', b'').decode(errors='replace')[:128]
        kind = 'self-reported account' if headers.get(b'x-acquire-client-kind') == b'account' else 'anonymous client'
        module = headers.get(b'x-acquire-module', b'').decode(errors='replace')
        if not module:
            # Optional query-ish fallback via custom header aliases.
            module = headers.get(b'x-ae-module', b'').decode(errors='replace')
        session = headers.get(b'x-acquire-session-id', b'').decode(errors='replace')[:128]
        if not session:
            session = headers.get(b'x-ae-session-id', b'').decode(errors='replace')[:128]
        if not client:
            client = str(scope.get('client', ('unknown',))[0])
        request_id = self.store.begin(
            client, kind, module=module or 'unknown', session=session
        )
        chunks, status = bytearray(), 500
        error_detail = ''

        async def observed(message):
            nonlocal status
            if message['type'] == 'http.response.start':
                status = message['status']
            elif message['type'] == 'http.response.body' and len(chunks) < 262144:
                chunks.extend(message.get('body', b''))
            await send(message)

        try:
            await self.app(scope, receive, observed)
        except (asyncio.CancelledError, ConnectionResetError, BrokenPipeError) as exc:
            status = 499
            error_detail = type(exc).__name__
            raise
        except Exception as exc:  # noqa: BLE001
            status = 500 if status < 400 else status
            error_detail = type(exc).__name__
            raise
        finally:
            try:
                usage = json.loads(chunks).get('usage', {}) if chunks else {}
            except (ValueError, AttributeError):
                usage = {}
            self.store.finish(request_id, status, usage, error_detail=error_detail)


def install_monitor(app):
    path = Path(os.getenv('ACQUIRE_USAGE_DB', str(Path(__file__).with_name('usage.sqlite3'))))
    store = UsageStore(path)
    app.add_middleware(UsageMiddleware, store=store)

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            path = self.path.split('?', 1)[0]
            peer = self.client_address[0] if self.client_address else ''
            if path == '/stats':
                # Non-loopback scrapes ≈ ECS Tailscale → local reverse path.
                if peer and peer not in ('127.0.0.1', '::1', 'localhost'):
                    store.note_remote_scrape(peer)
                body = json.dumps(store.snapshot()).encode()
            elif path in ('/backend-health', '/health/services'):
                try:
                    from backend_health import collect_backend_health
                except ImportError:
                    # Allow importing when cwd differs from this folder.
                    import importlib.util
                    spec = importlib.util.spec_from_file_location(
                        'backend_health',
                        Path(__file__).with_name('backend_health.py'),
                    )
                    mod = importlib.util.module_from_spec(spec)
                    assert spec.loader is not None
                    spec.loader.exec_module(mod)
                    collect_backend_health = mod.collect_backend_health
                body = json.dumps(
                    collect_backend_health(usage_store=store)
                ).encode()
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
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
