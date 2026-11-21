"""Pull platform-side spend from vendor billing APIs using keys in .env / settings.

Never returns raw secrets — only fingerprints, product lines, and amounts.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timezone
from typing import Any

from app.config import settings
from app.services.api_usage import fingerprint_key


def _env(name: str) -> str:
    return (os.getenv(name, "") or "").strip()


def _settings_or_env(*names: str) -> str:
    for n in names:
        # settings field style: DASHSCOPE_API_KEY -> dashscope_api_key
        attr = n.lower()
        if hasattr(settings, attr):
            v = getattr(settings, attr)
            if isinstance(v, str) and v.strip():
                return v.strip()
        v = _env(n)
        if v:
            return v
    return ""


def discover_keys() -> list[dict[str, Any]]:
    """Map configured platform credentials (presence only)."""
    catalog = [
        {
            "id": "dashscope",
            "label": "阿里云百炼 / DashScope",
            "env": "DASHSCOPE_API_KEY",
            "value": _settings_or_env("DASHSCOPE_API_KEY", "dashscope_api_key"),
            "usage": "LLM / ASR / TTS / VL",
            "billing": "aliyun_bss:sfm",
        },
        {
            "id": "aliyun_sms",
            "label": "阿里云短信",
            "env": "ALIYUN_SMS_ACCESS_KEY_ID",
            "value": _settings_or_env("ALIYUN_SMS_ACCESS_KEY_ID", "aliyun_sms_access_key_id"),
            "secret_set": bool(
                _settings_or_env(
                    "ALIYUN_SMS_ACCESS_KEY_SECRET", "aliyun_sms_access_key_secret"
                )
            ),
            "usage": "登录验证码 SMS",
            "billing": "aliyun_bss:dysms",
        },
        {
            "id": "aliyun_ecs",
            "label": "阿里云 ECS / 云盘（复用 AK）",
            "env": "ALIYUN_ECS_ACCESS_KEY_ID|ALIYUN_SMS_ACCESS_KEY_ID",
            "value": _settings_or_env(
                "ALIYUN_ECS_ACCESS_KEY_ID",
                "ALIYUN_ACCESS_KEY_ID",
                "ALIYUN_SMS_ACCESS_KEY_ID",
                "aliyun_ecs_access_key_id",
                "aliyun_sms_access_key_id",
            ),
            "usage": "主机与云盘监控 / 账单",
            "billing": "aliyun_bss:ecs",
        },
        {
            "id": "tencent_soe",
            "label": "腾讯云智聆口语评测 SOE",
            "env": "TENCENT_SOE_SECRET_ID",
            "value": _settings_or_env("TENCENT_SOE_SECRET_ID", "tencent_soe_secret_id"),
            "secret_set": bool(
                _settings_or_env("TENCENT_SOE_SECRET_KEY", "tencent_soe_secret_key")
            ),
            "usage": "跟读 / 发音评测",
            "billing": "tencent_billing:soe",
        },
        {
            "id": "livekit",
            "label": "LiveKit Cloud",
            "env": "LIVEKIT_API_KEY",
            "value": _settings_or_env("LIVEKIT_API_KEY", "livekit_api_key"),
            "secret_set": bool(
                _settings_or_env("LIVEKIT_API_SECRET", "livekit_api_secret")
            ),
            "extra": {"url": _settings_or_env("LIVEKIT_URL", "livekit_url")},
            "usage": "实时口语房间",
            "billing": "livekit_cloud",
        },
        {
            "id": "deepseek",
            "label": "DeepSeek",
            "env": "DEEPSEEK_API_KEY",
            "value": _env("DEEPSEEK_API_KEY"),
            "usage": "写作批改 LLM（可选）",
            "billing": "deepseek_portal",
        },
        {
            "id": "openai",
            "label": "OpenAI",
            "env": "OPENAI_API_KEY",
            "value": _env("OPENAI_API_KEY"),
            "usage": "写作批改 LLM（可选）",
            "billing": "openai_usage",
        },
    ]
    out: list[dict[str, Any]] = []
    for item in catalog:
        val = item.get("value") or ""
        present = bool(val)
        fp, label = fingerprint_key(val) if present else ("", "")
        out.append(
            {
                "id": item["id"],
                "label": item["label"],
                "env": item["env"],
                "usage": item["usage"],
                "billing": item["billing"],
                "configured": present,
                "key_fingerprint": fp,
                "key_label": label,
                "secret_set": bool(item.get("secret_set", present)),
                "extra": item.get("extra") or {},
            }
        )
    return out


def _aliyun_bss_call(action: str, extra: dict[str, str], *, ak: str, sk: str) -> dict[str, Any]:
    params = {
        "Format": "JSON",
        "Version": "2017-12-14",
        "AccessKeyId": ak,
        "SignatureMethod": "HMAC-SHA1",
        "Timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "SignatureVersion": "1.0",
        "SignatureNonce": str(uuid.uuid4()),
        "Action": action,
    }
    params.update(extra)
    qs = "&".join(
        f"{urllib.parse.quote(k, safe='')}={urllib.parse.quote(params[k], safe='')}"
        for k in sorted(params)
    )
    string_to_sign = "GET&%2F&" + urllib.parse.quote(qs, safe="")
    dig = hmac.new((sk + "&").encode(), string_to_sign.encode(), hashlib.sha1).digest()
    params["Signature"] = base64.b64encode(dig).decode()
    url = "https://business.aliyuncs.com/?" + urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(url, timeout=25) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read().decode())
        except Exception:
            return {"Success": False, "error": str(e)}
    except Exception as e:  # noqa: BLE001
        return {"Success": False, "error": str(e)}


def _bill_items(resp: dict[str, Any]) -> list[dict[str, Any]]:
    data = resp.get("Data") or {}
    items = data.get("Items")
    if isinstance(items, dict):
        items = items.get("Item") or []
    if not isinstance(items, list):
        return []
    return [x for x in items if isinstance(x, dict)]


def fetch_aliyun_bss(month: str | None = None) -> dict[str, Any]:
    ak = _settings_or_env(
        "ALIYUN_ECS_ACCESS_KEY_ID",
        "ALIYUN_ACCESS_KEY_ID",
        "ALIYUN_SMS_ACCESS_KEY_ID",
        "aliyun_sms_access_key_id",
    )
    sk = _settings_or_env(
        "ALIYUN_ECS_ACCESS_KEY_SECRET",
        "ALIYUN_ACCESS_KEY_SECRET",
        "ALIYUN_SMS_ACCESS_KEY_SECRET",
        "aliyun_sms_access_key_secret",
    )
    out: dict[str, Any] = {
        "ok": False,
        "provider": "aliyun_bss",
        "billing_cycle": month
        or datetime.now(tz=timezone.utc).strftime("%Y-%m"),
        "balance_cny": None,
        "overview": [],
        "products": {},
        "app_relevant": [],
        "error": "",
    }
    if not ak or not sk:
        out["error"] = "未配置阿里云 AccessKey，无法拉取 BSS 账单"
        return out

    cycle = out["billing_cycle"]
    bal = _aliyun_bss_call("QueryAccountBalance", {}, ak=ak, sk=sk)
    if bal.get("Success") or bal.get("Code") in ("200", "Success", 200):
        data = bal.get("Data") or {}
        try:
            out["balance_cny"] = float(data.get("AvailableAmount") or 0)
        except (TypeError, ValueError):
            out["balance_cny"] = None

    overview = _aliyun_bss_call("QueryBillOverview", {"BillingCycle": cycle}, ak=ak, sk=sk)
    ov_items = _bill_items(overview)
    # Deduplicate by ProductCode+ProductName summing payment
    merged: dict[str, dict[str, Any]] = {}
    for it in ov_items:
        key = f"{it.get('ProductCode')}|{it.get('ProductName')}"
        row = merged.setdefault(
            key,
            {
                "product_code": it.get("ProductCode"),
                "product_name": it.get("ProductName"),
                "payment_cny": 0.0,
                "pretax_cny": 0.0,
            },
        )
        row["payment_cny"] += float(it.get("PaymentAmount") or 0)
        row["pretax_cny"] += float(it.get("PretaxAmount") or 0)
    out["overview"] = sorted(merged.values(), key=lambda x: x["payment_cny"], reverse=True)

    # App-relevant product codes
    wanted = {
        "sfm": "阿里云百炼（DashScope / 模型调用）",
        "dysms": "阿里云短信",
        "dysms_system": "阿里云国内短信",
        "ecs": "阿里云 ECS",
        "disk": "阿里云云盘",
        "snapshot": "快照",
    }
    relevant_codes = set()
    for code, label in wanted.items():
        resp = _aliyun_bss_call(
            "DescribeInstanceBill",
            {
                "BillingCycle": cycle,
                "ProductCode": code,
                "MaxResults": "100",
                "IsBillingItem": "true",
            },
            ak=ak,
            sk=sk,
        )
        rows = _bill_items(resp)
        lines = []
        pretax = 0.0
        for r in rows:
            amt = float(r.get("PretaxAmount") or r.get("PaymentAmount") or 0)
            pretax += amt
            lines.append(
                {
                    "product_name": r.get("ProductName"),
                    "detail": r.get("ProductDetail") or r.get("BillingItem") or "",
                    "instance_id": str(r.get("InstanceID") or "")[:120],
                    "usage": r.get("Usage"),
                    "usage_unit": r.get("UsageUnit"),
                    "list_price": r.get("ListPrice"),
                    "list_price_unit": r.get("ListPriceUnit"),
                    "pretax_cny": amt,
                    "payment_cny": float(r.get("PaymentAmount") or 0),
                }
            )
        out["products"][code] = {
            "label": label,
            "pretax_cny": round(pretax, 4),
            "lines": lines,
            "count": len(lines),
        }
        if pretax > 0 or lines:
            relevant_codes.add(code)

    # Also mark overview rows that match app products
    app_codes = {"sfm", "dysms", "dysms_system", "ecs", "disk"}
    for row in out["overview"]:
        code = str(row.get("product_code") or "")
        if code in app_codes or "百炼" in str(row.get("product_name") or "") or "短信" in str(
            row.get("product_name") or ""
        ):
            out["app_relevant"].append(row)

    # Prefer product detail sums for app_relevant when overview pretax is rough
    for code in ("sfm", "dysms", "dysms_system", "ecs"):
        prod = out["products"].get(code) or {}
        if prod.get("count"):
            out["app_relevant"].append(
                {
                    "product_code": code,
                    "product_name": prod.get("label"),
                    "payment_cny": prod.get("pretax_cny"),
                    "pretax_cny": prod.get("pretax_cny"),
                    "source": "DescribeInstanceBill",
                }
            )

    out["ok"] = True
    out["ak_fingerprint"] = fingerprint_key(ak)[0]
    if overview.get("Success") is False and overview.get("error"):
        out["error"] = str(overview.get("error") or overview.get("Message") or "")
        out["ok"] = False
    return out


def fetch_tencent_billing(month: str | None = None) -> dict[str, Any]:
    """Best-effort Tencent Cloud bill summary (needs billing permission on SOE key)."""
    secret_id = _settings_or_env("TENCENT_SOE_SECRET_ID", "tencent_soe_secret_id")
    secret_key = _settings_or_env("TENCENT_SOE_SECRET_KEY", "tencent_soe_secret_key")
    out: dict[str, Any] = {
        "ok": False,
        "provider": "tencent",
        "configured": bool(secret_id and secret_key),
        "billing_cycle": month
        or datetime.now(tz=timezone.utc).strftime("%Y-%m"),
        "items": [],
        "error": "",
        "note": "",
    }
    if not secret_id or not secret_key:
        out["error"] = "未配置 TENCENT_SOE_SECRET_ID/KEY"
        return out

    # TC3-HMAC-SHA256 for billing.tencentcloudapi.com DescribeBillSummaryByProduct
    service = "billing"
    host = "billing.tencentcloudapi.com"
    action = "DescribeBillSummaryByProduct"
    version = "2018-07-09"
    region = ""
    # DescribeBillSummaryByProduct expects BeginTime/EndTime (YYYY-MM-DD)
    y, m = out["billing_cycle"].split("-")
    begin = f"{y}-{m}-01"
    # last day approx: next month - 1 day via calendar
    import calendar

    last = calendar.monthrange(int(y), int(m))[1]
    end = f"{y}-{m}-{last:02d}"
    payload = json.dumps(
        {"BeginTime": begin, "EndTime": end},
        separators=(",", ":"),
    )
    timestamp = int(time.time())
    date = datetime.fromtimestamp(timestamp, tz=timezone.utc).strftime("%Y-%m-%d")
    http_request_method = "POST"
    canonical_uri = "/"
    canonical_querystring = ""
    ct = "application/json; charset=utf-8"
    canonical_headers = f"content-type:{ct}\nhost:{host}\nx-tc-action:{action.lower()}\n"
    signed_headers = "content-type;host;x-tc-action"
    hashed_request_payload = hashlib.sha256(payload.encode("utf-8")).hexdigest()
    canonical_request = (
        f"{http_request_method}\n{canonical_uri}\n{canonical_querystring}\n"
        f"{canonical_headers}\n{signed_headers}\n{hashed_request_payload}"
    )
    credential_scope = f"{date}/{service}/tc3_request"
    string_to_sign = (
        "TC3-HMAC-SHA256\n"
        f"{timestamp}\n"
        f"{credential_scope}\n"
        f"{hashlib.sha256(canonical_request.encode('utf-8')).hexdigest()}"
    )

    def _sign(key: bytes, msg: str) -> bytes:
        return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()

    secret_date = _sign(("TC3" + secret_key).encode("utf-8"), date)
    secret_service = _sign(secret_date, service)
    secret_signing = _sign(secret_service, "tc3_request")
    signature = hmac.new(
        secret_signing, string_to_sign.encode("utf-8"), hashlib.sha256
    ).hexdigest()
    authorization = (
        "TC3-HMAC-SHA256 "
        f"Credential={secret_id}/{credential_scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}"
    )
    headers = {
        "Authorization": authorization,
        "Content-Type": ct,
        "Host": host,
        "X-TC-Action": action,
        "X-TC-Timestamp": str(timestamp),
        "X-TC-Version": version,
    }
    if region:
        headers["X-TC-Region"] = region
    req = urllib.request.Request(
        f"https://{host}",
        data=payload.encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            data = json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        try:
            data = json.loads(e.read().decode())
        except Exception:
            out["error"] = str(e)
            return out
    except Exception as e:  # noqa: BLE001
        out["error"] = str(e)
        return out

    resp = data.get("Response") or data
    if resp.get("Error"):
        err = resp["Error"]
        out["error"] = f"{err.get('Code')}: {err.get('Message')}"
        out["note"] = "SOE 密钥若无费用中心只读权限，需另配 Billing 只读子账号。"
        return out
    summary = resp.get("SummaryOverview") or resp.get("SummaryDetail") or []
    if isinstance(summary, dict):
        summary = summary.get("Detail") or summary.get("Overview") or []
    items = []
    for row in summary if isinstance(summary, list) else []:
        if not isinstance(row, dict):
            continue
        name = row.get("BusinessCodeName") or row.get("ProductCodeName") or row.get("BusinessCode")
        items.append(
            {
                "product": name,
                "real_total_cost": float(row.get("RealTotalCost") or row.get("TotalCost") or 0),
                "cash_pay": float(row.get("CashPayAmount") or 0),
                "voucher": float(row.get("VoucherPayAmount") or 0),
            }
        )
    out["items"] = items
    out["ok"] = True
    out["raw_keys"] = list(resp.keys())[:20]
    return out


def fetch_livekit_note() -> dict[str, Any]:
    url = _settings_or_env("LIVEKIT_URL", "livekit_url")
    key = _settings_or_env("LIVEKIT_API_KEY", "livekit_api_key")
    secret = _settings_or_env("LIVEKIT_API_SECRET", "livekit_api_secret")
    project = ""
    if "livekit.cloud" in url:
        # wss://acquireenglish-e5la1koz.livekit.cloud → subdomain hint
        try:
            host = url.split("//", 1)[1].split("/", 1)[0]
            project = host.split(".")[0]
        except Exception:
            project = ""
    return {
        "ok": False,
        "provider": "livekit",
        "configured": bool(url and key and secret),
        "project_hint": project,
        "url": url[:80] if url else "",
        "key_fingerprint": fingerprint_key(key)[0] if key else "",
        "note": (
            "LiveKit Cloud 用量需 Analytics API（Scale 计划及以上）或控制台账单；"
            "当前仅检测密钥已配置，未自动拉取分钟/带宽账单。"
        ),
        "error": "" if (url and key and secret) else "未完整配置 LIVEKIT_URL/KEY/SECRET",
    }


def collect_platform_usage(*, month: str | None = None) -> dict[str, Any]:
    keys = discover_keys()
    aliyun = fetch_aliyun_bss(month)
    tencent = fetch_tencent_billing(month)
    livekit = fetch_livekit_note()

    # Roll up app-facing cost estimate from Aliyun products we care about
    aliyun_app_cny = 0.0
    for code in ("sfm", "dysms", "dysms_system", "ecs"):
        aliyun_app_cny += float((aliyun.get("products") or {}).get(code, {}).get("pretax_cny") or 0)

    return {
        "ok": True,
        "collected_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "billing_cycle": month
        or datetime.now(tz=timezone.utc).strftime("%Y-%m"),
        "keys": keys,
        "configured_count": sum(1 for k in keys if k.get("configured")),
        "aliyun": aliyun,
        "tencent": tencent,
        "livekit": livekit,
        "summary": {
            "aliyun_balance_cny": aliyun.get("balance_cny"),
            "aliyun_app_products_cny": round(aliyun_app_cny, 4),
            "dashscope_sfm_cny": float(
                (aliyun.get("products") or {}).get("sfm", {}).get("pretax_cny") or 0
            ),
            "sms_cny": float(
                (aliyun.get("products") or {}).get("dysms", {}).get("pretax_cny") or 0
            )
            + float(
                (aliyun.get("products") or {}).get("dysms_system", {}).get("pretax_cny") or 0
            ),
            "note": (
                "平台账单来自阿里云 BSS（与账号 AccessKey 绑定）；"
                "App 内 ledger 是按次估算，两者口径不同可并存对照。"
            ),
        },
    }
