"""Personal Baidu / Quark import via OpenList (own drive only — no share links)."""

from __future__ import annotations

import hashlib
import re
from typing import Any, Literal

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import RedirectResponse
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.deps import get_current_user
from app.models import User, UserLinkCourse, UserNetdiskBinding
from app.services.netdisk_crypto import encrypt_credential
from app.services.netdisk_play import signed_play_url, verify_play
from app.services.netdisk_sidecars import load_sidecars_for_video
from app.services.openlist_client import (
    OpenListClient,
    OpenListError,
    is_video_name,
    join_mount,
    public_raw_url,
)

router = APIRouter(prefix="/netdisk", tags=["netdisk"])

Provider = Literal["baidu", "quark"]
_PROVIDER_RE = re.compile(r"^(baidu|quark)$")


class NetdiskBindIn(BaseModel):
    provider: Provider
    # Browser Cookie for Quark / Baidu pan, or Baidu refresh_token.
    credential: str = Field(min_length=8, max_length=16_000)


class NetdiskStatusOut(BaseModel):
    openlist_configured: bool
    providers: list[dict[str, Any]]


class NetdiskEntryOut(BaseModel):
    name: str
    path: str
    is_dir: bool
    size: int | None = None
    is_video: bool = False


class NetdiskListOut(BaseModel):
    provider: Provider
    path: str
    entries: list[NetdiskEntryOut]


class NetdiskImportIn(BaseModel):
    provider: Provider
    # Absolute OpenList path under the user mount, e.g. /ae-u1-baidu/Course/ep1.mp4
    paths: list[str] = Field(min_length=1, max_length=40)


class NetdiskImportItemOut(BaseModel):
    path: str
    course_id: str
    title: str
    watch_url: str
    ok: bool
    error: str | None = None
    has_en: bool = False
    has_zh: bool = False


class NetdiskImportOut(BaseModel):
    items: list[NetdiskImportItemOut]


def _require_openlist() -> None:
    if not settings.openlist_configured:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="网盘导入未启用：服务端未配置 OpenList",
        )


def _mount_for(user_id: int, provider: str) -> str:
    return f"/ae-u{user_id}-{provider}"


def _external_id(provider: str, path: str) -> str:
    digest = hashlib.sha1(f"{provider}:{path}".encode("utf-8")).hexdigest()[:20]
    return f"{provider[:1]}{digest}"


