"""Minimal LiveTalking-compatible stub: GET / and POST /human on :8010."""
from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 8010


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:  # quieter
        print("[%s] %s" % (self.log_date_time_string(), fmt % args))

    def _send(self, code: int, body: dict) -> None:
        data = json.dumps(body).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self) -> None:
        if self.path in ("/", "/health", "/status"):
            self._send(200, {"ok": True, "service": "livetalking-stub", "port": PORT})
            return
        self._send(404, {"ok": False, "error": "not_found"})

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw.decode("utf-8") or "{}")
        except Exception:
            payload = {}
        if self.path.rstrip("/") == "/human":
            text = (payload.get("text") or "")[:500]
            print("human cue:", text)
            self._send(200, {"ok": True, "echo": text, "stub": True})
            return
        self._send(404, {"ok": False, "error": "not_found"})


if __name__ == "__main__":
    httpd = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"LiveTalking stub listening on http://127.0.0.1:{PORT}")
    httpd.serve_forever()
