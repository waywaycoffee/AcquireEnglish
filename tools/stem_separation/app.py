"""Private Demucs worker that returns an instrumental WAV."""

from __future__ import annotations

import asyncio
import os
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from starlette.background import BackgroundTask

app = FastAPI(title="AcquireEnglish stem separation", version="0.1.0")


def _run(cmd: list[str]) -> None:
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "command failed")


def _separate_with_demucs(src: Path, out_wav: Path) -> bool:
    if shutil.which("demucs") is None:
        return False
    work = out_wav.parent / "demucs_out"
    work.mkdir(parents=True, exist_ok=True)
    try:
        _run(
            [
                "demucs",
                "-n",
                os.environ.get("DEMUCS_MODEL", "htdemucs"),
                "--two-stems=vocals",
                "--shifts", "0",
                "--segment", "4",
                "-d", "cpu",
                "-o",
                str(work),
                str(src),
            ]
        )
        matches = list(work.rglob("no_vocals.wav"))
        if not matches:
            return False
        shutil.copyfile(matches[0], out_wav)
        return True
    except Exception:  # noqa: BLE001
        return False


@app.get("/health")
def health() -> dict[str, str]:
    return {
        "status": "ok",
        "demucs": "yes" if shutil.which("demucs") else "no",
        "ffmpeg": "yes" if shutil.which("ffmpeg") else "no",
    }


@app.post("/v1/separate")
async def separate(
    file: UploadFile = File(...),
    episode_id: str = Form(default=""),
) -> FileResponse:
    suffix = Path(file.filename or "input.media").suffix or ".media"
    work = Path(tempfile.mkdtemp(prefix="stem_"))
    src = work / f"src-{uuid.uuid4().hex}{suffix}"
    out = work / f"no_vocals-{uuid.uuid4().hex}.wav"
    try:
        with src.open("wb") as target:
            while chunk := await file.read(1024 * 1024):
                target.write(chunk)
        audio = work / "input.wav"
        await asyncio.to_thread(_run, [
            "ffmpeg", "-v", "error", "-protocol_whitelist", "file,pipe",
            "-i", str(src), "-vn",
            "-ac", "2", "-ar", "44100", str(audio),
        ])
        if not await asyncio.to_thread(_separate_with_demucs, audio, out):
            raise HTTPException(status_code=503, detail="Demucs unavailable or separation failed")
        if not out.exists() or out.stat().st_size <= 0:
            raise HTTPException(status_code=500, detail="separation produced empty output")
        return FileResponse(
            path=out,
            media_type="audio/wav",
            filename=f"no_vocals-{episode_id or 'clip'}.wav",
            background=BackgroundTask(shutil.rmtree, work, ignore_errors=True),
        )
    except HTTPException:
        shutil.rmtree(work, ignore_errors=True)
        raise
    except Exception as exc:  # noqa: BLE001
        shutil.rmtree(work, ignore_errors=True)
        raise HTTPException(status_code=500, detail=str(exc)) from exc