@router.get("/status", response_model=NetdiskStatusOut)
async def netdisk_status(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> NetdiskStatusOut:
    result = await db.execute(
        select(UserNetdiskBinding).where(UserNetdiskBinding.user_id == user.id)
    )
    rows = list(result.scalars().all())
    return NetdiskStatusOut(
        openlist_configured=settings.openlist_configured,
        providers=[
            {
                "provider": row.provider,
                "bound": True,
                "mount_path": row.openlist_mount_path,
                "updated_at": row.updated_at.isoformat() if row.updated_at else None,
            }
            for row in rows
        ],
    )


@router.post("/bind")
async def bind_netdisk(
    payload: NetdiskBindIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    _require_openlist()
    provider = payload.provider
    if not _PROVIDER_RE.match(provider):
        raise HTTPException(400, "provider 必须是 baidu 或 quark")
    credential = payload.credential.strip()
    if len(credential) < 8:
        raise HTTPException(400, "凭证过短")

    mount = _mount_for(user.id, provider)
    client = OpenListClient()
    result = await db.execute(
        select(UserNetdiskBinding).where(
            UserNetdiskBinding.user_id == user.id,
            UserNetdiskBinding.provider == provider,
        )
    )
    row = result.scalar_one_or_none()
    try:
        if row is None:
            storage_id = await client.create_storage(
                mount_path=mount,
                provider=provider,
                credential=credential,
            )
            row = UserNetdiskBinding(
                user_id=user.id,
                provider=provider,
                credential_enc=encrypt_credential(credential),
                openlist_mount_path=mount,
                openlist_storage_id=storage_id,
            )
            db.add(row)
        else:
            storage_id = row.openlist_storage_id
            if storage_id is None:
                storage_id = await client.create_storage(
                    mount_path=mount,
                    provider=provider,
                    credential=credential,
                )
            else:
                await client.update_storage(
                    storage_id=storage_id,
                    mount_path=mount,
                    provider=provider,
                    credential=credential,
                )
            row.credential_enc = encrypt_credential(credential)
            row.openlist_mount_path = mount
            row.openlist_storage_id = storage_id
        await db.commit()
    except OpenListError as exc:
        await db.rollback()
        raise HTTPException(502, f"OpenList 绑定失败：{exc}") from exc

    return {
        "ok": True,
        "provider": provider,
        "mount_path": mount,
        "storage_id": row.openlist_storage_id,
    }


@router.delete("/bind/{provider}")
async def unbind_netdisk(
    provider: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, bool]:
    if not _PROVIDER_RE.match(provider):
        raise HTTPException(400, "provider 必须是 baidu 或 quark")
    result = await db.execute(
        select(UserNetdiskBinding).where(
            UserNetdiskBinding.user_id == user.id,
            UserNetdiskBinding.provider == provider,
        )
    )
    row = result.scalar_one_or_none()
    if row is None:
        return {"ok": True}
    if settings.openlist_configured and row.openlist_storage_id is not None:
        try:
            await OpenListClient().delete_storage(row.openlist_storage_id)
        except OpenListError:
            pass
    await db.delete(row)
    await db.commit()
    return {"ok": True}


@router.get("/list", response_model=NetdiskListOut)
async def list_netdisk(
    provider: Provider,
    path: str = "",
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> NetdiskListOut:
    _require_openlist()
    result = await db.execute(
        select(UserNetdiskBinding).where(
            UserNetdiskBinding.user_id == user.id,
            UserNetdiskBinding.provider == provider,
        )
    )
    row = result.scalar_one_or_none()
    if row is None:
        raise HTTPException(400, f"请先绑定{provider}网盘")

    full = join_mount(row.openlist_mount_path, path)
    try:
        data = await OpenListClient().fs_list(full)
    except OpenListError as exc:
        raise HTTPException(502, f"列目录失败：{exc}") from exc

    content = data.get("content") if isinstance(data, dict) else None
    entries: list[NetdiskEntryOut] = []
    if isinstance(content, list):
        for item in content:
            if not isinstance(item, dict):
                continue
            name = str(item.get("name") or "")
            if not name or name in (".", ".."):
                continue
            is_dir = bool(item.get("is_dir"))
            child_path = join_mount(full, name) if not full.endswith("/" + name) else full
            # Prefer building from mount + relative.
            child_path = f"{full.rstrip('/')}/{name}"
            is_video = (not is_dir) and is_video_name(name)
            if not is_dir and not is_video:
                continue
            size_raw = item.get("size")
            size = int(size_raw) if isinstance(size_raw, (int, float)) else None
            entries.append(
                NetdiskEntryOut(
                    name=name,
                    path=child_path,
                    is_dir=is_dir,
                    size=size,
                    is_video=is_video,
                )
            )
    entries.sort(key=lambda e: (not e.is_dir, e.name.lower()))
    return NetdiskListOut(provider=provider, path=full, entries=entries)


@router.post("/import", response_model=NetdiskImportOut)
async def import_netdisk_videos(
    payload: NetdiskImportIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> NetdiskImportOut:
    """Import selected videos from the user's own mounted drive into personal assets."""
    _require_openlist()
    result = await db.execute(
        select(UserNetdiskBinding).where(
            UserNetdiskBinding.user_id == user.id,
            UserNetdiskBinding.provider == payload.provider,
        )
    )
    row = result.scalar_one_or_none()
    if row is None:
        raise HTTPException(400, "请先绑定网盘")

    mount = row.openlist_mount_path.rstrip("/")
    client = OpenListClient()
    items: list[NetdiskImportItemOut] = []

    for raw_path in payload.paths:
        path = raw_path.strip()
        if not path.startswith(mount):
            items.append(
                NetdiskImportItemOut(
                    path=path,
                    course_id="",
                    title="",
                    watch_url="",
                    ok=False,
                    error="路径不属于当前绑定网盘",
                )
            )
            continue
        if not is_video_name(path.rsplit("/", 1)[-1]):
            items.append(
                NetdiskImportItemOut(
                    path=path,
                    course_id="",
                    title="",
                    watch_url="",
                    ok=False,
                    error="仅支持视频文件",
                )
            )
            continue
        try:
            meta = await client.fs_get(path)
        except OpenListError as exc:
            items.append(
                NetdiskImportItemOut(
                    path=path,
                    course_id="",
                    title="",
                    watch_url="",
                    ok=False,
                    error=str(exc),
                )
            )
            continue

        title = str(meta.get("name") or path.rsplit("/", 1)[-1])
        # Persist the OpenList path. Playback mints a fresh upstream URL.
        watch_url = path
        external_id = _external_id(payload.provider, path)
        source = f"{payload.provider}_netdisk"

        existing = await db.execute(
            select(UserLinkCourse).where(
                UserLinkCourse.user_id == user.id,
                UserLinkCourse.source == source,
                UserLinkCourse.external_id == external_id,
            )
        )
        link = existing.scalar_one_or_none()
        if link is None:
            link = UserLinkCourse(
                user_id=user.id,
                source=source,
                external_id=external_id,
                title=title[:512],
                author=payload.provider,
                watch_url=watch_url[:1024],
                duration_sec=60,
            )
            db.add(link)
        else:
            link.title = title[:512]
            link.watch_url = watch_url[:1024]

        # Same-folder .srt/.vtt → personal softsubs for the learning player.
        try:
            sidecars = await load_sidecars_for_video(client, path)
        except Exception:  # noqa: BLE001
            sidecars = {}
        if sidecars.get("en"):
            link.subtitle_en_srt = sidecars["en"]
        if sidecars.get("zh"):
            link.subtitle_zh_srt = sidecars["zh"]

        await db.flush()
        items.append(
            NetdiskImportItemOut(
                path=path,
                course_id=f"link-{link.id}",
                title=title,
                watch_url=signed_play_url(link.id, user.id),
                ok=True,
                has_en=bool(link.subtitle_en_srt),
                has_zh=bool(link.subtitle_zh_srt),
            )
        )

    await db.commit()
    return NetdiskImportOut(items=items)


@router.get("/play/{import_id}")
async def play_netdisk_video(
    import_id: int,
    uid: int,
    exp: int,
    sig: str,
    db: AsyncSession = Depends(get_db),
) -> RedirectResponse:
    """Refresh the upstream URL and redirect the player. No bearer token."""
    _require_openlist()
    if not verify_play(import_id, uid, exp, sig):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "播放链接无效或已过期")
    result = await db.execute(
        select(UserLinkCourse).where(
            UserLinkCourse.id == import_id,
            UserLinkCourse.user_id == uid,
        )
    )
    row = result.scalar_one_or_none()
    if row is None or not str(row.source).endswith("_netdisk"):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "课程不存在")
    path = (row.watch_url or "").strip()
    if not path.startswith("/"):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "网盘路径无效")
    try:
        meta = await OpenListClient().fs_get(path)
    except OpenListError as exc:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, f"无法获取播放地址：{exc}") from exc
    raw_url = str(meta.get("raw_url") or "").strip()
    if not raw_url:
        raw_url = public_raw_url(path)
    return RedirectResponse(raw_url, status_code=status.HTTP_302_FOUND)
