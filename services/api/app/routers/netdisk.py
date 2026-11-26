"""Personal netdisk import via OpenList (own drive only — no share links)."""

from __future__ import annotations

import asyncio
import hashlib
import re
from pathlib import PurePosixPath
from typing import Any, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import HTMLResponse, RedirectResponse
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.deps import get_current_user
from app.models import User, UserLinkCourse, UserNetdiskBinding
from app.schemas import CourseOut
from app.services import baidu_netdisk_oauth as baidu_oauth
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
from app.services.netdisk_embedded_subs import extract_embedded_softsubs
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
    baidu_oauth_configured: bool = False
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
    load_sidecars: bool = True,
    verify_remote: bool = True,
    sidecar_dir_cache: dict[str, list[str]] | None = None,
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
    title = path.rsplit("/", 1)[-1]
    client = OpenListClient()
    meta: dict[str, Any] = {}
    if verify_remote:
        try:
            meta = await client.fs_get(path)
            title = str(meta.get("name") or title)
        except OpenListError as exc:
            return None, NetdiskImportItemOut(
                path=path,
                course_id="",
                title="",
                watch_url="",
                ok=False,
                error=str(exc),
            )

    external_id = _external_id(provider, path)
    source = f"{provider}_netdisk"

    async def _fetch_existing() -> UserLinkCourse | None:
        result = await db.execute(
            select(UserLinkCourse).where(
                UserLinkCourse.user_id == user.id,
                UserLinkCourse.source == source,
                UserLinkCourse.external_id == external_id,
            )
        )
        return result.scalar_one_or_none()

    link = await _fetch_existing()
    if link is None:
        # SAVEPOINT: concurrent/partial re-import may race the unique index.
        try:
            async with db.begin_nested():
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
                await db.flush()
        except IntegrityError:
            link = await _fetch_existing()
            if link is None:
                return None, NetdiskImportItemOut(
                    path=path,
                    course_id="",
                    title=title,
                    watch_url="",
                    ok=False,
                    error="写入冲突且无法读回已有记录",
                )
    link.title = title[:512]
    link.watch_url = path[:1024]

    if series_key:
        link.series_key = series_key
        link.series_title = (series_title or link.series_title or title)[:512]
        link.episode_index = episode_index

    if load_sidecars:
        try:
            sidecars = await load_sidecars_for_video(
                client, path, dir_cache=sidecar_dir_cache
            )
        except Exception:  # noqa: BLE001
            sidecars = {}
        if sidecars.get("en"):
            link.subtitle_en_srt = sidecars["en"]
        if sidecars.get("zh"):
            link.subtitle_zh_srt = sidecars["zh"]
        # Fill gaps from MKV/MP4 embedded text softsubs (skip PGS/VobSub bitmap).
        need_en = not (link.subtitle_en_srt or "").strip()
        need_zh = not (link.subtitle_zh_srt or "").strip()
        if need_en or need_zh:
            try:
                embedded = await extract_embedded_softsubs(client, path)
            except Exception:  # noqa: BLE001
                embedded = {}
            if need_en and embedded.get("en"):
                link.subtitle_en_srt = embedded["en"]
            if need_zh and embedded.get("zh"):
                link.subtitle_zh_srt = embedded["zh"]

        # Before scheduling costly ASR, try the exact media fingerprint used by
        # ausaki/subfinder. OpenList supports Range, so this reads only 16 KiB.
        if not (link.subtitle_en_srt or "").strip():
            try:
                from app.services.online_subtitles import (
                    compute_subfinder_hash,
                    get_shared_media_subtitle,
                    search_shooter,
                    store_shared_media_subtitle,
                )

                if not meta:
                    meta = await client.fs_get(path)
                raw_url = str(meta.get("raw_url") or "").strip() or public_raw_url(path)
                file_size = int(meta.get("size") or 0)
                file_hash = await compute_subfinder_hash(raw_url, file_size)
                cached = await get_shared_media_subtitle(
                    db, file_hash=file_hash, language="en"
                )
                if cached is not None:
                    cached.hit_count = int(cached.hit_count or 0) + 1
                    link.subtitle_en_srt = cached.subtitle_srt
                else:
                    matches = await search_shooter(
                        file_hash=file_hash,
                        filename=title,
                        languages=("en",),
                    )
                    if matches:
                        match = matches[0]
                        cached = await store_shared_media_subtitle(
                            db,
                            file_hash=file_hash,
                            file_size=file_size,
                            duration_sec=None,
                            title=series_title or title,
                            language="en",
                            subtitle_srt=match.srt,
                            source_ref=match.source_ref,
                            uploader_user_id=user.id,
                            episode=episode_index,
                        )
                        link.subtitle_en_srt = cached.subtitle_srt
            except Exception:  # Online subtitles are best-effort; import must continue.
                pass

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
        account: dict[str, Any] | None = None
        if client is not None:
            try:
                await client.fs_list(row.openlist_mount_path, page=1, per_page=1)
            except OpenListError as exc:
                healthy = False
                error = str(exc)
            if row.provider == "baidu":
                try:
                    account = await client.baidu_account_info(row.openlist_mount_path)
                except Exception:  # noqa: BLE001
                    account = None
        providers.append(
            {
                "provider": row.provider,
                "bound": True,
                "mount_path": row.openlist_mount_path,
                "updated_at": row.updated_at.isoformat() if row.updated_at else None,
                "healthy": healthy,
                "error": error,
                "label": _PROVIDER_LABEL.get(row.provider, row.provider),
                "account": account,
            }
        )
    return NetdiskStatusOut(
        openlist_configured=settings.openlist_configured,
        baidu_oauth_configured=settings.baidu_netdisk_oauth_configured,
        providers=providers,
    )


