"""WeChat Pay App payment (APIv3).

Requires merchant credentials in addition to the Open Platform AppID/Secret:
  WECHAT_MCH_ID, WECHAT_MCH_SERIAL_NO, WECHAT_MCH_API_V3_KEY, WECHAT_MCH_PRIVATE_KEY
"""

from __future__ import annotations

import base64
import hashlib
import json
import time
import uuid
from dataclasses import dataclass
from pathlib import Path

import httpx
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from app.config import settings

_WECHAT_HOST = "https://api.mch.weixin.qq.com"


@dataclass(frozen=True)
class WeChatAppPrepay:
    app_id: str
    partner_id: str
    prepay_id: str
    package_value: str
    nonce_str: str
    timestamp: int
    sign: str
    sign_type: str = "RSA"
    out_trade_no: str = ""


class WeChatPayError(RuntimeError):
    pass


def _load_private_key():
    raw = settings.wechat_mch_private_key.strip().strip('"').strip("'")
    if not raw:
        raise WeChatPayError("未配置 WECHAT_MCH_PRIVATE_KEY")
    # Support single-line env with literal \n escapes.
    if "\\n" in raw and "-----BEGIN" in raw:
        raw = raw.replace("\\n", "\n")
    if raw.startswith("-----BEGIN"):
        pem = raw.encode("utf-8")
    else:
        path = Path(raw)
        if not path.is_file():
            raise WeChatPayError(f"商户私钥文件不存在：{raw}")
        pem = path.read_bytes()
    return serialization.load_pem_private_key(pem, password=None)


def _authorization(method: str, path_with_query: str, body: str) -> str:
    private_key = _load_private_key()
    timestamp = str(int(time.time()))
    nonce = uuid.uuid4().hex
    message = f"{method}\n{path_with_query}\n{timestamp}\n{nonce}\n{body}\n"
    signature = private_key.sign(
        message.encode("utf-8"),
        padding.PKCS1v15(),
        hashes.SHA256(),
    )
    sig_b64 = base64.b64encode(signature).decode("ascii")
    return (
        'WECHATPAY2-SHA256-RSA2048 '
        f'mchid="{settings.wechat_mch_id.strip()}",'
        f'nonce_str="{nonce}",'
        f'signature="{sig_b64}",'
        f'timestamp="{timestamp}",'
        f'serial_no="{settings.wechat_mch_serial_no.strip()}"'
    )


def _app_pay_sign(*, app_id: str, timestamp: str, nonce_str: str, prepay_id: str) -> str:
    private_key = _load_private_key()
    message = f"{app_id}\n{timestamp}\n{nonce_str}\nprepay_id={prepay_id}\n"
    signature = private_key.sign(
        message.encode("utf-8"),
        padding.PKCS1v15(),
        hashes.SHA256(),
    )
    return base64.b64encode(signature).decode("ascii")


def ensure_pay_configured() -> None:
    if not settings.wechat_pay_configured:
        raise WeChatPayError(
            "微信支付商户未配置。请在 .env 填写 WECHAT_MCH_ID / "
            "WECHAT_MCH_SERIAL_NO / WECHAT_MCH_API_V3_KEY / WECHAT_MCH_PRIVATE_KEY。"
        )


def build_out_trade_no(order_id: int) -> str:
    # Max 32 chars; keep stable-ish for retries while unique enough.
    stamp = int(time.time())
    return f"AE{order_id}T{stamp}"[:32]


async def create_app_prepay(
    *,
    order_id: int,
    description: str,
    amount_cents: int,
    out_trade_no: str | None = None,
) -> WeChatAppPrepay:
    ensure_pay_configured()
    if amount_cents <= 0:
        raise WeChatPayError("订单金额无效")
    trade_no = (out_trade_no or build_out_trade_no(order_id)).strip()
    app_id = settings.wechat_app_id.strip()
    path = "/v3/pay/transactions/app"
    payload = {
        "appid": app_id,
        "mchid": settings.wechat_mch_id.strip(),
        "description": (description or f"AcquireEnglish#{order_id}")[:127],
        "out_trade_no": trade_no,
        "notify_url": settings.wechat_pay_notify_url.strip(),
        "amount": {"total": int(amount_cents), "currency": "CNY"},
    }
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Authorization": _authorization("POST", path, body),
    }
    async with httpx.AsyncClient(timeout=20.0) as client:
        resp = await client.post(f"{_WECHAT_HOST}{path}", content=body, headers=headers)
    data = resp.json() if resp.content else {}
    if resp.status_code >= 400:
        raise WeChatPayError(
            f"微信下单失败：{data.get('message') or data.get('code') or resp.status_code}"
        )
    prepay_id = str(data.get("prepay_id") or "").strip()
    if not prepay_id:
        raise WeChatPayError("微信未返回 prepay_id")
    timestamp = int(time.time())
    nonce = uuid.uuid4().hex
    sign = _app_pay_sign(
        app_id=app_id,
        timestamp=str(timestamp),
        nonce_str=nonce,
        prepay_id=prepay_id,
    )
    return WeChatAppPrepay(
        app_id=app_id,
        partner_id=settings.wechat_mch_id.strip(),
        prepay_id=prepay_id,
        package_value="Sign=WXPay",
        nonce_str=nonce,
        timestamp=timestamp,
        sign=sign,
        out_trade_no=trade_no,
    )


def decrypt_resource(resource: dict) -> dict:
    """Decrypt APIv3 notification resource (AES-256-GCM)."""
    api_key = settings.wechat_mch_api_v3_key.strip().encode("utf-8")
    if len(api_key) != 32:
        raise WeChatPayError("WECHAT_MCH_API_V3_KEY 长度必须为 32")
    nonce = str(resource.get("nonce") or "").encode("utf-8")
    associated = str(resource.get("associated_data") or "").encode("utf-8")
    ciphertext_b64 = str(resource.get("ciphertext") or "")
    raw = base64.b64decode(ciphertext_b64)
    if len(raw) < 16:
        raise WeChatPayError("通知密文无效")
    ct, tag = raw[:-16], raw[-16:]
    plain = AESGCM(api_key).decrypt(nonce, ct + tag, associated or None)
    return json.loads(plain.decode("utf-8"))


def parse_out_trade_no_order_id(out_trade_no: str) -> int | None:
    value = (out_trade_no or "").strip()
    if not value.startswith("AE"):
        return None
    body = value[2:]
    if "T" in body:
        body = body.split("T", 1)[0]
    try:
        return int(body)
    except ValueError:
        return None


def resource_fingerprint(resource: dict) -> str:
    blob = json.dumps(resource, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:40]
