"""Probe backend services for the local AcquireEnglish monitor console.

Returns a JSON-serializable snapshot the WinForms tray can render, including
explicit healthy / degraded / unhealthy states.
"""
from __future__ import annotations

import json
import os
import socket
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any, Callable


def _env(name: str, default: str) -> str:
    return (os.environ.get(name) or default).strip()


PUBLIC_API = _env(
    "AE_PUBLIC_API_HEALTH",
    "https://acquireenglish.curlhairai.com/api/health",
)
PUBLIC_COACH = _env(
    "AE_PUBLIC_COACH_HEALTH",
    "https://acquireenglish.curlhairai.com/coach/api/health",
)
LOCAL_LLM = _env("AE_LOCAL_LLM_HEALTH", "http://127.0.0.1:11434/health")
LOCAL_STATS = _env("AE_LOCAL_STATS", "http://127.0.0.1:11435/stats")
LOCAL_LIVETALKING = _env("AE_LIVETALKING_URL", "http://127.0.0.1:8010/")
GPU_SUBTITLE_MARK = _env(
    "AE_GPU_SUBTITLE_MARK",
    "tools\\subtitle\\gpu_worker.py",
)
LIVEKIT_AGENT_MARK = _env(
    "AE_LIVEKIT_AGENT_MARK",
    "tools\\digital_human_coach",
)


def _http_probe(
    url: str,
    *,
    timeout: float = 4.0,
    expect_json: Callable[[dict[str, Any]], str | None] | None = None,
    allow_redirect: bool = True,
) -> dict[str, Any]:
    started = time.perf_counter()
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "AcquireEnglishMonitor/1.0", "Accept": "application/json,*/*"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            status = int(getattr(resp, "status", 200) or 200)
            raw = resp.read(65536)
            latency_ms = int((time.perf_counter() - started) * 1000)
            if status >= 500:
                return {
                    "ok": False,
                    "state": "unhealthy",
                    "http_status": status,
                    "latency_ms": latency_ms,
                    "detail": f"HTTP {status}",
                }
            if status >= 400:
                return {
                    "ok": False,
                    "state": "unhealthy",
                    "http_status": status,
                    "latency_ms": latency_ms,
                    "detail": f"HTTP {status}",
                }
            if 300 <= status < 400 and not allow_redirect:
                return {
                    "ok": False,
                    "state": "unhealthy",
                    "http_status": status,
                    "latency_ms": latency_ms,
                    "detail": f"unexpected redirect HTTP {status}",
                }
            body: dict[str, Any] | None = None
            text = raw.decode("utf-8", errors="replace").strip()
            if text.startswith("{") or text.startswith("["):
                try:
                    parsed = json.loads(text)
                    body = parsed if isinstance(parsed, dict) else {"value": parsed}
                except json.JSONDecodeError:
                    body = None
            if expect_json is not None:
                if body is None:
                    return {
                        "ok": False,
                        "state": "unhealthy",
                        "http_status": status,
                        "latency_ms": latency_ms,
                        "detail": "响应不是 JSON",
                    }
                err = expect_json(body)
                if err:
                    return {
                        "ok": False,
                        "state": "unhealthy",
                        "http_status": status,
                        "latency_ms": latency_ms,
                        "detail": err,
                        "body_keys": sorted(body.keys())[:12],
                    }
            state = "healthy"
            detail = f"HTTP {status}"
            if latency_ms >= 2500:
                state = "degraded"
                detail = f"HTTP {status} · 偏慢 {latency_ms}ms"
            return {
                "ok": state == "healthy",
                "state": state,
                "http_status": status,
                "latency_ms": latency_ms,
                "detail": detail,
            }
    except urllib.error.HTTPError as exc:
        latency_ms = int((time.perf_counter() - started) * 1000)
        return {
            "ok": False,
            "state": "unhealthy",
            "http_status": int(exc.code),
            "latency_ms": latency_ms,
            "detail": f"HTTP {exc.code}",
        }
    except Exception as exc:  # noqa: BLE001
        latency_ms = int((time.perf_counter() - started) * 1000)
        return {
            "ok": False,
            "state": "unhealthy",
            "http_status": 0,
            "latency_ms": latency_ms,
            "detail": str(exc)[:160] or "unreachable",
        }