async def _upsert_binding(
    *,
    db: AsyncSession,
    user_id: int,
    provider: Provider,
    credential: str,
    access_token: str = "",
    replace_mount: bool = False,
) -> UserNetdiskBinding:
    mount = _mount_for(user_id, provider)
    client = OpenListClient()
    result = await db.execute(
        select(UserNetdiskBinding).where(
            UserNetdiskBinding.user_id == user_id,
            UserNetdiskBinding.provider == provider,
        )
    )
    row = result.scalar_one_or_none()
    # OAuth rebind: delete+recreate so OpenList cannot keep a stale AccessToken
    # from the previous Baidu passport on the same mount_path.
    storage_id = await client.create_or_update_storage(
        mount_path=mount,
        provider=provider,
        credential=credential,
        access_token=access_token,
        storage_id=None if row is None else row.openlist_storage_id,
        replace_existing=replace_mount or bool(access_token),
    )
    if row is None:
        row = UserNetdiskBinding(
            user_id=user_id,
            provider=provider,
            credential_enc=encrypt_credential(credential),
            openlist_mount_path=mount,
            openlist_storage_id=storage_id,
        )
        db.add(row)
    else:
        row.credential_enc = encrypt_credential(credential)
        row.openlist_mount_path = mount
        row.openlist_storage_id = storage_id
    await db.commit()
    await db.refresh(row)
    return row


def _oauth_result_html(*, ok: bool, message: str) -> HTMLResponse:
    color = "#16a34a" if ok else "#dc2626"
    title = "授权成功" if ok else "授权失败"
    body = f"""<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>{title} · 爱快英语</title>
<style>
body{{font-family:system-ui,-apple-system,sans-serif;background:#0f172a;color:#e2e8f0;
display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0;padding:24px}}
.card{{max-width:420px;background:#1e293b;border-radius:16px;padding:28px;text-align:center}}
h1{{color:{color};font-size:22px;margin:0 0 12px}}
p{{line-height:1.6;margin:0;color:#cbd5e1}}
</style></head><body><div class="card"><h1>{title}</h1><p>{message}</p></div></body></html>"""
    return HTMLResponse(body, status_code=200 if ok else 400)


@router.get("/baidu/oauth/start")
async def baidu_oauth_start(
    mode: str = Query(
        "password",
        description="password=账号密码/短信登录（推荐）；qrcode=百度App扫码",
    ),
    user: User = Depends(get_current_user),
) -> dict[str, Any]:
    """Return Baidu authorize URL for the logged-in Acquire user."""
    _require_openlist()
    if not settings.baidu_netdisk_oauth_configured:
        raise HTTPException(
            503,
            "服务端尚未配置百度网盘开放平台 APP KEY，请联系管理员",
        )
    use_qr = mode.strip().lower() in {"qr", "qrcode", "scan"}
    state = baidu_oauth.mint_oauth_state(user.id)
    try:
        url = baidu_oauth.build_authorize_url(state=state, use_qrcode=use_qr)
    except RuntimeError as exc:
        raise HTTPException(503, str(exc)) from exc
    return {
        "authorize_url": url,
        "state": state,
        "mode": "qrcode" if use_qr else "password",
        "expires_in": 15 * 60,
        "hint": (
            "请用百度 App 扫码授权；扫码会绑定手机里当前登录的百度号"
            if use_qr
            else "请用无痕窗口打开，登录名填百度用户名（如 linghusgc）+密码；"
            "勿扫码、勿用手机号短信（一号两护照会进默认号）"
        ),
    }


