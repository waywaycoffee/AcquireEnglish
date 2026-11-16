"""Lightweight stem / accompaniment helper for 趣配音.

Prefer Demucs/UVR when installed on the GPU box. Falls back to ffmpeg
center-channel attenuation so clients always get a `no_vocals`-like WAV.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse

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


def _separate_with_ffmpeg(src: Path, out_wav: Path) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("ffmpeg not found")
    _run(
        [
            ffmpeg,
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(src),
            "-vn",
            "-af",
            "pan=stereo|c0=0.5*c0+-0.5*c1|c1=-0.5*c0+0.5*c1,aformat=sample_fmts=s16:sample_rates=16000:channel_layouts=mono",
            "-ac",
            "1",
            "-ar",
            "16000",
            str(out_wav),
        ]
    )


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
        src.write_bytes(await file.read())
        if not _separate_with_demucs(src, out):
            _separate_with_ffmpeg(src, out)
        if not out.exists() or out.stat().st_size <= 0:
            raise HTTPException(status_code=500, detail="separation produced empty output")
        # Caller downloads the wav; temp dir cleanup is left to OS tmp scrubbers.
        return FileResponse(
            path=out,
            media_type="audio/wav",
            filename=f"no_vocals-{episode_id or 'clip'}.wav",
        )
    except HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=str(exc)) from exc
