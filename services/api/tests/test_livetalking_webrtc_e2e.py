"""LiveTalking WebRTC lip-sync E2E (requires Tailscale + running LiveTalking).

Skip unless LIVETALKING_WEBRTC_E2E=1 (or RUN_LIVETALKING_WEBRTC=1).

Uses tools/livetalking/test_webrtc_e2e.py via the LiveTalking venv when present.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[3]
SCRIPT = REPO / "tools" / "livetalking" / "test_webrtc_e2e.py"
LT_VENV_WIN = REPO / "third_party" / "LiveTalking" / ".venv" / "Scripts" / "python.exe"
LT_VENV_UNIX = REPO / "third_party" / "LiveTalking" / ".venv" / "bin" / "python"
BASE = os.environ.get("LIVETALKING_BASE", "http://100.115.252.55:8010").rstrip("/")


def _enabled() -> bool:
    return os.environ.get("LIVETALKING_WEBRTC_E2E", "").strip() in {
        "1",
        "true",
        "yes",
    } or os.environ.get("RUN_LIVETALKING_WEBRTC", "").strip() in {"1", "true", "yes"}


def _python() -> str:
    if LT_VENV_WIN.is_file():
        return str(LT_VENV_WIN)
    if LT_VENV_UNIX.is_file():
        return str(LT_VENV_UNIX)
    return sys.executable


@pytest.mark.skipif(not _enabled(), reason="Set LIVETALKING_WEBRTC_E2E=1 to run WebRTC E2E")
def test_livetalking_webrtc_offer_human_e2e():
    assert SCRIPT.is_file(), f"missing {SCRIPT}"
    env = os.environ.copy()
    env["LIVETALKING_BASE"] = BASE
    proc = subprocess.run(
        [
            _python(),
            str(SCRIPT),
            "--base",
            BASE,
            "--avatar",
            os.environ.get("LIVETALKING_AVATAR", "wav2lip_avatar_glass_man"),
            "--track-wait",
            "15",
            "--speak-wait",
            "5",
        ],
        capture_output=True,
        text=True,
        env=env,
        cwd=str(REPO),
        timeout=180,
        check=False,
    )
    out = (proc.stdout or "") + "\n" + (proc.stderr or "")
    try:
        # Script prints JSON summary as last/only stdout object
        summary = json.loads(proc.stdout.strip().split("\n\n")[-1] if proc.stdout else "{}")
    except json.JSONDecodeError:
        summary = {"ok": False, "raw": out[-800:]}
    assert proc.returncode == 0 and summary.get("ok") is True, (
        f"WebRTC E2E failed rc={proc.returncode} summary={json.dumps(summary)[:800]}"
    )
    human = (summary.get("steps") or {}).get("human") or {}
    assert human.get("code") == 0
    offer = (summary.get("steps") or {}).get("offer") or {}
    assert offer.get("has_sdp") is True
    assert offer.get("sessionid")
