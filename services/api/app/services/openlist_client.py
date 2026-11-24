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
    if provider == "aliyun":
        return "AliyundriveOpen"
    if provider == "pan115":
        return "115 Cloud"
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
    if provider == "aliyun":
        # AliyundriveOpen expects refresh_token (OAuth).
        token = cred
        if cred.lstrip().startswith("{"):
            try:
                parsed = json.loads(cred)
                token = str(parsed.get("refresh_token") or cred)
            except Exception:  # noqa: BLE001
                token = cred
        return json.dumps(
            {
                "refresh_token": token,
                "root_folder_id": "root",
                "order_by": "name",
                "order_direction": "ASC",
            },
            ensure_ascii=False,
        )
    if provider == "pan115":
        return json.dumps(
            {
                "cookie": cred,
                "root_folder_id": "0",
                "page_size": 1000,
            },
            ensure_ascii=False,
        )
    # Baidu: accept cookie (BDUSS/STOKEN) or a bare refresh_token (OAuth).
    # Empty order_by/order_direction makes OpenList call xpan/file with bad
    # params and Baidu returns errno:2 ("参数错误") on every list.
    baidu_common: dict[str, Any] = {
        "root_folder_path": "/",
        "order_by": "name",
        "order_direction": "asc",
        "download_api": "official",
        "custom_crack_ua": "netdisk",
        "upload_thread": "3",
    }
    if "BDUSS" in cred.upper() or "STOKEN" in cred.upper() or ";" in cred:
        return json.dumps(
            {
                **baidu_common,
                "cookie": cred,
            },
            ensure_ascii=False,
        )
    addition: dict[str, Any] = {
        **baidu_common,
        "refresh_token": cred,
        # Own AppKey tokens must not go through OpenList online renew API.
        "use_online_api": False,
    }
    # Official Open Platform app — required when not using OpenList online API.
    app_key = (settings.baidu_netdisk_app_key or "").strip()
    app_secret = (settings.baidu_netdisk_app_secret or "").strip()
    if app_key and app_secret:
        addition["client_id"] = app_key
        addition["client_secret"] = app_secret
    return json.dumps(addition, ensure_ascii=False)


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

    async def find_storage_by_mount(self, mount_path: str) -> dict[str, Any] | None:
        target = "/" + mount_path.strip().strip("/")
        for row in await self.list_storages():
            raw = str(row.get("mount_path") or "").strip()
            if not raw:
                continue
            normalized = "/" + raw.strip("/")
            if normalized == target:
                return row if isinstance(row, dict) else None
        return None

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
        existing = await self.find_storage_by_mount(mount_path)
        if existing and existing.get("id") is not None:
            return int(existing["id"])
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

    async def create_or_update_storage(
        self,
        *,
        mount_path: str,
        provider: str,
        credential: str,
        storage_id: int | None = None,
        order: int = 0,
    ) -> int:
        """Prefer update when mount_path already exists (avoids UNIQUE constraint)."""
        existing_id = storage_id
        if existing_id is None:
            found = await self.find_storage_by_mount(mount_path)
            if found and found.get("id") is not None:
                existing_id = int(found["id"])
        if existing_id is not None:
            try:
                await self.update_storage(
                    storage_id=existing_id,
                    mount_path=mount_path,
                    provider=provider,
                    credential=credential,
                    order=order,
                )
                return existing_id
            except OpenListError:
                # Stale id — fall through to create / rematch by path.
                found = await self.find_storage_by_mount(mount_path)
                if found and found.get("id") is not None:
                    existing_id = int(found["id"])
                    await self.update_storage(
                        storage_id=existing_id,
                        mount_path=mount_path,
                        provider=provider,
                        credential=credential,
                        order=order,
                    )
                    return existing_id
        try:
            return await self.create_storage(
                mount_path=mount_path,
                provider=provider,
                credential=credential,
                order=order,
            )
        except OpenListError as exc:
            detail = str(exc).lower()
            if "unique" in detail or "constraint" in detail or "2067" in detail:
                found = await self.find_storage_by_mount(mount_path)
                if found and found.get("id") is not None:
                    sid = int(found["id"])
                    await self.update_storage(
                        storage_id=sid,
                        mount_path=mount_path,
                        provider=provider,
                        credential=credential,
                        order=order,
                    )
                    return sid
            raise

    async def delete_storage(self, storage_id: int) -> None:
        await self._request(
            "POST",
            "/api/admin/storage/delete",
            json_body={"id": storage_id},
        )

    async def delete_storage_by_mount(self, mount_path: str) -> bool:
        found = await self.find_storage_by_mount(mount_path)
        if not found or found.get("id") is None:
            return False
        await self.delete_storage(int(found["id"]))
        return True

    async def baidu_account_info(self, mount_path: str) -> dict[str, Any] | None:
        """Resolve bound Baidu passport nickname / VIP via OpenList token."""
        found = await self.find_storage_by_mount(mount_path)
        if not found:
            return None
        raw_add = found.get("addition") or ""
        try:
            addition = json.loads(raw_add) if isinstance(raw_add, str) else (raw_add or {})
        except Exception:  # noqa: BLE001
            return None
        if not isinstance(addition, dict):
            return None
        token = str(
            addition.get("AccessToken")
            or addition.get("access_token")
            or ""
        ).strip()
        if not token:
            return None
        try:
            async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
                resp = await client.get(
                    "https://pan.baidu.com/rest/2.0/xpan/nas",
                    params={"method": "uinfo", "access_token": token},
                )
                data = resp.json()
        except Exception:  # noqa: BLE001
            return None
        if not isinstance(data, dict) or int(data.get("errno") or 0) != 0:
            return None
        vip = int(data.get("vip_type") or 0)
        return {
            "baidu_name": str(data.get("baidu_name") or "").strip(),
            "netdisk_name": str(data.get("netdisk_name") or "").strip(),
            "uk": data.get("uk"),
            "vip_type": vip,
            "is_vip": vip > 0,
        }

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

    async def fs_list_all(
        self, path: str, *, per_page: int = 200, max_pages: int = 50
    ) -> list[dict[str, Any]]:
        """Paginate OpenList fs/list until empty or max_pages."""
        items: list[dict[str, Any]] = []
        for page in range(1, max_pages + 1):
            data = await self.fs_list(path, page=page, per_page=per_page)
            content = data.get("content")
            if not isinstance(content, list) or not content:
                break
            for row in content:
                if isinstance(row, dict):
                    items.append(row)
            total = data.get("total")
            if isinstance(total, int) and len(items) >= total:
                break
            if len(content) < per_page:
                break
        return items

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
