"""Authenticated accompaniment extraction via the private ECS worker."""

import asyncio
import tempfile
from pathlib import Path

import httpx
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from starlette.background import BackgroundTask

from app.config import settings
from app.deps import get_current_user

router = APIRouter(prefix="/stem", tags=["stem"])
_worker = asyncio.Lock()


@router.post("/separate", dependencies=[Depends(get_current_user)])
async def separate(file: UploadFile = File(...)) -> FileResponse:
    if not file.size or file.size > 100 * 1024 * 1024:
        raise HTTPException(413, "Video exceeds the separation upload limit")
    if _worker.locked():
        raise HTTPException(503, "Separation is busy, please retry")
    directory = Path(settings.media_cache_dir).resolve().parent / "private_stems"
    directory.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=directory, suffix=".wav", delete=False) as output:
        path = Path(output.name)
    try:
        async with _worker, httpx.AsyncClient(timeout=540) as client:
            async with client.stream(
                "POST",
                "http://127.0.0.1:8790/v1/separate",
                files={"file": ("video.mp4", file.file, "video/mp4")},
            ) as response:
                response.raise_for_status()
                if "audio/wav" not in response.headers.get("content-type", ""):
                    raise ValueError("Invalid worker response")
                with path.open("wb") as target:
                    async for chunk in response.aiter_bytes():
                        target.write(chunk)
        if path.stat().st_size < 44:
            raise ValueError("Invalid accompaniment")
    except (httpx.HTTPError, OSError, ValueError) as error:
        path.unlink(missing_ok=True)
        raise HTTPException(503, "Vocal separation is unavailable") from error
    except BaseException:
        path.unlink(missing_ok=True)
        raise
    return FileResponse(path, media_type="audio/wav", background=BackgroundTask(path.unlink, missing_ok=True))
