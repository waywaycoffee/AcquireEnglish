from __future__ import annotations

import pytest

from app.services import netdisk_import_jobs as jobs


@pytest.mark.asyncio
async def test_active_job_survives_client_reconnect() -> None:
    user_id = 991_337
    job_id, created = await jobs.create_job(
        user_id=user_id,
        provider="baidu",
        folder="/shows/Modern Family",
    )
    assert created is True
    await jobs.update_job(
        job_id,
        status="running",
        done=35,
        total=250,
        current="S02E12.mkv",
    )

    active = await jobs.get_active_job(user_id=user_id)
    assert active is not None
    assert active["id"] == job_id
    assert active["done"] == 35
    assert active["total"] == 250

    await jobs.update_job(job_id, status="done")
    assert await jobs.get_active_job(user_id=user_id) is None
