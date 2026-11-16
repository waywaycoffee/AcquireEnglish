"""Aliyun Dysmsapi SendSms (RPC signature, no SDK required)."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
import time
import urllib.parse
from datetime import datetime, timezone

import httpx

from app.config import settings


def aliyun_sms_configured() -> bool:
    return bool(
        settings.aliyun_sms_access_key_id.strip()
        and settings.aliyun_sms_access_key_secret.strip()
        and settings.aliyun_sms_sign_name.strip()
        and settings.aliyun_sms_template_code.strip()
    )


def _phone_for_aliyun(phone: str) -> str:
    """Dysmsapi expects mainland numbers as 11 digits (no +86)."""
    digits = "".join(ch for ch in phone if ch.isdigit())
    if digits.startswith("86") and len(digits) == 13:
        return digits[2:]
    return digits


def _percent_encode(value: str) -> str:
    return urllib.parse.quote(value, safe="~")


def _sign(params: dict[str, str], secret: str) -> str:
    ordered = sorted(params.items())
    canonical = "&".join(
        f"{_percent_encode(k)}={_percent_encode(v)}" for k, v in ordered
    )
    string_to_sign = f"GET&{_percent_encode('/')}&{_percent_encode(canonical)}"
    digest = hmac.new(
        (secret + "&").encode("utf-8"),
        string_to_sign.encode("utf-8"),
        hashlib.sha1,
    ).digest()
    return base64.b64encode(digest).decode("utf-8")


async def send_aliyun_sms(*, phone: str, code: str) -> None:
    if not aliyun_sms_configured():
        raise RuntimeError("未配置阿里云短信参数")

    phone_number = _phone_for_aliyun(phone)
    if not phone_number:
        raise RuntimeError("手机号无效")

    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    params: dict[str, str] = {
        "AccessKeyId": settings.aliyun_sms_access_key_id.strip(),
        "Action": "SendSms",
        "Format": "JSON",
        "PhoneNumbers": phone_number,
        "RegionId": settings.aliyun_sms_region.strip() or "cn-hangzhou",
        "SignName": settings.aliyun_sms_sign_name.strip(),
        "SignatureMethod": "HMAC-SHA1",
        "SignatureNonce": f"{time.time_ns()}-{secrets.token_hex(8)}",
        "SignatureVersion": "1.0",
        "TemplateCode": settings.aliyun_sms_template_code.strip(),
        "TemplateParam": json.dumps({"code": code}, ensure_ascii=False),
        "Timestamp": timestamp,
        "Version": "2017-05-25",
    }
    params["Signature"] = _sign(params, settings.aliyun_sms_access_key_secret.strip())
    url = "https://dysmsapi.aliyuncs.com/?" + urllib.parse.urlencode(params)

    async with httpx.AsyncClient(timeout=20) as client:
        response = await client.get(url)
        response.raise_for_status()
        data = response.json()

    if str(data.get("Code") or "") != "OK":
        message = data.get("Message") or data.get("Code") or "unknown"
        raise RuntimeError(f"阿里云短信失败：{message}")
