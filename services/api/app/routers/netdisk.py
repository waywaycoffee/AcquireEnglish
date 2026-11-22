"""Personal netdisk import via OpenList (own drive only — no share links)."""

from __future__ import annotations

import hashlib
import re
from pathlib import PurePosixPath
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
from app.schemas import CourseOut
from app.services.netdisk_crypto import encrypt_credential
from app.services.netdisk_books import scan_book_folder
from app.services.netdisk_episode_sort import sort_video_paths
from app.services.netdisk_play import signed_play_url, verify_play
from app.services.netdisk_series import (
    folder_title,
    series_course_id,
    series_key_for,
    to_series_course_out,
)
from app.services.netdisk_sidecars import load_sidecars_for_video
from app.services.openlist_client import (
    OpenListClient,
    OpenListError,
    is_video_name,
    join_mount,
    public_raw_url,
)

router = APIRouter(prefix="/netdisk", tags=["netdisk"])

Provider = Literal["baidu", "quark", "aliyun", "pan115"]
_PROVIDER_RE = re.compile(r"^(baidu|quark|aliyun|pan115)$")
_PROVIDER_LABEL = {
    "baidu": "百度网盘",
    "quark": "夸克",
    "aliyun": "阿里云盘",
    "pan115": "115",
}


class NetdiskBindIn(BaseModel):
    provider: Provider
    # Browser Cookie / refresh_token depending on provider.
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
    hint: str | None = (
        "外挂字幕建议命名：Show.S01E01.en.srt / Show.S01E01.zh.srt（亦支持 .ass）"
    )


class NetdiskImportIn(BaseModel):
    provider: Provider
    # Absolute OpenList path under the user mount, e.g. /ae-u1-baidu/Course/ep1.mp4
    paths: list[str] = Field(min_length=1, max_length=200)
    # Optional: attach imports to a series folder course.
    series_folder: str | None = None
    series_title: str | None = None


class NetdiskImportItemOut(BaseModel):
    path: str
    course_id: str
    title: str
    watch_url: str
    ok: bool
    error: str | None = None
    has_en: bool = False
    has_zh: bool = False
    episode_index: int | None = None


class NetdiskImportOut(BaseModel):
    items: list[NetdiskImportItemOut]
    series_course: CourseOut | None = None


class NetdiskImportSeriesIn(BaseModel):
    provider: Provider
    folder_path: str = Field(min_length=1, max_length=1024)
    title: str | None = None


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


def _validate_provider(provider: str) -> None:
    if not _PROVIDER_RE.match(provider):
        raise HTTPException(400, "provider 必须是 baidu / quark / aliyun / pan115")


async def _binding_or_400(
    db: AsyncSession, user_id: int, provider: str
) -> UserNetdiskBinding:
    result = await db.execute(
        select(UserNetdiskBinding).where(
            UserNetdiskBinding.user_id == user_id,
            UserNetdiskBinding.provider == provider,
        )
    )
    row = result.scalar_one_or_none()
    if row is None:
        label = _PROVIDER_LABEL.get(provider, provider)
        raise HTTPException(400, f"请先绑定{label}")
    return row


async def _upsert_video_link(
    *,
    db: AsyncSession,
    user: User,
    provider: str,
    path: str,
    series_key: str | None = None,
    series_title: str | None = None,
    episode_index: int | None = None,
) -> tuple[UserLinkCourse | None, NetdiskImportItemOut]:
    if not is_video_name(path.rsplit("/", 1)[-1]):
        return None, NetdiskImportItemOut(
            path=path,
            course_id="",
            title="",
            watch_url="",
            ok=False,
            error="仅支持视频文件",
        )
    client = OpenListClient()
    try:
        meta = await client.fs_get(path)
    except OpenListError as exc:
        return None, NetdiskImportItemOut(
            path=path,
            course_id="",
            title="",
            watch_url="",
            ok=False,
            error=str(exc),
        )

    title = str(meta.get("name") or path.rsplit("/", 1)[-1])
    external_id = _external_id(provider, path)
    source = f"{provider}_netdisk"
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
            author=provider,
            watch_url=path[:1024],
            duration_sec=60,
        )
        db.add(link)
    else:
        link.title = title[:512]
        link.watch_url = path[:1024]

    if series_key:
        link.series_key = series_key
        link.series_title = (series_title or link.series_title or title)[:512]
        link.episode_index = episode_index

    try:
        sidecars = await load_sidecars_for_video(client, path)
    except Exception:  # noqa: BLE001
        sidecars = {}
    if sidecars.get("en"):
        link.subtitle_en_srt = sidecars["en"]
    if sidecars.get("zh"):
        link.subtitle_zh_srt = sidecars["zh"]

    await db.flush()
    course_id = (
        series_course_id(series_key)
        if series_key
        else f"link-{link.id}"
    )
    return link, NetdiskImportItemOut(
        path=path,
        course_id=course_id,
        title=title,
        watch_url=signed_play_url(link.id, user.id),
        ok=True,
        has_en=bool(link.subtitle_en_srt),
        has_zh=bool(link.subtitle_zh_srt),
        episode_index=episode_index,
    )


