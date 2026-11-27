"""Enqueue long-novel TTS jobs on ECS for the local 5060 Ti worker.

Reads ``book.txt`` already uploaded under personal ebooks, calls
``reading_tts_queue.enqueue_book`` for the emotional voice pair
(``longanfengyue`` + ``longze_v3.1``), and does **not** spawn ECS drain —
``tools/reading/tts_worker.py`` on this PC claims and fills packs.

Example::

  python tools/reading/enqueue_book_tts.py --doc-id ebook-harry-potter-01 --index 1
"""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

BOOK_VOICES = ("longanfengyue", "longze_v3.1")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--doc-id", required=True)
    ap.add_argument("--index", type=int, required=True, help="Book number 1–7")
    ap.add_argument("--user-id", type=int, default=1)
    ap.add_argument("--series", default="harry-potter")
    ap.add_argument("--ssh-host", default="acquireenglish")
    ap.add_argument(
        "--voices",
        default=",".join(BOOK_VOICES),
        help="Comma-separated CosyVoice ids (default book pair)",
    )
    args = ap.parse_args()
    voices = [v.strip() for v in args.voices.split(",") if v.strip()]
    remote_txt = (
        f"/opt/acquireenglish/services/api/media/reading/personal/"
        f"{args.user_id}/ebooks/{args.series}/{args.index:02d}/book.txt"
    )
    remote_py = "/tmp/enqueue_book_tts.py"
    script = f'''
import json, os, sys
from pathlib import Path
sys.path.insert(0, "/opt/acquireenglish/services/api")
for line in Path("/opt/acquireenglish/services/api/.env").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

from app.services import reading_tts_queue as rtq

doc_id = {args.doc_id!r}
user_id = {args.user_id}
voices = {voices!r}
text_path = Path({remote_txt!r})
if not text_path.is_file():
    raise SystemExit(f"missing book text: {{text_path}}")
text = text_path.read_text(encoding="utf-8")
print(f"chars={{len(text)}} words≈{{len(text.split())}} long={{rtq.is_long_novel(text)}}", flush=True)
out = []
for voice in voices:
    status = rtq.enqueue_book(doc_id=doc_id, voice=voice, text=text, user_id=user_id)
    out.append(status)
    print(json.dumps(status, ensure_ascii=False), flush=True)
print("ENQUEUE_OK", json.dumps({{"doc_id": doc_id, "voices": out}}, ensure_ascii=False))
'''
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", suffix=".py", delete=False
    ) as tmp:
        tmp.write(script)
        local_py = tmp.name
    try:
        subprocess.run(
            ["scp", local_py, f"{args.ssh_host}:{remote_py}"], check=True
        )
        proc = subprocess.run(
            [
                "ssh",
                args.ssh_host,
                "cd /opt/acquireenglish/services/api && . .venv/bin/activate "
                f"&& python {remote_py}",
            ],
            check=False,
            capture_output=True,
            encoding="utf-8",
            errors="replace",
        )
    finally:
        Path(local_py).unlink(missing_ok=True)
    if proc.stdout:
        print(proc.stdout)
    if proc.stderr:
        print(proc.stderr, file=__import__("sys").stderr)
    return 0 if proc.returncode == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
