#!/usr/bin/env python3
"""Push CosyVoice Harry Potter (or other local TTS) progress to AcquireEnglish admin.

Reads progress.json + narrate.pid on the 5060 Ti box and POSTs a snapshot to
``POST /api/admin/tts-progress/report`` (X-Admin-Token).

Defaults match the local CosyVoice layout documented for Jingway:

  D:\\cosyvoice\\output\\harry-potter\\progress.json
  D:\\cosyvoice\\output\\harry-potter\\narrate.pid
  WAV dirs: female_aria / male_guy

Examples (PowerShell on the GPU box)::

  $env:AE_ADMIN_TOKEN = (Get-Content ...\\acquireenglish-admin-login.token -Raw).Trim()
  python tools/cosyvoice/report_tts_progress.py --once

  # every 60s while narrating
  python tools/cosyvoice/report_tts_progress.py --loop 60

Env:
  AE_API_BASE     default https://acquireenglish.curlhairai.com
  AE_ADMIN_TOKEN  required (same ops token as /admin/)
  COSYVOICE_HP_DIR  default D:\\cosyvoice\\output\\harry-potter
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


DEFAULT_DIR = Path(r"D:\cosyvoice\output\harry-potter")
DEFAULT_API = "https://acquireenglish.curlhairai.com"
VOICE_DIRS = ("female_aria", "male_guy")


def _pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    if os.name == "nt":
        try:
            import ctypes

            kernel32 = ctypes.windll.kernel32  # type: ignore[attr-defined]
            PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
            handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
            if not handle:
                return False
            kernel32.CloseHandle(handle)
            return True
        except Exception:  # noqa: BLE001
            return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def _count_chapter_wavs(voice_dir: Path) -> tuple[int, int]:
    """Return (doneish_count, chapter_dirs_or_files). Best-effort from disk layout."""
    if not voice_dir.is_dir():
        return 0, 0
    chapters = [
        p
        for p in voice_dir.iterdir()
        if p.is_dir() or (p.is_file() and p.suffix.lower() == ".wav")
    ]
    if not chapters:
        return 0, 0
    done = 0
    for item in chapters:
        if item.is_file() and item.suffix.lower() == ".wav" and item.stat().st_size > 64:
            done += 1
        elif item.is_dir():
            wavs = [w for w in item.glob("*.wav") if w.stat().st_size > 64]
            # chapter done if concat chapter.wav exists or any chunk wavs
            if (item / "chapter.wav").is_file() and (item / "chapter.wav").stat().st_size > 64:
                done += 1
            elif wavs:
                done += 1
    return done, len(chapters)


def load_snapshot(root: Path, *, job_id: str, title: str) -> dict:
    progress_path = root / "progress.json"
    pid_path = root / "narrate.pid"
    progress: dict = {}
    if progress_path.is_file():
        try:
            progress = json.loads(progress_path.read_text(encoding="utf-8"))
            if not isinstance(progress, dict):
                progress = {"_raw": progress}
        except (OSError, json.JSONDecodeError) as exc:
            progress = {"last_error": f"progress.json read failed: {exc}"}

    pid = None
    pid_alive = False
    if pid_path.is_file():
        try:
            pid = int((pid_path.read_text(encoding="utf-8") or "").strip().split()[0])
            pid_alive = _pid_alive(pid)
        except (OSError, ValueError, IndexError):
            pid = None
            pid_alive = False

    voices: dict[str, dict] = {}
    # Prefer progress.json voices; fall back to counting WAV dirs.
    raw_voices = progress.get("voices") if isinstance(progress.get("voices"), dict) else {}
    for name in VOICE_DIRS:
        disk_done, disk_total = _count_chapter_wavs(root / name)
        meta = raw_voices.get(name) if isinstance(raw_voices.get(name), dict) else {}
        voices[name] = {
            "done_chapters": meta.get("done_chapters")
            or meta.get("chapters_done")
            or disk_done,
            "total": meta.get("chapters_total")
            or meta.get("total")
            or disk_total
            or progress.get("chapters_total"),
            "last_error": meta.get("last_error") or meta.get("error"),
        }

    return {
        "job_id": job_id,
        "title": title,
        "engine": "cosyvoice-local",
        "all_done": bool(progress.get("all_done")),
        "current_chapter": (progress.get("current") or {}).get("chapter")
        if isinstance(progress.get("current"), dict)
        else progress.get("current_chapter"),
        "current_voice": (progress.get("current") or {}).get("voice")
        if isinstance(progress.get("current"), dict)
        else progress.get("current_voice"),
        "chapters_total": progress.get("chapters_total") or progress.get("total_chapters"),
        "voices": voices,
        "last_error": progress.get("last_error")
        or progress.get("FATAL")
        or progress.get("error"),
        "pid": pid,
        "pid_alive": pid_alive,
        "paths": {
            "output_dir": str(root),
            "progress_json": str(progress_path),
            "pid_file": str(pid_path),
            "female_dir": str(root / "female_aria"),
            "male_dir": str(root / "male_guy"),
        },
        "progress": progress,
    }


def post_report(api_base: str, token: str, payload: dict) -> dict:
    url = api_base.rstrip("/") + "/api/admin/tts-progress/report"
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "X-Admin-Token": token,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"HTTP {exc.code}: {detail}") from exc


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--dir",
        default=os.environ.get("COSYVOICE_HP_DIR") or str(DEFAULT_DIR),
        help="Harry Potter CosyVoice output dir",
    )
    ap.add_argument("--job-id", default="harry-potter")
    ap.add_argument("--title", default="Harry Potter · CosyVoice")
    ap.add_argument(
        "--api-base",
        default=os.environ.get("AE_API_BASE") or DEFAULT_API,
    )
    ap.add_argument(
        "--token",
        default=os.environ.get("AE_ADMIN_TOKEN") or "",
        help="X-Admin-Token (or AE_ADMIN_TOKEN)",
    )
    ap.add_argument("--once", action="store_true", default=True)
    ap.add_argument(
        "--loop",
        type=float,
        default=0,
        help="If >0, report every N seconds (implies not once)",
    )
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    if args.loop and args.loop > 0:
        args.once = False
    if not args.token and not args.dry_run:
        print("AE_ADMIN_TOKEN / --token required", file=sys.stderr)
        return 2

    root = Path(args.dir)
    while True:
        payload = load_snapshot(root, job_id=args.job_id, title=args.title)
        if args.dry_run:
            print(json.dumps(payload, ensure_ascii=False, indent=2))
        else:
            result = post_report(args.api_base, args.token, payload)
            job = (result or {}).get("job") or {}
            print(
                json.dumps(
                    {
                        "ok": result.get("ok"),
                        "status": job.get("status"),
                        "percent": job.get("percent"),
                        "pid_alive": job.get("pid_alive"),
                        "reported_at": job.get("reported_at"),
                    },
                    ensure_ascii=False,
                ),
                flush=True,
            )
        if args.once or not args.loop:
            break
        time.sleep(max(5.0, float(args.loop)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