@router.get("/status", response_model=NetdiskStatusOut)
async def netdisk_status(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> NetdiskStatusOut:
    result = await db.execute(
        select(UserNetdiskBinding).where(UserNetdiskBinding.user_id == user.id)
    )
    rows = list(result.scalars().all())
    providers: list[dict[str, Any]] = []
    client = OpenListClient() if settings.openlist_configured else None
    for row in rows:
        healthy = True
        error: str | None = None
        if client is not None:
            try:
                await client.fs_list(row.openlist_mount_path, page=1, per_page=1)
            except OpenListError as exc:
                healthy = False
                error = str(exc)
        providers.append(
            {
                "provider": row.provider,
                "bound": True,
                "mount_path": row.openlist_mount_path,
                "updated_at": row.updated_at.isoformat() if row.updated_at else None,
                "healthy": healthy,
                "error": error,
                "label": _PROVIDER_LABEL.get(row.provider, row.provider),
            }
        )
    return NetdiskStatusOut(
        openlist_configured=settings.openlist_configured,
        providers=providers,
    )


@router.post("/bind")
async def bind_netdisk(
    payload: NetdiskBindIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    _require_openlist()
    provider = payload.provider
    _validate_provider(provider)
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
    _validate_provider(provider)
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
    include_epub: bool = False,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> NetdiskListOut:
    _require_openlist()
    row = await _binding_or_400(db, user.id, provider)
    if any(part in (".", "..") for part in path.replace("\\", "/").split("/")):
        raise HTTPException(400, "目录路径无效")
    full = join_mount(row.openlist_mount_path, path)
    try:
        content_rows = await OpenListClient().fs_list_all(full)
    except OpenListError as exc:
        raise HTTPException(502, f"列目录失败：{exc}") from exc

    entries: list[NetdiskEntryOut] = []
    for item in content_rows:
        name = str(item.get("name") or "")
        if not name or name in (".", ".."):
            continue
        is_dir = bool(item.get("is_dir"))
        child_path = f"{full.rstrip('/')}/{name}"
        is_video = (not is_dir) and is_video_name(name)
        is_epub = include_epub and name.lower().endswith(".epub")
        if not is_dir and not is_video and not is_epub:
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


@router.get("/books/scan")
async def scan_netdisk_books(
    provider: Provider,
    path: str,
    epub_only: bool = True,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    """Recursively find books on the authenticated user's own drive."""
    _require_openlist()
    binding = await _binding_or_400(db, user.id, provider)
    mount = binding.openlist_mount_path.rstrip("/")
    root = path.rstrip("/")
    if root != mount and not root.startswith(mount + "/"):
        raise HTTPException(400, "文件夹不属于当前绑定网盘")
    if any(part in (".", "..") for part in root.split("/")):
        raise HTTPException(400, "文件夹路径无效")
    try:
        books = await scan_book_folder(OpenListClient(), root, epub_only=epub_only)
    except ValueError as exc:
        raise HTTPException(413, str(exc)) from exc
    except OpenListError as exc:
        raise HTTPException(502, f"扫描文件夹失败：{exc}") from exc
    return {"count": len(books), "books": books}


@router.get("/books/file")
async def get_netdisk_epub(
    provider: Provider,
    path: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Stream one EPUB from the user's bound drive for personal reading import."""
    import httpx
    from fastapi.responses import Response

    _require_openlist()
    binding = await _binding_or_400(db, user.id, provider)
    mount = binding.openlist_mount_path.rstrip("/")
    if not path.startswith(mount + "/") or any(p in (".", "..") for p in path.split("/")) or not path.lower().endswith(".epub"):
        raise HTTPException(400, "只能导入当前网盘内的 EPUB 文件")
    try:
        item = await OpenListClient().fs_get(path)
        raw = str(item.get("raw_url") or "")
        if not raw:
            raise HTTPException(404, "网盘文件不可读取")
        async with httpx.AsyncClient(follow_redirects=True, timeout=90) as client:
            async with client.stream("GET", raw) as upstream:
                upstream.raise_for_status()
                chunks = []
                size = 0
                async for chunk in upstream.aiter_bytes():
                    size += len(chunk)
                    if size > 30 * 1024 * 1024:
                        raise HTTPException(413, "EPUB 超过 30 MB，请使用本地导入")
                    chunks.append(chunk)
        return Response(content=b"".join(chunks), media_type="application/epub+zip")
    except OpenListError as exc:
        raise HTTPException(502, f"读取网盘失败：{exc}") from exc


@router.post("/import", response_model=NetdiskImportOut)
async def import_netdisk_videos(
    payload: NetdiskImportIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> NetdiskImportOut:
    """Import selected videos from the user's own mounted drive into personal assets."""
    _require_openlist()
    binding = await _binding_or_400(db, user.id, payload.provider)
    mount = binding.openlist_mount_path.rstrip("/")

    series_key: str | None = None
    series_title_val: str | None = None
    if payload.series_folder:
        folder = payload.series_folder.strip()
        if not folder.startswith(mount):
            raise HTTPException(400, "系列文件夹不属于当前绑定网盘")
        series_key = series_key_for(user.id, payload.provider, folder)
        series_title_val = folder_title(folder, payload.series_title)

    ordered = sort_video_paths([p.strip() for p in payload.paths if p.strip()])
    items: list[NetdiskImportItemOut] = []
    links: list[UserLinkCourse] = []
    for i, path in enumerate(ordered, start=1):
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
        link, item = await _upsert_video_link(
            db=db,
            user=user,
            provider=payload.provider,
            path=path,
            series_key=series_key,
            series_title=series_title_val,
            episode_index=i if series_key else None,
        )
        items.append(item)
        if link is not None and item.ok:
            links.append(link)

    await db.commit()
    series_course = None
    if series_key and links:
        series_course = CourseOut.model_validate(
            to_series_course_out(
                links,
                series_key=series_key,
                series_title=series_title_val or "网盘剧集",
            )
        )
    return NetdiskImportOut(items=items, series_course=series_course)


@router.post("/import-series", response_model=NetdiskImportOut)
async def import_netdisk_series(
    payload: NetdiskImportSeriesIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> NetdiskImportOut:
    """Import all videos in a folder as one multi-episode course."""
    _require_openlist()
    binding = await _binding_or_400(db, user.id, payload.provider)
    mount = binding.openlist_mount_path.rstrip("/")
    folder = payload.folder_path.strip().rstrip("/")
    if not folder.startswith(mount):
        # Allow relative path under mount.
        folder = join_mount(binding.openlist_mount_path, payload.folder_path)
    if not folder.startswith(mount):
        raise HTTPException(400, "文件夹不属于当前绑定网盘")

    try:
        content_rows = await OpenListClient().fs_list_all(folder)
    except OpenListError as exc:
        raise HTTPException(502, f"列目录失败：{exc}") from exc

    video_paths: list[str] = []
    for item in content_rows:
        if bool(item.get("is_dir")):
            continue
        name = str(item.get("name") or "")
        if not is_video_name(name):
            continue
        video_paths.append(f"{folder}/{name}")

    if not video_paths:
        raise HTTPException(400, "该文件夹下没有可导入的视频")

    ordered = sort_video_paths(video_paths)
    series_key = series_key_for(user.id, payload.provider, folder)
    title = folder_title(folder, payload.title)
    items: list[NetdiskImportItemOut] = []
    links: list[UserLinkCourse] = []
    for i, path in enumerate(ordered, start=1):
        link, item = await _upsert_video_link(
            db=db,
            user=user,
            provider=payload.provider,
            path=path,
            series_key=series_key,
            series_title=title,
            episode_index=i,
        )
        items.append(item)
        if link is not None and item.ok:
            links.append(link)

    await db.commit()
    if not links:
        raise HTTPException(502, "导入失败：没有成功写入的视频")
    series_course = CourseOut.model_validate(
        to_series_course_out(links, series_key=series_key, series_title=title)
    )
    return NetdiskImportOut(items=items, series_course=series_course)


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
