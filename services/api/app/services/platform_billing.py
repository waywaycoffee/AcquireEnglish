"""Pull platform-side spend from vendor billing APIs using keys in .env / settings.

Never returns raw secrets — only fingerprints, product lines, and amounts.
Scans API + oral_coach + digital_human_coach env files so ALL connected platforms appear.
"""

from __future__ import annotations

import base64
import calendar
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
from pathlib import Path
from typing import Any

from app.config import settings
from app.services.api_usage import fingerprint_key

# Sidecar env files on ECS (and local checkout mirrors).
_ENV_CANDIDATES = (
    Path("/opt/acquireenglish/services/api/.env"),
    Path("/opt/acquireenglish/tools/oral_coach/.env"),
    Path("/opt/acquireenglish/tools/digital_human_coach/.env"),
    Path(__file__).resolve().parents[2] / ".env",
    Path(__file__).resolve().parents[3] / "tools" / "oral_coach" / ".env",
    Path(__file__).resolve().parents[3] / "tools" / "digital_human_coach" / ".env",
)

_MODULE_LABELS_ZH = {
    "oral_coach": "口语陪练",
    "digital_human": "数字人对话",
    "peer_oral": "双人口语",
    "subtitle_asr": "字幕补全·ASR",
    "subtitle_translate": "字幕补全·翻译",
    "subtitle_resegment": "字幕重切分",
    "translation": "阅读/播放器翻译",
    "word_lookup": "查词",
    "grammar": "语法解析",
    "writing_grade": "写作批改",
    "reading_tts": "阅读配音 TTS",
    "fingerprint": "素材指纹 Embedding",
    "scene_vl": "场景识词 VL",
    "vocab_enrich": "词卡 enrichment",
    "membership": "会员相关",
    "local_ollama": "本地 Ollama（未标注模块）",
    "unknown": "未标注模块",
}


def _env(name: str) -> str:
    return (os.getenv(name, "") or "").strip()