@router.get("/baidu/oauth/callback")
async def baidu_oauth_callback(
    code: str | None = Query(None),
    state: str | None = Query(None),
    error: str | None = Query(None),
    error_description: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
) -> HTMLResponse:
    """Baidu redirects here after QR / password authorize."""
    if error:
        detail = (error_description or error or "用户取消或授权失败").strip()
        return _oauth_result_html(ok=False, message=detail)
    if not code or not state:
        return _oauth_result_html(ok=False, message="缺少 code 或 state")
    user_id = baidu_oauth.parse_oauth_state(state)
    if user_id is None:
        return _oauth_result_html(ok=False, message="授权已过期，请返回 App 重新发起")
    if not settings.openlist_configured:
        return _oauth_result_html(ok=False, message="OpenList 未启用，无法完成绑定")
    account_hint = ""
    try:
        tokens = await baidu_oauth.exchange_code_for_tokens(code)
        # Identity from Baidu OAuth token itself — proves which passport authorized.
        oauth_info = await baidu_oauth.fetch_uinfo(tokens.get("access_token") or "")
        await _upsert_binding(
            db=db,
            user_id=user_id,
            provider="baidu",
            credential=tokens["refresh_token"],
            access_token=str(tokens.get("access_token") or ""),
            replace_mount=True,
        )
        if oauth_info:
            name = str(
                oauth_info.get("baidu_name") or oauth_info.get("netdisk_name") or ""
            ).strip()
            vip = "会员" if oauth_info.get("is_vip") else "非会员"
            if name:
                account_hint = (
                    f"百度本次授权身份：{name}（{vip}）。"
                    f"这是百度返回的登录身份，不是爱快缓存。"
                    f"若不是目标昵称，请无痕窗口用「用户名+密码」重授（勿扫码、勿手机号短信）。"
                )
    except OpenListError as exc:
        return _oauth_result_html(ok=False, message=f"挂载网盘失败：{exc}")
    except Exception as exc:  # noqa: BLE001
        return _oauth_result_html(ok=False, message=str(exc)[:240])
    msg = "百度网盘已绑定。请返回爱快英语 App 刷新后浏览文件。"
    if account_hint:
        msg = f"{msg}\n{account_hint}"
    return _oauth_result_html(ok=True, message=msg)


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

    try:
        row = await _upsert_binding(
            db=db,
            user_id=user.id,
            provider=provider,
            credential=credential,
        )
    except OpenListError as exc:
        await db.rollback()
        raise HTTPException(502, f"OpenList 绑定失败：{exc}") from exc

    return {
        "ok": True,
        "provider": provider,
        "mount_path": row.openlist_mount_path,
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
    if settings.openlist_configured:
        client = OpenListClient()
        deleted = False
        if row.openlist_storage_id is not None:
            try:
                await client.delete_storage(row.openlist_storage_id)
                deleted = True
            except OpenListError:
                deleted = False
        if not deleted:
            try:
                await client.delete_storage_by_mount(
                    row.openlist_mount_path or _mount_for(user.id, provider)
                )
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
        detail = str(exc)
        lowered = detail.lower()
        if "object not found" in lowered or "not found" in lowered:
            raise HTTPException(
                404,
                "目录不存在或无权访问，请返回上一级再试",
            ) from exc
        raise HTTPException(502, f"列目录失败：{detail}") from exc

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


async def _resolve_import_folder(
    *,
    db: AsyncSession,
    user: User,
    provider: Provider,
    folder_path: str,
) -> tuple[UserNetdiskBinding, str]:
    binding = await _binding_or_400(db, user.id, provider)
    mount = binding.openlist_mount_path.rstrip("/")
    folder = folder_path.strip().rstrip("/")
    if not folder.startswith(mount):
        folder = join_mount(binding.openlist_mount_path, folder_path)
    if not folder.startswith(mount):
        raise HTTPException(400, "文件夹不属于当前绑定网盘")
    return binding, folder


async def _run_series_import_job(
    *,
    job_id: str,
    user_id: int,
    provider: Provider,
    folder: str,
    title_override: str | None,
) -> None:
    from app.database import SessionLocal
    from app.services import netdisk_import_jobs as jobs

    await jobs.update_job(
        job_id,
        status="running",
        phase="scanning",
        message="正在扫描网盘视频…",
    )
    try:
        video_paths = await OpenListClient().fs_list_video_paths_recursive(
            folder,
            max_depth=3,
            max_videos=500,
        )
    except OpenListError as exc:
        await jobs.update_job(
            job_id,
            status="error",
            phase="error",
            error=f"列目录失败：{exc}",
            message=str(exc),
        )
        return

    if not video_paths:
        await jobs.update_job(
            job_id,
            status="error",
            phase="error",
            error="该文件夹及子文件夹下没有可导入的视频",
            message="没有可导入的视频",
        )
        return

    ordered = list(dict.fromkeys(sort_video_paths(video_paths)))
    total = len(ordered)
    series_key = series_key_for(user_id, provider, folder)
    title = folder_title(folder, title_override)
    await jobs.update_job(
        job_id,
        phase="importing",
        total=total,
        done=0,
        message=f"找到 {total} 个视频，开始写入（含外挂 .srt）…",
    )

    items: list[dict[str, Any]] = []
    ok_n = 0
    failed_n = 0
    sidecar_dir_cache: dict[str, list[str]] = {}
    try:
        async with SessionLocal() as db:
            user = await db.get(User, user_id)
            if user is None:
                await jobs.update_job(
                    job_id,
                    status="error",
                    phase="error",
                    error="用户不存在",
                    message="用户不存在",
                )
                return
            links: list[UserLinkCourse] = []
            for i, path in enumerate(ordered, start=1):
                name = path.rsplit("/", 1)[-1]
                # Publish progress before the slow per-file work so the App can poll.
                await jobs.update_job(
                    job_id,
                    phase="importing",
                    done=i - 1,
                    total=total,
                    ok=ok_n,
                    failed=failed_n,
                    current=name,
                    message=f"写入中 {i}/{total} · 外挂/内嵌字幕 · {name}",
                )
                # Yield so concurrent GET /import-jobs can run between files.
                await asyncio.sleep(0)
                link, item = await _upsert_video_link(
                    db=db,
                    user=user,
                    provider=provider,
                    path=path,
                    series_key=series_key,
                    series_title=title,
                    episode_index=i,
                    # Reuse folder listing; attach sibling .srt (no ASR).
                    load_sidecars=True,
                    verify_remote=False,
                    sidecar_dir_cache=sidecar_dir_cache,
                )
                items.append(item.model_dump())
                if link is not None and item.ok:
                    links.append(link)
                    ok_n += 1
                else:
                    failed_n += 1
                sub_bit = ""
                if item.ok:
                    flags = []
                    if item.has_en:
                        flags.append("英字")
                    if item.has_zh:
                        flags.append("中字")
                    if flags:
                        sub_bit = " · " + "+".join(flags)
                await jobs.update_job(
                    job_id,
                    done=i,
                    ok=ok_n,
                    failed=failed_n,
                    current=name,
                    message=f"已写入 {i}/{total} · 成功 {ok_n}{sub_bit}",
                )
                if i % 5 == 0:
                    await db.commit()
                    await asyncio.sleep(0)
            await db.commit()
            if not links:
                await jobs.update_job(
                    job_id,
                    status="error",
                    phase="error",
                    error="导入失败：没有成功写入的视频",
                    message="没有成功写入的视频",
                    result={"items": items},
                )
                return
            series_course = CourseOut.model_validate(
                to_series_course_out(
                    links, series_key=series_key, series_title=title
                )
            )
            await jobs.update_job(
                job_id,
                status="done",
                phase="done",
                done=total,
                ok=ok_n,
                failed=failed_n,
                message=f"完成：成功 {ok_n}，失败 {failed_n}",
                result={
                    "items": items,
                    "series_course": series_course.model_dump(),
                },
            )
    except Exception as exc:  # noqa: BLE001
        await jobs.update_job(
            job_id,
            status="error",
            phase="error",
            error=str(exc)[:500],
            message=f"导入异常：{exc}",
        )


@router.post("/import-series")
async def import_netdisk_series(
    payload: NetdiskImportSeriesIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    """Start async series import; poll ``GET /import-jobs/{id}`` for progress."""
    from app.services import netdisk_import_jobs as jobs

    _require_openlist()
    _, folder = await _resolve_import_folder(
        db=db,
        user=user,
        provider=payload.provider,
        folder_path=payload.folder_path,
    )
    job_id, created = await jobs.create_job(
        user_id=user.id,
        provider=payload.provider,
        folder=folder,
    )
    if created:
        asyncio.create_task(
            _run_series_import_job(
                job_id=job_id,
                user_id=user.id,
                provider=payload.provider,
                folder=folder,
                title_override=payload.title,
            )
        )
    existing = await jobs.get_job(job_id)
    return {
        "job_id": job_id,
        "status": (existing or {}).get("status") or ("queued" if created else "running"),
        "message": (existing or {}).get("message")
        or ("已开始导入，请轮询进度" if created else "已有导入任务进行中"),
        "poll_path": f"/api/netdisk/import-jobs/{job_id}",
        "resumed": not created,
    }


@router.get("/import-jobs/{job_id}")
async def get_netdisk_import_job(
    job_id: str,
    user: User = Depends(get_current_user),
) -> dict[str, Any]:
    from app.services import netdisk_import_jobs as jobs

    job = await jobs.get_job(job_id)
    if job is None or int(job.get("user_id") or 0) != user.id:
        raise HTTPException(404, "导入任务不存在")
    return job


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
