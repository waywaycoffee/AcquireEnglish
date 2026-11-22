"""In-process queue_gpu drain loop (API lifespan) + scheduled LRU + CLI entry."""

from __future__ import annotations

import asyncio
import logging
import time
from typing import Any

from app.config import settings

logger = logging.getLogger("fingerprint.queue_worker")

_worker_task: asyncio.Task[None] | None = None
_last_lru_at: float = 0.0


async def drain_once(*, limit: int = 3) -> list[dict[str, Any]]:
    from app.database import SessionLocal
    from app.services.fingerprint import service as fp_svc

    async with SessionLocal() as session:
        return await fp_svc.drain_queue_gpu(session, limit=limit)


async def _maybe_lru_evict() -> None:
    global _last_lru_at
    interval = int(settings.fingerprint_lru_interval_seconds or 0)
    if interval <= 0:
        return
    now = time.time()
    if _last_lru_at and (now - _last_lru_at) < interval:
        return
    _last_lru_at = now
    try:
        from app.database import SessionLocal
        from app.services.fingerprint import service as fp_svc

        async with SessionLocal() as session:
            removed = await fp_svc.lru_evict_cold_assets(session, limit=20)
        if removed:
            logger.info("fingerprint scheduled LRU removed=%s", len(removed))
    except Exception:  # noqa: BLE001
        logger.exception("fingerprint scheduled LRU failed")


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
            await _maybe_lru_evict()
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001
            logger.exception("fingerprint queue worker tick failed")
        await asyncio.sleep(interval_busy if processed else interval_idle)


def start_background_worker() -> asyncio.Task[None]:
    global _worker_task
    if _worker_task is not None and not _worker_task.done():
        return _worker_task
    try:
        from app.services.fingerprint.runtime_config import load_into_settings

        load_into_settings()
    except Exception:  # noqa: BLE001
        logger.exception("fingerprint runtime config load failed at worker start")
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
