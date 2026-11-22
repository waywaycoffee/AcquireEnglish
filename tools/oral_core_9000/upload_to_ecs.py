#!/usr/bin/env python3
"""Upload oral_core_9000 subtitle files + note about API manifest.

Preferred (ops on this Windows host with SSH alias `acquireenglish`):

  python seed_pack_subs.py
  python upload_to_ecs.py --scp

Or multipart API upload (needs ACQUIRE_API_BASE + token; allows .srt now):

  set ACQUIRE_API_BASE=https://acquireenglish.curlhairai.com
  set ACQUIRE_API_TOKEN=...
  python upload_to_ecs.py

Manifest itself is deployed with the API repo (`services/api/data/oral_core_9000`).
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SUBS = ROOT / "subs"
REMOTE_MEDIA = "/opt/acquireenglish/services/api/media/course/oral_core_9000"
REMOTE_HOST = os.environ.get("ACQUIRE_SSH_HOST", "acquireenglish")


def upload_http(path: Path, key: str) -> None:
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


def upload_via_scp() -> None:
    if not SUBS.is_dir():
        raise SystemExit("No tools/oral_core_9000/subs — run seed_pack_subs.py first")
    with tempfile.TemporaryDirectory() as tmp:
        tgz = Path(tmp) / "oral_core_subs.tgz"
        with tarfile.open(tgz, "w:gz") as tar:
            for lesson_dir in sorted(SUBS.iterdir()):
                if not lesson_dir.is_dir():
                    continue
                for name in ("en.srt", "zh.srt"):
                    f = lesson_dir / name
                    if f.is_file():
                        tar.add(f, arcname=f"{lesson_dir.name}/{name}")
        remote_tgz = "/tmp/oral_core_subs.tgz"
        subprocess.check_call(["scp", str(tgz), f"{REMOTE_HOST}:{remote_tgz}"])
        script = f"""
set -e
mkdir -p {REMOTE_MEDIA}
rm -rf {REMOTE_MEDIA}/*
tar -xzf {remote_tgz} -C {REMOTE_MEDIA}
echo dirs=$(ls {REMOTE_MEDIA} | wc -l)
"""
        subprocess.check_call(["ssh", REMOTE_HOST, "bash", "-s"], input=script.encode())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--scp",
        action="store_true",
        help="tar+scp into ECS media/course/oral_core_9000 (recommended)",
    )
    args = parser.parse_args()
    if args.scp:
        upload_via_scp()
        return
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
                upload_http(f, f"{nn}/{name}")


if __name__ == "__main__":
    main()