def _tcp_probe(host: str, port: int, timeout: float = 2.0) -> dict[str, Any]:
    started = time.perf_counter()
    try:
        with socket.create_connection((host, port), timeout=timeout):
            latency_ms = int((time.perf_counter() - started) * 1000)
            state = "degraded" if latency_ms >= 1500 else "healthy"
            return {
                "ok": state == "healthy",
                "state": state,
                "http_status": 0,
                "latency_ms": latency_ms,
                "detail": f"TCP {host}:{port} open",
            }
    except Exception as exc:  # noqa: BLE001
        latency_ms = int((time.perf_counter() - started) * 1000)
        return {
            "ok": False,
            "state": "unhealthy",
            "http_status": 0,
            "latency_ms": latency_ms,
            "detail": str(exc)[:160] or "tcp closed",
        }


def _windows_process_match(needle: str) -> dict[str, Any]:
    """Best-effort: find a running process whose command line contains needle."""
    started = time.perf_counter()
    needle_l = needle.lower().replace("/", "\\")
    try:
        import subprocess

        # PowerShell is always available on this GPU box.
        ps = (
            "Get-CimInstance Win32_Process | "
            "Select-Object -ExpandProperty CommandLine"
        )
        completed = subprocess.run(
            ["powershell", "-NoProfile", "-Command", ps],
            capture_output=True,
            text=True,
            timeout=8,
            check=False,
        )
        latency_ms = int((time.perf_counter() - started) * 1000)
        if completed.returncode != 0:
            return {
                "ok": False,
                "state": "unhealthy",
                "http_status": 0,
                "latency_ms": latency_ms,
                "detail": "无法枚举进程",
            }
        hits = [
            line.strip()
            for line in (completed.stdout or "").splitlines()
            if needle_l in line.lower().replace("/", "\\")
        ]
        if hits:
            return {
                "ok": True,
                "state": "healthy",
                "http_status": 0,
                "latency_ms": latency_ms,
                "detail": f"进程在跑（匹配 {len(hits)}）",
            }
        return {
            "ok": False,
            "state": "unhealthy",
            "http_status": 0,
            "latency_ms": latency_ms,
            "detail": "未找到进程",
        }
    except Exception as exc:  # noqa: BLE001
        latency_ms = int((time.perf_counter() - started) * 1000)
        return {
            "ok": False,
            "state": "unhealthy",
            "http_status": 0,
            "latency_ms": latency_ms,
            "detail": str(exc)[:160],
        }


def _expect_status_ok(body: dict[str, Any]) -> str | None:
    status = str(body.get("status") or "").lower()
    if status in ("ok", "healthy", "up", "ready"):
        return None
    if body.get("ready") is True:
        return None
    return f"status={body.get('status')!r}"


def _expect_coach_ready(body: dict[str, Any]) -> str | None:
    if body.get("ready") is True:
        return None
    return f"ready={body.get('ready')!r}"


def _expect_stats(body: dict[str, Any]) -> str | None:
    if "day" in body and "requests" in body:
        return None
    return "缺少 day/requests 字段"


ServiceProbe = Callable[[], dict[str, Any]]


