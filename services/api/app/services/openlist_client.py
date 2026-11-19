"""Minimal OpenList (AList-compatible) admin + fs client."""

from __future__ import annotations

import json
from typing import Any

import httpx

from app.config import settings

VIDEO_SUFFIXES = (
    ".mp4",
    ".mkv",
    ".webm",
    ".mov",
    ".m4v",
    ".avi",
    ".flv",
    ".ts",
    ".m3u8",
)


class OpenListError(RuntimeError):
    pass


def _base() -> str:
    raw = (settings.openlist_base_url or "").strip().rstrip("/")
    if not raw:
        raise OpenListError("OpenList 未配置（OPENLIST_BASE_URL）")
    return raw


def _public_base() -> str:
    pub = (settings.openlist_public_base or "").strip().rstrip("/")
    return pub or _base()


async def _login(client: httpx.AsyncClient) -> str:
    user = (settings.openlist_admin_user or "admin").strip() or "admin"
    password = (settings.openlist_admin_password or "").strip()
    if not password:
        raise OpenListError("OpenList 未配置（OPENLIST_ADMIN_PASSWORD）")
    resp = await client.post(
        f"{_base()}/api/auth/login",
        json={"username": user, "password": password},
        timeout=20.0,
    )
    data = _unwrap(resp)
    token = str((data or {}).get("token") or "")
    if not token:
        raise OpenListError("OpenList 登录失败：无 token")
    return token


def _unwrap(resp: httpx.Response) -> Any:
    try:
        body = resp.json()
    except Exception as exc:  # noqa: BLE001
        raise OpenListError(f"OpenList 响应无效 HTTP {resp.status_code}") from exc
    code = body.get("code")
    if code not in (200, 201, None) and resp.status_code >= 400:
        raise OpenListError(str(body.get("message") or body.get("msg") or body))
    if isinstance(code, int) and code >= 400:
        raise OpenListError(str(body.get("message") or body.get("msg") or body))
    return body.get("data", body)


def driver_for(provider: str) -> str:
    if provider == "baidu":
        return "BaiduNetdisk"
    if provider == "quark":
        return "Quark"
    raise OpenListError(f"不支持的网盘：{provider}")


def addition_for(provider: str, credential: str) -> str:
    cred = credential.strip()
    if provider == "quark":
        return json.dumps(
            {
                "cookie": cred,
                "root_folder_id": "0",
                "order_by": "none",
                "order_direction": "asc",
            },
            ensure_ascii=False,
        )
    # Baidu: accept cookie (BDUSS/STOKEN) or a bare refresh_token.
    if "BDUSS" in cred.upper() or "STOKEN" in cred.upper() or ";" in cred:
        return json.dumps(
            {
                "cookie": cred,
                "download_api": "official",
            },
            ensure_ascii=False,
        )
    return json.dumps(
        {
            "refresh_token": cred,
            "download_api": "official",
        },
        ensure_ascii=False,
    )


class OpenListClient:
    def __init__(self) -> None:
        self._token: str | None = None

    async def _headers(self, client: httpx.AsyncClient) -> dict[str, str]:
        if not self._token:
            self._token = await _login(client)
        return {"Authorization": self._token}

    async def _request(
        self,
        method: str,
        path: str,
        *,
        json_body: dict[str, Any] | None = None,
    ) -> Any:
        async with httpx.AsyncClient(follow_redirects=True) as client:
            headers = await self._headers(client)
            resp = await client.request(
                method,
                f"{_base()}{path}",
                headers=headers,
                json=json_body,
                timeout=45.0,
            )
            if resp.status_code in (401, 403):
                self._token = await _login(client)
                headers = {"Authorization": self._token}
                resp = await client.request(
                    method,
                    f"{_base()}{path}",
                    headers=headers,
                    json=json_body,
                    timeout=45.0,
                )
            return _unwrap(resp)

    async def list_storages(self) -> list[dict[str, Any]]:
        data = await self._request("GET", "/api/admin/storage/list")
        if isinstance(data, dict):
            content = data.get("content")
            if isinstance(content, list):
                return content
        if isinstance(data, list):
            return data
        return []

    async def create_storage(
        self,
        *,
        mount_path: str,
        provider: str,
        credential: str,
        order: int = 0,
    ) -> int:
        payload = {
            "mount_path": mount_path,
            "order": order,
            "driver": driver_for(provider),
            "cache_expiration": 30,
            "status": "work",
            "addition": addition_for(provider, credential),
            "remark": f"acquireenglish:{provider}",
            "web_proxy": False,
            "webdav_policy": "302_redirect",
            "enable_sign": False,
        }
        data = await self._request("POST", "/api/admin/storage/create", json_body=payload)
        if isinstance(data, dict) and data.get("id") is not None:
            return int(data["id"])
        # Some versions return null data; resolve by mount_path.
        for row in await self.list_storages():
            if str(row.get("mount_path") or "") == mount_path:
                return int(row["id"])
        raise OpenListError("OpenList 创建存储成功但未返回 id")

    async def update_storage(
        self,
        *,
        storage_id: int,
        mount_path: str,
        provider: str,
        credential: str,
        order: int = 0,
    ) -> None:
        payload = {
            "id": storage_id,
            "mount_path": mount_path,
            "order": order,
            "driver": driver_for(provider),
            "cache_expiration": 30,
            "status": "work",
            "addition": addition_for(provider, credential),
            "remark": f"acquireenglish:{provider}",
            "web_proxy": False,
            "webdav_policy": "302_redirect",
            "enable_sign": False,
        }
        await self._request("POST", "/api/admin/storage/update", json_body=payload)

    async def delete_storage(self, storage_id: int) -> None:
        await self._request(
            "POST",
            "/api/admin/storage/delete",
            json_body={"id": storage_id},
        )

    async def fs_list(self, path: str, *, page: int = 1, per_page: int = 100) -> dict[str, Any]:
        data = await self._request(
            "POST",
            "/api/fs/list",
            json_body={
                "path": path,
                "password": "",
                "page": page,
                "per_page": per_page,
                "refresh": False,
            },
        )
        return data if isinstance(data, dict) else {"content": []}

    async def fs_get(self, path: str) -> dict[str, Any]:
        data = await self._request(
            "POST",
            "/api/fs/get",
            json_body={"path": path, "password": ""},
        )
        if not isinstance(data, dict):
            raise OpenListError("OpenList fs/get 无效")
        return data


def is_video_name(name: str) -> bool:
    lower = name.lower()
    return any(lower.endswith(suf) for suf in VIDEO_SUFFIXES)


def join_mount(mount_path: str, rel: str) -> str:
    base = "/" + mount_path.strip().strip("/")
    rel_clean = (rel or "").strip().strip("/")
    if not rel_clean:
        return base
    return f"{base}/{rel_clean}"


def public_raw_url(path: str) -> str:
    """Best-effort public file URL (OpenList /d/ path)."""
    clean = "/" + path.strip().lstrip("/")
    return f"{_public_base()}/d{clean}"
