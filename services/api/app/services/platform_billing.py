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
            "id": "aliyun_bss",
            "label": "阿里云 BSS 账单（专用 AK）",
            "env": "ALIYUN_BSS_ACCESS_KEY_ID|ALIYUN_ECS_ACCESS_KEY_ID",
            "value": val(
                "ALIYUN_BSS_ACCESS_KEY_ID",
                "ALIYUN_ECS_ACCESS_KEY_ID",
                "ALIYUN_ACCESS_KEY_ID",
                "aliyun_bss_access_key_id",
                "aliyun_ecs_access_key_id",
            ),
            "source": src(
                "ALIYUN_BSS_ACCESS_KEY_ID",
                "ALIYUN_ECS_ACCESS_KEY_ID",
                "ALIYUN_ACCESS_KEY_ID",
            ),
            "usage": "平台账单 / 余额（永不回落短信 AK）",
            "billing": "aliyun_bss",
        },
        {
            "id": "aliyun_ecs",
            "label": "阿里云 ECS / 云盘",
            "env": "ALIYUN_ECS_ACCESS_KEY_ID|ALIYUN_ACCESS_KEY_ID",
            "value": val(
                "ALIYUN_ECS_ACCESS_KEY_ID",
                "ALIYUN_ACCESS_KEY_ID",
                "aliyun_ecs_access_key_id",
            ),
            "source": src(
                "ALIYUN_ECS_ACCESS_KEY_ID",
                "ALIYUN_ACCESS_KEY_ID",
            ),
            "usage": "主机与云盘监控（不复用短信 AK）",
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


# CDT 1.0 → 2.0 (2026-12): commodity/billing-item codes change; amounts stay the same.
# Docs: https://help.aliyun.com/zh/cdt/product-overview/cdt-upgrade-to-2-0
_CDT_BILLING_ITEM_LABELS: dict[str, str] = {
    # CDT 2.0 (by traffic type)
    "internet_traffic": "公网流量",
    "inter_region_traffic": "跨地域流量",
    "CU_inter_region_traffic": "跨境流量",
    # CDT 1.0 public (by cloud product)
    "ECS_Out_Bytes": "ECS 公网出流量",
    "Eip_Out_Bytes": "EIP 出流量",
    "clb_out_bytes": "CLB 出流量",
    "Cbwp_Out_Bytes": "共享带宽出流量",
    "Cbwp_Max_Bytes": "共享带宽峰值带宽",
    "IPv6_Out_Bytes": "IPv6 出流量",
    "GA_Max_Bytes": "全球加速峰值带宽",
    "Fc_Out_Bytes": "函数计算出流量",
    "MSE_Out_Bytes": "微服务引擎出流量",
    "PAI_Eas_Out_Bytes": "PAI-EAS 出流量",
    "Anycast_Max_Bytes": "Anycast EIP 峰值带宽",
    "nativeapigw_Out_Bytes": "API 网关出流量",
    "Miniappdev_Out_Bytes": "魔笔出流量",
    # CDT 1.0 inter-region
    "CDTIR_Out_Bytes": "跨地域出流量",
    "GA_Inter_Region_MAX_Bytes": "全球加速跨地域峰值带宽",
    "AnycastInterRegionTraffic": "Anycast 跨地域流量",
    "ECR_Out_Bytes": "ECR 出流量",
    "VPC_Peering_Out_Bytes": "VPC 对等连接出流量",
    # CDT 1.0 cross-border
    "CUCBDT_Out_Bytes": "跨境出流量",
    "CUCBDT_VPC_Peering_Out_Bytes": "跨境 VPC 对等连接出流量",
    "CUCBDT_GA_MAX_Bytes": "跨境全球加速峰值带宽",
}

_CDT_COMMODITY_CODES_V1 = frozenset(
    {
        "cdt_internet_public_cn",
        "cdt_cdtir_public_cn",
        "cdt_cucbdt_public_cn",
    }
)
_CDT_COMMODITY_CODES_V2 = frozenset(
    {
        "cdt_DataTransfer_public_cn",
        "cdt_cucbdt_public_cn",
    }
)


def _cdt_commodity_code(row: dict[str, Any]) -> str:
    for key in ("CommodityCode", "PipCode", "ProductType", "SubscriptionType"):
        val = str(row.get(key) or "").strip()
        if val.startswith("cdt_"):
            return val
    detail = str(row.get("ProductDetail") or "")
    if "跨地域" in detail:
        return "cdt_cdtir_public_cn"
    if "跨境" in detail:
        return "cdt_cucbdt_public_cn"
    return ""


def _cdt_billing_item_code(row: dict[str, Any]) -> str:
    for key in ("BillingItemCode", "BillingItem", "ItemCode", "ChargeItem"):
        raw = str(row.get(key) or "").strip()
        if not raw:
            continue
        # Prefer machine codes over localized display names.
        if raw in _CDT_BILLING_ITEM_LABELS or "_" in raw or raw.islower():
            return raw
    return str(row.get("BillingItemCode") or row.get("BillingItem") or "").strip()


def _cdt_resource_type(row: dict[str, Any]) -> str:
    """CDT 2.0 puts source product in price factors (资源类型), not billing item name."""
    for key in ("InstanceConfig", "Tag", "NickName", "ProductDetail", "BillingItem"):
        text = str(row.get(key) or "")
        if "资源类型" in text:
            # e.g. "计费类型：按流量计费;资源类型：云服务器 ECS实例;地域：华南1"
            for part in text.replace("；", ";").replace("，", ",").split(";"):
                part = part.strip()
                if part.startswith("资源类型") or "资源类型：" in part or "资源类型:" in part:
                    return part.split("：", 1)[-1].split(":", 1)[-1].strip()
        for marker in ("云服务器 ECS", "弹性公网 IP", "共享带宽", "负载均衡", "函数计算"):
            if marker in text:
                return marker
    return ""


def _cdt_version_for(commodity: str, billing_item: str) -> str:
    if commodity in _CDT_COMMODITY_CODES_V2 and billing_item in {
        "internet_traffic",
        "inter_region_traffic",
        "CU_inter_region_traffic",
    }:
        return "2.0"
    if commodity in _CDT_COMMODITY_CODES_V1 or billing_item in _CDT_BILLING_ITEM_LABELS:
        if billing_item in {"internet_traffic", "inter_region_traffic", "CU_inter_region_traffic"}:
            return "2.0"
        if billing_item:
            return "1.0"
    if commodity == "cdt_DataTransfer_public_cn":
        return "2.0"
    return ""


def normalize_cdt_bill_line(row: dict[str, Any]) -> dict[str, Any]:
    """Normalize one DescribeInstanceBill row for CDT 1.0 and 2.0 side-by-side."""
    commodity = _cdt_commodity_code(row)
    item_code = _cdt_billing_item_code(row)
    label = _CDT_BILLING_ITEM_LABELS.get(item_code) or str(
        row.get("ProductDetail") or row.get("BillingItem") or item_code or "云数据传输"
    )
    resource_type = _cdt_resource_type(row)
    version = _cdt_version_for(commodity, item_code)
    detail_parts = [label]
    if resource_type and resource_type not in label:
        detail_parts.append(resource_type)
    if version:
        detail_parts.append(f"CDT {version}")
    pretax = float(row.get("PretaxAmount") or row.get("PaymentAmount") or 0)
    return {
        "product_name": row.get("ProductName") or "云数据传输",
        "detail": " · ".join(detail_parts),
        "billing_item_code": item_code,
        "commodity_code": commodity,
        "cdt_version": version,
        "resource_type": resource_type,
        "instance_id": str(row.get("InstanceID") or "")[:120],
        "usage": row.get("Usage"),
        "usage_unit": row.get("UsageUnit"),
        "list_price": row.get("ListPrice"),
        "list_price_unit": row.get("ListPriceUnit"),
        "pretax_cny": pretax,
        "payment_cny": float(row.get("PaymentAmount") or 0),
        "cost_type": str(row.get("Item") or row.get("BillingType") or ""),
    }


def _bss_credentials(file_env: dict[str, tuple[str, str]] | None = None) -> tuple[str, str]:
    """Billing / BSS only — never fall back to SMS AccessKeys (Aliyun flags that)."""
    ak = _settings_or_env(
        "ALIYUN_BSS_ACCESS_KEY_ID",
        "ALIYUN_ECS_ACCESS_KEY_ID",
        "ALIYUN_ACCESS_KEY_ID",
        "aliyun_bss_access_key_id",
        "aliyun_ecs_access_key_id",
        file_env=file_env,
    )
    sk = _settings_or_env(
        "ALIYUN_BSS_ACCESS_KEY_SECRET",
        "ALIYUN_ECS_ACCESS_KEY_SECRET",
        "ALIYUN_ACCESS_KEY_SECRET",
        "aliyun_bss_access_key_secret",
        "aliyun_ecs_access_key_secret",
        file_env=file_env,
    )
    return ak, sk


def fetch_aliyun_bss(month: str | None = None) -> dict[str, Any]:
    file_env = _merged_env_files()
    ak, sk = _bss_credentials(file_env)
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
        out["error"] = (
            "未配置 ALIYUN_BSS_ACCESS_KEY_ID（或 ALIYUN_ECS_ACCESS_KEY_ID）。"
            "短信 AK 不再用于 BSS，避免触发阿里云敏感 API 风控。"
        )
        return out

    cycle = out["billing_cycle"]
    # QueryAccountBalance is the sensitive API Aliyun flagged. Opt-in only.
    allow_balance = (
        os.environ.get("ALIYUN_BSS_QUERY_BALANCE") or ""
    ).strip().lower() in ("1", "true", "yes", "on")
    if allow_balance:
        bal = _aliyun_bss_call("QueryAccountBalance", {}, ak=ak, sk=sk)
        if bal.get("Success") or bal.get("Code") in ("200", "Success", 200):
            data = bal.get("Data") or {}
            try:
                out["balance_cny"] = float(data.get("AvailableAmount") or 0)
            except (TypeError, ValueError):
                out["balance_cny"] = None
    else:
        out["balance_note"] = (
            "已跳过 QueryAccountBalance（默认关闭）。"
            "需要余额时设置 ALIYUN_BSS_QUERY_BALANCE=1 并使用 BSS 专用 RAM。"
        )

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
        # CDT owns public / inter-region traffic after migrating off per-product Out_Bytes.
        "cdt": "阿里云数据传输（CDT）",
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
            if code == "cdt":
                line = normalize_cdt_bill_line(r)
                amt = float(line.get("pretax_cny") or 0)
            else:
                amt = float(r.get("PretaxAmount") or r.get("PaymentAmount") or 0)
                line = {
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
            pretax += amt
            lines.append(line)
        product_meta: dict[str, Any] = {
            "label": label,
            "pretax_cny": round(pretax, 4),
            "lines": lines,
            "count": len(lines),
        }
        if code == "cdt":
            versions = sorted(
                {
                    str(line.get("cdt_version") or "")
                    for line in lines
                    if line.get("cdt_version")
                }
            )
            commodities = sorted(
                {
                    str(line.get("commodity_code") or "")
                    for line in lines
                    if line.get("commodity_code")
                }
            )
            product_meta["cdt_versions"] = versions
            product_meta["commodity_codes"] = commodities
            product_meta["note"] = (
                "兼容 CDT 1.0（ECS_Out_Bytes 等）与 2.0（internet_traffic / "
                "cdt_DataTransfer_public_cn）；升级后金额口径不变，仅商品/计费项改名。"
            )
        out["products"][code] = product_meta

    app_codes = {"sfm", "dysms", "dysms_system", "ecs", "disk", "cdt"}
    for row in out["overview"]:
        code = str(row.get("product_code") or "")
        name = str(row.get("product_name") or "")
        if (
            code in app_codes
            or code.startswith("cdt")
            or "百炼" in name
            or "短信" in name
            or "云数据传输" in name
            or "CDT" in name.upper()
        ):
            out["app_relevant"].append(row)

    for code in ("sfm", "dysms", "dysms_system", "ecs", "cdt"):
        prod = out["products"].get(code) or {}
        if prod.get("count"):
            out["app_relevant"].append(
                {
                    "product_code": code,
                    "product_name": prod.get("label"),
                    "payment_cny": prod.get("pretax_cny"),
                    "pretax_cny": prod.get("pretax_cny"),
                    "source": "DescribeInstanceBill",
                    "cdt_versions": prod.get("cdt_versions"),
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
    manual_raw = (
        _settings_or_env("LIVEKIT_MANUAL_COST_CNY", file_env=file_env) or ""
    ).strip()
    manual_cost: float | None = None
    if manual_raw:
        try:
            manual_cost = float(manual_raw)
        except ValueError:
            manual_cost = None
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
        "manual_cost_cny": manual_cost,
        "note": (
            "LiveKit Cloud 用量需 Analytics API（Scale 计划及以上）或控制台账单；"
            "当前仅检测密钥已配置，未自动拉取分钟/带宽账单。"
            "可在 .env 写 LIVEKIT_MANUAL_COST_CNY=本月估算元 供运营对照。"
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
    for code in ("sfm", "dysms", "dysms_system", "ecs", "cdt"):
        aliyun_app_cny += float(
            (aliyun.get("products") or {}).get(code, {}).get("pretax_cny") or 0
        )
    cdt_prod = (aliyun.get("products") or {}).get("cdt") or {}

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
            "cdt_cny": float(cdt_prod.get("pretax_cny") or 0),
            "cdt_versions": cdt_prod.get("cdt_versions") or [],
            "tencent_total_cny": float(tencent.get("total_cny") or 0)
            if tencent.get("ok")
            else None,
            "gpu_tokens_today": int(gpu.get("total_tokens") or 0) if gpu.get("ok") else None,
            "deepgram_projects": len(deepgram.get("projects") or []),
            "note": (
                "平台账单聚合：阿里云 BSS（含 CDT 1.0/2.0 流量）+ 腾讯云费用中心（需权限）"
                "+ Deepgram 项目校验；DeepSeek / 本地 5060Ti 以 ApiUsageEvent 与 GPU "
                "usage_monitor 按模块对照；App 内 ledger 是按次估算，与厂商账单口径不同可并存。"
            ),
        },
    }
