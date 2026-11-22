"""Recognize public cloud-drive share URLs without fetching untrusted links."""

from urllib.parse import urlparse

_HOSTS = {
    "pan.baidu.com": "baidu",
    "yun.baidu.com": "baidu",
    "pan.quark.cn": "quark",
    "www.alipan.com": "aliyun",
    "alipan.com": "aliyun",
    "www.aliyundrive.com": "aliyun",
    "aliyundrive.com": "aliyun",
    "115.com": "pan115",
    "www.115.com": "pan115",
}


def netdisk_share_provider(raw: str) -> str | None:
    """Return the known provider; reject embedded credentials and lookalike hosts."""
    parsed = urlparse(raw.strip())
    if parsed.scheme != "https" or parsed.username or parsed.password:
        return None
    host = (parsed.hostname or "").lower().rstrip(".")
    if host not in _HOSTS or not parsed.path.strip("/"):
        return None
    return _HOSTS[host]
