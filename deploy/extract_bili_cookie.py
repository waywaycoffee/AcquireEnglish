"""Read bilibili SESSDATA from local Edge cookie DB (read-only)."""
from __future__ import annotations

import os
import shutil
import sqlite3
import sys
import tempfile
from pathlib import Path

try:
    import win32crypt  # type: ignore
except ImportError:
    win32crypt = None

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except ImportError:
    AESGCM = None  # type: ignore


def _get_edge_key() -> bytes | None:
    local_state = (
        Path(os.environ["LOCALAPPDATA"])
        / "Microsoft"
        / "Edge"
        / "User Data"
        / "Local State"
    )
    if not local_state.exists() or win32crypt is None:
        return None
    import json
    import base64

    data = json.loads(local_state.read_text(encoding="utf-8"))
    enc = base64.b64decode(data["os_crypt"]["encrypted_key"])
    assert enc.startswith(b"DPAPI")
    return win32crypt.CryptUnprotectData(enc[5:], None, None, None, 0)[1]


def _decrypt(value: bytes, key: bytes | None) -> str:
    if not value:
        return ""
    if value.startswith(b"v10") or value.startswith(b"v20"):
        if key is None or AESGCM is None:
            return ""
        nonce = value[3:15]
        cipher = value[15:]
        return AESGCM(key).decrypt(nonce, cipher, None).decode("utf-8", "ignore")
    if win32crypt is None:
        return ""
    try:
        return win32crypt.CryptUnprotectData(value, None, None, None, 0)[1].decode(
            "utf-8", "ignore"
        )
    except Exception:
        return ""


def main() -> int:
    src = (
        Path(os.environ["LOCALAPPDATA"])
        / "Microsoft"
        / "Edge"
        / "User Data"
        / "Default"
        / "Network"
        / "Cookies"
    )
    if not src.exists():
        print("NO_COOKIE_DB", file=sys.stderr)
        return 1

    tmp = Path(tempfile.gettempdir()) / "edge_cookies_ro.db"
    # Prefer file copy; if locked, try sqlite URI readonly.
    conn = None
    try:
        shutil.copy2(src, tmp)
        conn = sqlite3.connect(str(tmp))
    except Exception:
        try:
            uri = f"file:{src.as_posix()}?mode=ro&immutable=1"
            conn = sqlite3.connect(uri, uri=True)
        except Exception as exc:
            print(f"OPEN_FAIL {exc}", file=sys.stderr)
            return 2

    key = _get_edge_key()
    cur = conn.execute(
        "SELECT name, host_key, encrypted_value, value FROM cookies "
        "WHERE host_key LIKE '%bilibili.com%' "
        "AND name IN ('SESSDATA','bili_jct','DedeUserID','buvid3')"
    )
    found: dict[str, str] = {}
    for name, host, enc, plain in cur.fetchall():
        val = plain or _decrypt(enc or b"", key)
        if val:
            found[name] = val
            print(f"FOUND {name} host={host} len={len(val)}")
    conn.close()
    if "SESSDATA" not in found:
        print("NO_SESSDATA")
        return 3
    cookie = "; ".join(
        f"{k}={found[k]}"
        for k in ("SESSDATA", "bili_jct", "DedeUserID", "buvid3")
        if k in found
    )
    out = Path(tempfile.gettempdir()) / "bili_cookie.txt"
    out.write_text(cookie, encoding="utf-8")
    print(f"WROTE {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