def _parse_dotenv(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return out
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip().strip("'").strip('"')
        if key:
            out[key] = val
    return out


def _merged_env_files() -> dict[str, tuple[str, str]]:
    """name -> (value, source_path). First wins for each key."""
    merged: dict[str, tuple[str, str]] = {}
    seen_paths: set[str] = set()
    for path in _ENV_CANDIDATES:
        resolved = str(path.resolve()) if path.exists() else str(path)
        if resolved in seen_paths:
            continue
        seen_paths.add(resolved)
        for k, v in _parse_dotenv(path).items():
            if k not in merged and v:
                merged[k] = (v, path.name)
    return merged


def _settings_or_env(*names: str, file_env: dict[str, tuple[str, str]] | None = None) -> str:
    for n in names:
        attr = n.lower()
        if hasattr(settings, attr):
            v = getattr(settings, attr)
            if isinstance(v, str) and v.strip():
                return v.strip()
        v = _env(n)
        if v:
            return v
        if file_env and n in file_env:
            return file_env[n][0]
    return ""


def _source_for(*names: str, file_env: dict[str, tuple[str, str]]) -> str:
    for n in names:
        if _env(n) or (hasattr(settings, n.lower()) and getattr(settings, n.lower())):
            return "api/.env / process"
        if n in file_env:
            return file_env[n][1]
    return ""


def discover_keys() -> list[dict[str, Any]]:
    """Map configured platform credentials (presence only)."""
    file_env = _merged_env_files()

    def val(*names: str) -> str:
        return _settings_or_env(*names, file_env=file_env)

    def src(*names: str) -> str:
        return _source_for(*names, file_env=file_env)

    catalog = [
        {
            "id": "dashscope",
            "label": "阿里云百炼 / DashScope",
            "env": "DASHSCOPE_API_KEY",
            "value": val("DASHSCOPE_API_KEY", "dashscope_api_key"),
            "source": src("DASHSCOPE_API_KEY"),
            "usage": "LLM / ASR / TTS / VL",
            "billing": "aliyun_bss:sfm",
        },
        {
            "id": "aliyun_sms",
            "label": "阿里云短信",
            "env": "ALIYUN_SMS_ACCESS_KEY_ID",
            "value": val("ALIYUN_SMS_ACCESS_KEY_ID", "aliyun_sms_access_key_id"),
            "source": src("ALIYUN_SMS_ACCESS_KEY_ID"),
            "secret_set": bool(
                val("ALIYUN_SMS_ACCESS_KEY_SECRET", "aliyun_sms_access_key_secret")
            ),
            "usage": "登录验证码 SMS",
            "billing": "aliyun_bss:dysms",
        },
        {
            "id": "aliyun_ecs",
            "label": "阿里云 ECS / 云盘（复用 AK）",
            "env": "ALIYUN_ECS_ACCESS_KEY_ID|ALIYUN_SMS_ACCESS_KEY_ID",
            "value": val(
                "ALIYUN_ECS_ACCESS_KEY_ID",
                "ALIYUN_ACCESS_KEY_ID",
                "ALIYUN_SMS_ACCESS_KEY_ID",
                "aliyun_ecs_access_key_id",
                "aliyun_sms_access_key_id",
            ),
            "source": src(
                "ALIYUN_ECS_ACCESS_KEY_ID",
                "ALIYUN_ACCESS_KEY_ID",
                "ALIYUN_SMS_ACCESS_KEY_ID",
            ),
            "usage": "主机与云盘监控 / 账单",
            "billing": "aliyun_bss:ecs",
        },
        {
            "id": "tencent_soe",
            "label": "腾讯云智聆口语评测 SOE",
            "env": "TENCENT_SOE_SECRET_ID",
            "value": val("TENCENT_SOE_SECRET_ID", "tencent_soe_secret_id"),
            "source": src("TENCENT_SOE_SECRET_ID"),
            "secret_set": bool(val("TENCENT_SOE_SECRET_KEY", "tencent_soe_secret_key")),
            "usage": "跟读 / 发音评测",
            "billing": "tencent_billing:soe",
        },
        {
            "id": "livekit",
            "label": "LiveKit Cloud",
            "env": "LIVEKIT_API_KEY",
            "value": val("LIVEKIT_API_KEY", "livekit_api_key"),
            "source": src("LIVEKIT_API_KEY"),
            "secret_set": bool(val("LIVEKIT_API_SECRET", "livekit_api_secret")),
            "extra": {"url": val("LIVEKIT_URL", "livekit_url")},
            "usage": "实时口语房间",
            "billing": "livekit_cloud",
        },
        {
            "id": "deepseek",
            "label": "DeepSeek",
            "env": "DEEPSEEK_API_KEY",
            "value": val("DEEPSEEK_API_KEY"),
            "source": src("DEEPSEEK_API_KEY"),
            "usage": "写作批改 / 口语陪练 LLM / 字幕翻译",
            "billing": "deepseek_portal + ApiUsageEvent",
        },
        {
            "id": "openai",
            "label": "OpenAI / OpenAI 兼容",
            "env": "OPENAI_API_KEY",
            "value": val("OPENAI_API_KEY"),
            "source": src("OPENAI_API_KEY"),
            "extra": {
                "base_url": val("OPENAI_BASE_URL"),
                "model": val("OPENAI_MODEL", "DEEPSEEK_MODEL"),
            },
            "usage": "OpenAI 兼容聊天（可能指向 DeepSeek）",
            "billing": "openai_usage / 兼容端点",
        },
        {
            "id": "deepgram",
            "label": "Deepgram ASR/TTS",
            "env": "DEEPGRAM_API_KEY",
            "value": val("DEEPGRAM_API_KEY"),
            "source": src("DEEPGRAM_API_KEY"),
            "usage": "口语陪练语音识别",
            "billing": "deepgram_projects",
        },
        {
            "id": "local_gpu_ollama",
            "label": "本机 RTX 5060 Ti · 本地 LLM（Ollama 兼容）",
            "env": "OLLAMA_URL|GPU_USAGE_STATS_URL",
            "value": val(
                "GPU_USAGE_STATS_URL",
                "OLLAMA_URL",
                "LOCAL_LLM_URL",
            )
            or "http://100.115.252.55:11434",
            "source": src("GPU_USAGE_STATS_URL", "OLLAMA_URL", "LOCAL_LLM_URL")
            or "default Tailscale",
            "usage": "App 本地 Ollama / 字幕翻译备选 / 口语 LLM",
            "billing": "gpu_usage_monitor + ApiUsageEvent",
            "force_configured": True,
            "extra": {
                "stats_url": val("GPU_USAGE_STATS_URL")
                or "http://100.115.252.55:11435/stats",
                "inference_hint": "http://100.115.252.55:11434/v1",
            },
        },
        {
            "id": "livetalking",
            "label": "LiveTalking 数字人（5060 Ti）",
            "env": "LIVETALKING_URL",
            "value": val("LIVETALKING_URL"),
            "source": src("LIVETALKING_URL"),
            "usage": "数字人口型驱动（GPU，不计 LLM token）",
            "billing": "local_gpu_runtime",
        },
        {
            "id": "fingerprint_embed",
            "label": "素材指纹 Embedding（可选远程 GPU）",
            "env": "FINGERPRINT_EMBED_URL",
            "value": val("FINGERPRINT_EMBED_URL", "fingerprint_embed_url"),
            "source": src("FINGERPRINT_EMBED_URL"),
            "usage": "指纹缓存向量；空则本机 hashing-trick",
            "billing": "ApiUsageEvent:fingerprint",
        },
    ]
    out: list[dict[str, Any]] = []
    for item in catalog:
        val_raw = item.get("value") or ""
        force = bool(item.get("force_configured"))
        present = bool(val_raw) or force
        # For URL-only entries, fingerprint the URL string (not a secret).
        is_url = str(val_raw).startswith("http") or item["id"] in {
            "local_gpu_ollama",
            "livetalking",
            "fingerprint_embed",
        }
        if present and val_raw and not is_url:
            fp, label = fingerprint_key(val_raw)
        elif present and val_raw:
            fp, label = "", (val_raw[:64] + ("…" if len(val_raw) > 64 else ""))
        else:
            fp, label = "", ""
        out.append(
            {
                "id": item["id"],
                "label": item["label"],
                "env": item["env"],
                "usage": item["usage"],
                "billing": item["billing"],
                "configured": present if not force else bool(val_raw) or force,
                "key_fingerprint": fp,
                "key_label": label,
                "secret_set": bool(item.get("secret_set", present and not is_url)),
                "source": item.get("source") or "",
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
    file_env = _merged_env_files()
    ak = _settings_or_env(
        "ALIYUN_ECS_ACCESS_KEY_ID",
        "ALIYUN_ACCESS_KEY_ID",
        "ALIYUN_SMS_ACCESS_KEY_ID",
        "aliyun_sms_access_key_id",
        file_env=file_env,
    )
    sk = _settings_or_env(
        "ALIYUN_ECS_ACCESS_KEY_SECRET",
        "ALIYUN_ACCESS_KEY_SECRET",
        "ALIYUN_SMS_ACCESS_KEY_SECRET",
        "aliyun_sms_access_key_secret",
        file_env=file_env,
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

    wanted = {
        "sfm": "阿里云百炼（DashScope / 模型调用）",
        "dysms": "阿里云短信",
        "dysms_system": "阿里云国内短信",
        "ecs": "阿里云 ECS",
        "disk": "阿里云云盘",
        "snapshot": "快照",
    }
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

    app_codes = {"sfm", "dysms", "dysms_system", "ecs", "disk"}
    for row in out["overview"]:
        code = str(row.get("product_code") or "")
        if code in app_codes or "百炼" in str(row.get("product_name") or "") or "短信" in str(
            row.get("product_name") or ""
        ):
            out["app_relevant"].append(row)

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
    file_env = _merged_env_files()
    secret_id = _settings_or_env(
        "TENCENT_SOE_SECRET_ID", "tencent_soe_secret_id", file_env=file_env
    )
    secret_key = _settings_or_env(
        "TENCENT_SOE_SECRET_KEY", "tencent_soe_secret_key", file_env=file_env
    )
    out: dict[str, Any] = {
        "ok": False,
        "provider": "tencent",
        "configured": bool(secret_id and secret_key),
        "billing_cycle": month
        or datetime.now(tz=timezone.utc).strftime("%Y-%m"),
        "items": [],
        "error": "",
        "note": "",
        "key_fingerprint": fingerprint_key(secret_id)[0] if secret_id else "",
    }
    if not secret_id or not secret_key:
        out["error"] = "未配置 TENCENT_SOE_SECRET_ID/KEY"
        return out

    service = "billing"
    host = "billing.tencentcloudapi.com"
    action = "DescribeBillSummaryByProduct"
    version = "2018-07-09"
    region = ""
    y, m = out["billing_cycle"].split("-")
    begin = f"{y}-{m}-01"
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
        name = (
            row.get("BusinessCodeName")
            or row.get("ProductCodeName")
            or row.get("BusinessCode")
        )
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
    out["total_cny"] = round(sum(i["real_total_cost"] for i in items), 4)
    return out


def fetch_livekit_note() -> dict[str, Any]:
    file_env = _merged_env_files()
    url = _settings_or_env("LIVEKIT_URL", "livekit_url", file_env=file_env)
    key = _settings_or_env("LIVEKIT_API_KEY", "livekit_api_key", file_env=file_env)
    secret = _settings_or_env(
        "LIVEKIT_API_SECRET", "livekit_api_secret", file_env=file_env
    )
    project = ""
    if "livekit.cloud" in url:
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


def fetch_deepgram_usage() -> dict[str, Any]:
    """List Deepgram projects (balance/usage details need project-scoped calls)."""
    file_env = _merged_env_files()
    key = _settings_or_env("DEEPGRAM_API_KEY", file_env=file_env)
    out: dict[str, Any] = {
        "ok": False,
        "provider": "deepgram",
        "configured": bool(key),
        "projects": [],
        "error": "",
        "note": "Deepgram 控制台可查分钟用量；此处校验密钥并列出项目。",
        "key_fingerprint": fingerprint_key(key)[0] if key else "",
        "key_label": fingerprint_key(key)[1] if key else "",
    }
    if not key:
        out["error"] = "未配置 DEEPGRAM_API_KEY（通常在 oral_coach/.env）"
        return out
    req = urllib.request.Request(
        "https://api.deepgram.com/v1/projects",
        headers={"Authorization": f"Token {key}"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            data = json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read().decode())
            out["error"] = str(body.get("err_msg") or body.get("message") or e)
        except Exception:
            out["error"] = str(e)
        return out
    except Exception as e:  # noqa: BLE001
        out["error"] = str(e)
        return out
    projects = data.get("projects") or data.get("Projects") or []
    for p in projects if isinstance(projects, list) else []:
        if not isinstance(p, dict):
            continue
        out["projects"].append(
            {
                "project_id": str(p.get("project_id") or p.get("projectId") or "")[:40],
                "name": str(p.get("name") or "")[:80],
            }
        )
    out["ok"] = True
    return out


def fetch_deepseek_note() -> dict[str, Any]:
    file_env = _merged_env_files()
    key = _settings_or_env("DEEPSEEK_API_KEY", file_env=file_env)
    base = _settings_or_env("OPENAI_BASE_URL", file_env=file_env) or "https://api.deepseek.com/v1"
    model = (
        _settings_or_env("DEEPSEEK_MODEL", "OPENAI_MODEL", file_env=file_env)
        or "deepseek-chat"
    )
    return {
        "ok": bool(key),
        "provider": "deepseek",
        "configured": bool(key),
        "base_url": base[:100],
        "model": model,
        "key_fingerprint": fingerprint_key(key)[0] if key else "",
        "key_label": fingerprint_key(key)[1] if key else "",
        "note": (
            "DeepSeek 无公开账单 API；消耗以 ApiUsageEvent / oral_coach 调用为准，"
            "可在平台门户核对。"
        ),
        "error": "" if key else "未配置 DEEPSEEK_API_KEY",
    }


def fetch_gpu_usage() -> dict[str, Any]:
    """Pull local 5060 Ti usage_monitor stats over Tailscale (module breakdown)."""
    file_env = _merged_env_files()
    stats_url = (
        _settings_or_env("GPU_USAGE_STATS_URL", file_env=file_env)
        or "http://100.115.252.55:11435/stats"
    )
    out: dict[str, Any] = {
        "ok": False,
        "provider": "local_gpu_5060ti",
        "stats_url": stats_url,
        "label": "本机 RTX 5060 Ti（本地 LLM）",
        "day": "",
        "requests": 0,
        "input_tokens": 0,
        "output_tokens": 0,
        "total_tokens": 0,
        "by_module": [],
        "error": "",
        "note": (
            "Token 来自 GPU 箱 usage_monitor；按 X-Acquire-Module 归因到 App 模块。"
            "LiveTalking 口型不产生 LLM token，单独计 GPU 运行时。"
        ),
    }
    req = urllib.request.Request(stats_url, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            data = json.loads(r.read().decode())
    except Exception as e:  # noqa: BLE001
        out["error"] = (
            f"无法拉取 GPU 用量（{stats_url}）：{e}。"
            "请确认本机 deploy/gpu-box-ollama 已启动且 stats 监听 Tailscale。"
        )
        return out

    out["day"] = str(data.get("day") or "")
    out["requests"] = int(data.get("requests") or 0)
    out["input_tokens"] = int(data.get("input_tokens") or 0)
    out["output_tokens"] = int(data.get("output_tokens") or 0)
    out["total_tokens"] = int(data.get("total_tokens") or 0)
    out["failures"] = int(data.get("failures") or 0)
    by_module = data.get("by_module") or []
    modules: list[dict[str, Any]] = []
    if isinstance(by_module, list) and by_module:
        for row in by_module:
            if not isinstance(row, dict):
                continue
            mid = str(row.get("module") or "unknown")
            modules.append(
                {
                    "module": mid,
                    "label_zh": _MODULE_LABELS_ZH.get(mid, mid),
                    "requests": int(row.get("requests") or 0),
                    "tokens": int(row.get("tokens") or 0),
                    "input_tokens": int(row.get("input_tokens") or 0),
                    "output_tokens": int(row.get("output_tokens") or 0),
                }
            )
    else:
        # Fallback: roll up clients[].kind if older monitor without by_module.
        rolled: dict[str, dict[str, Any]] = {}
        for row in data.get("clients") or []:
            if not isinstance(row, dict):
                continue
            mid = str(row.get("module") or row.get("kind") or "unknown")
            slot = rolled.setdefault(
                mid,
                {
                    "module": mid,
                    "label_zh": _MODULE_LABELS_ZH.get(mid, mid),
                    "requests": 0,
                    "tokens": 0,
                    "input_tokens": 0,
                    "output_tokens": 0,
                },
            )
            slot["requests"] += int(row.get("requests") or 0)
            slot["tokens"] += int(row.get("tokens") or 0)
        modules = sorted(rolled.values(), key=lambda x: x["tokens"], reverse=True)
    out["by_module"] = modules
    out["ok"] = True
    return out


def module_label_zh(module: str) -> str:
    return _MODULE_LABELS_ZH.get(module, module or "未标注模块")


def collect_platform_usage(*, month: str | None = None) -> dict[str, Any]:
    keys = discover_keys()
    aliyun = fetch_aliyun_bss(month)
    tencent = fetch_tencent_billing(month)
    livekit = fetch_livekit_note()
    deepgram = fetch_deepgram_usage()
    deepseek = fetch_deepseek_note()
    gpu = fetch_gpu_usage()

    aliyun_app_cny = 0.0
    for code in ("sfm", "dysms", "dysms_system", "ecs"):
        aliyun_app_cny += float(
            (aliyun.get("products") or {}).get(code, {}).get("pretax_cny") or 0
        )

    configured = [k for k in keys if k.get("configured")]
    return {
        "ok": True,
        "collected_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "billing_cycle": month
        or datetime.now(tz=timezone.utc).strftime("%Y-%m"),
        "keys": keys,
        "configured_count": len(configured),
        "configured_platforms": [k["id"] for k in configured],
        "aliyun": aliyun,
        "tencent": tencent,
        "livekit": livekit,
        "deepgram": deepgram,
        "deepseek": deepseek,
        "gpu": gpu,
        "module_labels_zh": _MODULE_LABELS_ZH,
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
                (aliyun.get("products") or {}).get("dysms_system", {}).get("pretax_cny")
                or 0
            ),
            "tencent_total_cny": float(tencent.get("total_cny") or 0)
            if tencent.get("ok")
            else None,
            "gpu_tokens_today": int(gpu.get("total_tokens") or 0) if gpu.get("ok") else None,
            "deepgram_projects": len(deepgram.get("projects") or []),
            "note": (
                "平台账单聚合：阿里云 BSS + 腾讯云费用中心（需权限）+ Deepgram 项目校验；"
                "DeepSeek / 本地 5060Ti 以 ApiUsageEvent 与 GPU usage_monitor 按模块对照；"
                "App 内 ledger 是按次估算，与厂商账单口径不同可并存。"
            ),
        },
    }