def _catalog() -> list[dict[str, Any]]:
    """Ordered list of backend probes shown on the monitor."""
    return [
        {
            "id": "local_llm",
            "name": "本地 Qwen 推理",
            "where": "本机 :11434",
            "critical": True,
            "probe": lambda: _http_probe(LOCAL_LLM, expect_json=_expect_status_ok),
        },
        {
            "id": "usage_stats",
            "name": "用量统计端口",
            "where": "本机 :11435",
            "critical": True,
            "probe": lambda: _http_probe(LOCAL_STATS, expect_json=_expect_stats),
        },
        {
            "id": "livetalking",
            "name": "LiveTalking",
            "where": "本机 :8010",
            "critical": False,
            "probe": lambda: _http_probe(LOCAL_LIVETALKING, timeout=5.0),
        },
        {
            "id": "ecs_api",
            "name": "生产 API",
            "where": "ECS /api/health",
            "critical": True,
            "probe": lambda: _http_probe(PUBLIC_API, timeout=8.0, expect_json=_expect_status_ok),
        },
        {
            "id": "oral_coach",
            "name": "口语管线",
            "where": "ECS /coach/api/health",
            "critical": True,
            "probe": lambda: _http_probe(
                PUBLIC_COACH, timeout=8.0, expect_json=_expect_coach_ready
            ),
        },
        {
            "id": "gpu_subtitle_worker",
            "name": "字幕 GPU Worker",
            "where": "本机进程",
            "critical": False,
            "probe": lambda: _windows_process_match(GPU_SUBTITLE_MARK),
        },
        {
            "id": "livekit_agent",
            "name": "LiveKit Agent",
            "where": "本机进程",
            "critical": False,
            "probe": lambda: _windows_process_match(LIVEKIT_AGENT_MARK),
        },
    ]


def collect_backend_health(*, max_workers: int = 6) -> dict[str, Any]:
    catalog = _catalog()
    results: list[dict[str, Any]] = []
    started = time.perf_counter()

    def run_one(item: dict[str, Any]) -> dict[str, Any]:
        probe: ServiceProbe = item["probe"]
        try:
            outcome = probe()
        except Exception as exc:  # noqa: BLE001
            outcome = {
                "ok": False,
                "state": "unhealthy",
                "http_status": 0,
                "latency_ms": 0,
                "detail": str(exc)[:160],
            }
        row = {
            "id": item["id"],
            "name": item["name"],
            "where": item["where"],
            "critical": bool(item.get("critical")),
            "ok": bool(outcome.get("ok")),
            "state": str(outcome.get("state") or ("healthy" if outcome.get("ok") else "unhealthy")),
            "http_status": int(outcome.get("http_status") or 0),
            "latency_ms": int(outcome.get("latency_ms") or 0),
            "detail": str(outcome.get("detail") or ""),
        }
        return row

    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        futures = {pool.submit(run_one, item): item["id"] for item in catalog}
        by_id: dict[str, dict[str, Any]] = {}
        for fut in as_completed(futures):
            by_id[futures[fut]] = fut.result()

    for item in catalog:
        results.append(by_id[item["id"]])

    healthy = sum(1 for r in results if r["state"] == "healthy")
    degraded = sum(1 for r in results if r["state"] == "degraded")
    unhealthy = sum(1 for r in results if r["state"] == "unhealthy")
    critical_bad = [
        r for r in results if r["critical"] and r["state"] == "unhealthy"
    ]
    overall = "healthy"
    if unhealthy:
        overall = "unhealthy" if critical_bad else "degraded"
    elif degraded:
        overall = "degraded"

    return {
        "ok": overall == "healthy",
        "overall": overall,
        "collected_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "elapsed_ms": int((time.perf_counter() - started) * 1000),
        "counts": {
            "total": len(results),
            "healthy": healthy,
            "degraded": degraded,
            "unhealthy": unhealthy,
            "critical_unhealthy": len(critical_bad),
        },
        "alerts": [
            {
                "level": "critical" if r["critical"] else "warn",
                "service": r["id"],
                "message": f"{r['name']} 不健康：{r['detail']}",
            }
            for r in results
            if r["state"] == "unhealthy"
        ]
        + [
            {
                "level": "warn",
                "service": r["id"],
                "message": f"{r['name']} 偏慢：{r['detail']}",
            }
            for r in results
            if r["state"] == "degraded"
        ],
        "services": results,
    }


if __name__ == "__main__":
    print(json.dumps(collect_backend_health(), ensure_ascii=False, indent=2))
