"""In-process queue_gpu drain loop (API lifespan) + CLI entry."""

from __future__ import annotations

import asyncio
import logging
from typing import Any

logger = logging.getLogger("fingerprint.queue_worker")

_worker_task: asyncio.Task[None] | None = None


async def drain_once(*, limit: int = 3) -> list[dict[str, Any]]:
    from app.database import SessionLocal
    from app.services.fingerprint import service as fp_svc

    async with SessionLocal() as session:
        return await fp_svc.drain_queue_gpu(session, limit=limit)


async def _loop(*, interval_idle: float = 20.0, interval_busy: float = 4.0) -> None:
    while True:
        processed = 0
        try:
            results = await drain_once(limit=3)
            processed = len(results)
            for item in results:
                if item.get("ok"):
                    logger.info(
                        "fingerprint queue ok task=%s asset=%s",
                        item.get("task_id"),
                        item.get("asset_id"),
                    )
                else:
                    logger.warning(
                        "fingerprint queue fail task=%s err=%s",
                        item.get("task_id"),
                        item.get("error"),
                    )
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001
            logger.exception("fingerprint queue worker tick failed")
        await asyncio.sleep(interval_busy if processed else interval_idle)


def start_background_worker() -> asyncio.Task[None]:
    global _worker_task
    if _worker_task is not None and not _worker_task.done():
        return _worker_task
    _worker_task = asyncio.create_task(_loop(), name="fingerprint-queue-gpu")
    logger.info("fingerprint queue_gpu background worker started")
    return _worker_task


async def stop_background_worker() -> None:
    global _worker_task
    task = _worker_task
    _worker_task = None
    if task is None:
        return
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass
    logger.info("fingerprint queue_gpu background worker stopped")
