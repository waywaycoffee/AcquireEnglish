#!/usr/bin/env python3
"""Upload oral_core_9000 subtitle files + publish manifest note.

Usage:
  set ACQUIRE_API_BASE=https://your-api
  set ACQUIRE_API_TOKEN=...
  python upload_to_ecs.py

Uploads local `subs/{nn}/en.srt|zh.srt` via POST /api/content/media/upload
namespace=course, book_id=oral_core_9000, key={nn}/en.srt

Manifest itself is deployed with the API repo (`services/api/data/oral_core_9000`).
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import urllib.request

ROOT = Path(__file__).resolve().parent
SUBS = ROOT / "subs"


def upload(path: Path, key: str) -> None:
    base = os.environ.get("ACQUIRE_API_BASE", "").rstrip("/")
    token = os.environ.get("ACQUIRE_API_TOKEN", "")
    if not base:
        raise SystemExit("Set ACQUIRE_API_BASE")
    boundary = "----AcquireBoundary7MA4YWxkTrZu0gW"
    body = bytearray()
    fields = {
        "book_id": "oral_core_9000",
        "key": key,
        "namespace": "course",
    }
    for name, value in fields.items():
        body.extend(f"--{boundary}\r\n".encode())
        body.extend(
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
        )
    body.extend(f"--{boundary}\r\n".encode())
    body.extend(
        f'Content-Disposition: form-data; name="file"; filename="{path.name}"\r\n'.encode()
    )
    body.extend(b"Content-Type: application/octet-stream\r\n\r\n")
    body.extend(path.read_bytes())
    body.extend(f"\r\n--{boundary}--\r\n".encode())
    req = urllib.request.Request(
        f"{base}/api/content/media/upload",
        data=bytes(body),
        method="POST",
        headers={
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            **({"Authorization": f"Bearer {token}"} if token else {}),
        },
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        print(path.name, resp.status, resp.read()[:200])


def main() -> None:
    if not SUBS.is_dir():
        print("No tools/oral_core_9000/subs yet — drop en.srt/zh.srt per lesson first.")
        sys.exit(0)
    for lesson_dir in sorted(SUBS.iterdir()):
        if not lesson_dir.is_dir():
            continue
        nn = lesson_dir.name
        for name in ("en.srt", "zh.srt"):
            f = lesson_dir / name
            if f.is_file():
                upload(f, f"{nn}/{name}")


if __name__ == "__main__":
    main()
