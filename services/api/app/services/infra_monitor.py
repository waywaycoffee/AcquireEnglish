"""ECS host + Aliyun cloud-disk snapshot for admin infra monitor."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import shutil
import socket
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path
from typing import Any, Callable

from app.config import settings


def _run(cmd: list[str], timeout: float = 8.0) -> str:
    try:
        p = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return (p.stdout or "").strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def _bytes_human(n: int | float) -> str:
    n = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(n) < 1024 or unit == "TB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{int(n)} B"
        n /= 1024
    return f"{n:.1f} TB"


def _read_meminfo() -> dict[str, int]:
    out: dict[str, int] = {}
    try:
        text = Path("/proc/meminfo").read_text(encoding="utf-8")
    except OSError:
        return out
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0].endswith(":"):
            key = parts[0][:-1]
            try:
                # values in kB
                out[key] = int(parts[1]) * 1024
            except ValueError:
                continue
    return out


def _cpu_sample() -> tuple[int, int]:
    """Return (idle, total) jiffies from /proc/stat."""
    try:
        line = Path("/proc/stat").read_text(encoding="utf-8").splitlines()[0]
    except OSError:
        return 0, 0
    parts = line.split()
    if not parts or parts[0] != "cpu":
        return 0, 0
    nums = [int(x) for x in parts[1:] if x.isdigit()]
    if len(nums) < 4:
        return 0, 0
    idle = nums[3] + (nums[4] if len(nums) > 4 else 0)
    total = sum(nums)
    return idle, total


def _cpu_percent(interval: float = 0.35) -> float | None:
    a_idle, a_total = _cpu_sample()
    if a_total <= 0:
        return None
    time.sleep(interval)
    b_idle, b_total = _cpu_sample()
    d_total = b_total - a_total
    d_idle = b_idle - a_idle
    if d_total <= 0:
        return None
    return round(max(0.0, min(100.0, (1.0 - d_idle / d_total) * 100.0)), 1)


def _loadavg() -> dict[str, Any]:
    try:
        a, b, c = os.getloadavg()
        return {"1m": round(a, 2), "5m": round(b, 2), "15m": round(c, 2)}
    except (AttributeError, OSError):
        return {}


def _uptime_seconds() -> float | None:
    try:
        return float(Path("/proc/uptime").read_text(encoding="utf-8").split()[0])
    except (OSError, IndexError, ValueError):
        return None


def _service_status(name: str) -> str:
    out = _run(["systemctl", "is-active", name])
    return out or "unknown"


def _dir_size(path: Path) -> int | None:
    if not path.exists():
        return None
    # Prefer du -sb (fast); fall back to shallow estimate.
    raw = _run(["du", "-sb", str(path)], timeout=12.0)
    if raw:
        try:
            return int(raw.split()[0])
        except (ValueError, IndexError):
            pass
    total = 0
    try:
        for root, _dirs, files in os.walk(path):
            for name in files:
                try:
                    total += (Path(root) / name).stat().st_size
                except OSError:
                    continue
    except OSError:
        return None
    return total


def _mounts() -> list[dict[str, Any]]:
    mounts: list[dict[str, Any]] = []
    skip_fs = {
        "tmpfs",
        "devtmpfs",
        "squashfs",
        "overlay",
        "proc",
        "sysfs",
        "cgroup",
        "cgroup2",
        "efivarfs",
        "devpts",
        "mqueue",
        "hugetlbfs",
        "rpc_pipefs",
        "fusectl",
        "configfs",
        "pstore",
        "bpf",
        "tracefs",
        "debugfs",
        "securityfs",
        "ramfs",
        "nsfs",
        "autofs",
    }
    try:
        lines = Path("/proc/mounts").read_text(encoding="utf-8").splitlines()
    except OSError:
        # Windows / non-linux fallback
        usage = shutil.disk_usage(".")
        return [
            {
                "device": "local",
                "mount": str(Path(".").resolve()),
                "fstype": "unknown",
                "total_bytes": usage.total,
                "used_bytes": usage.used,
                "free_bytes": usage.free,
                "used_pct": round(usage.used / usage.total * 100, 1) if usage.total else 0,
                "total_human": _bytes_human(usage.total),
                "used_human": _bytes_human(usage.used),
                "free_human": _bytes_human(usage.free),
            }
        ]

    seen: set[str] = set()
    for line in lines:
        parts = line.split()
        if len(parts) < 3:
            continue
        device, mount, fstype = parts[0], parts[1], parts[2]
        if fstype in skip_fs or mount.startswith("/snap"):
            continue
        if not device.startswith("/dev/"):
            continue
        if mount in seen:
            continue
        seen.add(mount)
        try:
            usage = shutil.disk_usage(mount)
        except OSError:
            continue
        mounts.append(
            {
                "device": device,
                "mount": mount,
                "fstype": fstype,
                "total_bytes": usage.total,
                "used_bytes": usage.used,
                "free_bytes": usage.free,
                "used_pct": round(usage.used / usage.total * 100, 1) if usage.total else 0,
                "total_human": _bytes_human(usage.total),
                "used_human": _bytes_human(usage.used),
                "free_human": _bytes_human(usage.free),
            }
        )
    mounts.sort(key=lambda m: m["mount"])
    return mounts


def _block_devices() -> list[dict[str, Any]]:
    raw = _run(["lsblk", "-b", "-J", "-o", "NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL,SERIAL,UUID"])
    if not raw:
        return []
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return []
    devices = data.get("blockdevices") or []
    out: list[dict[str, Any]] = []

    def walk(nodes: list[dict[str, Any]], parent: str | None = None) -> None:
        for n in nodes:
            name = str(n.get("name") or "")
            size = int(n.get("size") or 0)
            out.append(
                {
                    "name": name,
                    "path": f"/dev/{name}" if name else "",
                    "size_bytes": size,
                    "size_human": _bytes_human(size),
                    "type": n.get("type"),
                    "mountpoint": n.get("mountpoint") or "",
                    "fstype": n.get("fstype") or "",
                    "model": n.get("model") or "",
                    "serial": n.get("serial") or "",
                    "uuid": n.get("uuid") or "",
                    "parent": parent,
                    "likely_cloud_disk": bool(
                        name.startswith("vd") or name.startswith("nvme") or name.startswith("xvd")
                    ),
                }
            )
            kids = n.get("children") or []
            if isinstance(kids, list) and kids:
                walk(kids, name)

    if isinstance(devices, list):
        walk(devices)
    return out


def _metadata() -> dict[str, Any]:
    """Best-effort Aliyun ECS metadata (often blocked on hardened images)."""
    base = "http://100.100.100.200/latest"
    out: dict[str, Any] = {"available": False}
    token = ""
    try:
        req = urllib.request.Request(
            f"{base}/api/token",
            method="PUT",
            headers={"X-aliyun-ecs-metadata-token-ttl-seconds": "60"},
        )
        with urllib.request.urlopen(req, timeout=1.5) as r:
            token = r.read().decode().strip()
    except Exception:
        token = ""

    def get(path: str) -> str:
        headers = {}
        if token:
            headers["X-aliyun-ecs-metadata-token"] = token
        req = urllib.request.Request(f"{base}/meta-data/{path}", headers=headers)
        with urllib.request.urlopen(req, timeout=1.5) as r:
            return r.read().decode().strip()

    keys = {
        "instance_id": "instance-id",
        "instance_type": "instance/instance-type",
        "region_id": "region-id",
        "zone_id": "zone-id",
        "image_id": "image-id",
        "hostname": "hostname",
    }
    for dst, src in keys.items():
        try:
            out[dst] = get(src)
            out["available"] = True
        except Exception:
            out[dst] = ""
    return out


def _aliyun_credentials() -> tuple[str, str]:
    # Never fall back to SMS AccessKeys — those are Dysms-only and trigger
    # Aliyun "suspicious sensitive API" alerts when reused for ECS/BSS.
    ak = (
        (settings.aliyun_ecs_access_key_id or "").strip()
        or os.environ.get("ALIYUN_ECS_ACCESS_KEY_ID", "").strip()
        or os.environ.get("ALIYUN_ACCESS_KEY_ID", "").strip()
    )
    sk = (
        (settings.aliyun_ecs_access_key_secret or "").strip()
        or os.environ.get("ALIYUN_ECS_ACCESS_KEY_SECRET", "").strip()
        or os.environ.get("ALIYUN_ACCESS_KEY_SECRET", "").strip()
    )
    return ak, sk


def _aliyun_sign(params: dict[str, str], secret: str) -> str:
    qs = "&".join(
        f"{urllib.parse.quote(k, safe='')}={urllib.parse.quote(params[k], safe='')}"
        for k in sorted(params)
    )
    string_to_sign = "GET&%2F&" + urllib.parse.quote(qs, safe="")
    dig = hmac.new((secret + "&").encode(), string_to_sign.encode(), hashlib.sha1).digest()
    return base64.b64encode(dig).decode()


def _aliyun_call(
    host: str,
    version: str,
    action: str,
    extra: dict[str, str],
    *,
    ak: str,
    sk: str,
    region: str,
) -> dict[str, Any]:
    params = {
        "Format": "JSON",
        "Version": version,
        "AccessKeyId": ak,
        "SignatureMethod": "HMAC-SHA1",
        "Timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "SignatureVersion": "1.0",
        "SignatureNonce": str(uuid.uuid4()),
        "Action": action,
        "RegionId": region,
    }
    params.update(extra)
    params["Signature"] = _aliyun_sign(params, sk)
    # Prefer regional ECS endpoint (central ecs.aliyuncs.com rejects some regions).
    hosts = [host]
    if host.startswith("ecs.") and region:
        regional = f"ecs.{region}.aliyuncs.com"
        if regional not in hosts:
            hosts.insert(0, regional)
    last: dict[str, Any] = {"error": "no host"}
    for h in hosts:
        url = f"https://{h}/?" + urllib.parse.urlencode(params)
        try:
            with urllib.request.urlopen(url, timeout=12) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            try:
                last = json.loads(e.read().decode())
            except Exception:
                last = {"error": str(e), "Code": getattr(e, "code", None)}
        except Exception as e:  # noqa: BLE001
            last = {"error": str(e)}
        # Retry next host on endpoint/region mismatch
        msg = str(last.get("Message") or last.get("error") or "")
        if "endpoint" not in msg.lower() and "region" not in msg.lower():
            return last
    return last


def _collect_aliyun_cloud(
    *,
    instance_hint: str,
    region_hint: str,
) -> dict[str, Any]:
    ak, sk = _aliyun_credentials()
    result: dict[str, Any] = {
        "configured": bool(ak and sk),
        "ok": False,
        "region_id": region_hint or (settings.aliyun_ecs_region_id or "").strip() or "cn-guangzhou",
        "instance": None,
        "disks": [],
        "error": "",
        "note": "",
    }
    if not ak or not sk:
        result["note"] = (
            "未配置阿里云 AccessKey（ALIYUN_ECS_ACCESS_KEY_ID / ALIYUN_ACCESS_KEY_ID）。"
            "本机云盘用量仍可查看；控制台级磁盘详情需只读 ECS 权限。"
        )
        return result

    region = result["region_id"]
    instance_id = (settings.aliyun_ecs_instance_id or "").strip() or instance_hint
    public_ip = (settings.aliyun_ecs_public_ip or "").strip() or "8.163.45.100"
    scan_regions = []
    for r in [
        region,
        "cn-guangzhou",
        "cn-hangzhou",
        "cn-shenzhen",
        "cn-beijing",
        "cn-shanghai",
        "cn-qingdao",
        "cn-chengdu",
        "cn-hongkong",
    ]:
        if r and r not in scan_regions:
            scan_regions.append(r)

    if not instance_id:
        # Discover by public IP across likely regions
        for r in scan_regions:
            resp = _aliyun_call(
                "ecs.aliyuncs.com",
                "2014-05-26",
                "DescribeInstances",
                {"PageSize": "50"},
                ak=ak,
                sk=sk,
                region=r,
            )
            instances = ((resp.get("Instances") or {}).get("Instance")) or []
            for inst in instances:
                ips = ((inst.get("PublicIpAddress") or {}).get("IpAddress")) or []
                eip = ((inst.get("EipAddress") or {}) or {}).get("IpAddress") or ""
                if public_ip in ips or eip == public_ip:
                    instance_id = str(inst.get("InstanceId") or "")
                    region = r
                    result["instance"] = {
                        "instance_id": instance_id,
                        "instance_name": inst.get("InstanceName"),
                        "instance_type": inst.get("InstanceType"),
                        "status": inst.get("Status"),
                        "zone_id": inst.get("ZoneId"),
                        "os_name": inst.get("OSName"),
                        "cpu": inst.get("Cpu"),
                        "memory_mb": inst.get("Memory"),
                        "public_ips": ips or ([eip] if eip else []),
                    }
                    break
            if instance_id:
                result["region_id"] = region
                break
            if resp.get("Code") or resp.get("error"):
                result["error"] = str(resp.get("Message") or resp.get("Code") or resp.get("error"))

    if instance_id and not result["instance"]:
        resp = _aliyun_call(
            "ecs.aliyuncs.com",
            "2014-05-26",
            "DescribeInstances",
            {"InstanceIds": json.dumps([instance_id])},
            ak=ak,
            sk=sk,
            region=region,
        )
        instances = ((resp.get("Instances") or {}).get("Instance")) or []
        if instances:
            inst = instances[0]
            ips = ((inst.get("PublicIpAddress") or {}).get("IpAddress")) or []
            result["instance"] = {
                "instance_id": inst.get("InstanceId"),
                "instance_name": inst.get("InstanceName"),
                "instance_type": inst.get("InstanceType"),
                "status": inst.get("Status"),
                "zone_id": inst.get("ZoneId"),
                "os_name": inst.get("OSName"),
                "cpu": inst.get("Cpu"),
                "memory_mb": inst.get("Memory"),
                "public_ips": ips,
            }
        elif resp.get("Code") or resp.get("error"):
            result["error"] = str(resp.get("Message") or resp.get("Code") or resp.get("error"))

    if not instance_id:
        if not result["error"]:
            result["error"] = "未能定位 ECS 实例（可设置 ALIYUN_ECS_INSTANCE_ID）"
        return result

    disks_resp = _aliyun_call(
        "ecs.aliyuncs.com",
        "2014-05-26",
        "DescribeDisks",
        {"InstanceId": instance_id, "PageSize": "50"},
        ak=ak,
        sk=sk,
        region=region,
    )
    disks = ((disks_resp.get("Disks") or {}).get("Disk")) or []
    if disks_resp.get("Code") or disks_resp.get("error"):
        result["error"] = str(
            disks_resp.get("Message") or disks_resp.get("Code") or disks_resp.get("error")
        )
        result["note"] = "当前 AccessKey 可能缺少 ECS:DescribeDisks 权限（短信子账号常见）。"
        return result

    for d in disks:
        size_gb = int(d.get("Size") or 0)
        result["disks"].append(
            {
                "disk_id": d.get("DiskId"),
                "disk_name": d.get("DiskName"),
                "category": d.get("Category"),
                "type": d.get("Type"),  # system / data
                "status": d.get("Status"),
                "size_gb": size_gb,
                "size_human": f"{size_gb} GB",
                "device": d.get("Device"),
                "portable": d.get("Portable"),
                "encrypted": d.get("Encrypted"),
                "delete_with_instance": d.get("DeleteWithInstance"),
                "zone_id": d.get("ZoneId"),
                "performance_level": d.get("PerformanceLevel"),
                "iops": d.get("IOPS"),
                "throughput": d.get("Throughput"),
                "attached_time": d.get("AttachedTime"),
                "creation_time": d.get("CreationTime"),
            }
        )
    result["ok"] = True
    result["instance_id"] = instance_id
    return result


def collect_infra_snapshot() -> dict[str, Any]:
    mem = _read_meminfo()
    mem_total = mem.get("MemTotal") or 0
    mem_avail = mem.get("MemAvailable") or mem.get("MemFree") or 0
    mem_used = max(0, mem_total - mem_avail) if mem_total else 0
    mem_pct = round(mem_used / mem_total * 100, 1) if mem_total else None

    media_dir = Path(settings.media_cache_dir or "./media")
    if not media_dir.is_absolute():
        media_dir = (Path(__file__).resolve().parents[2] / media_dir).resolve()
    data_dir = Path(__file__).resolve().parents[2] / "data"
    packs_dir = data_dir / "exam_packs"

    cpu_pct = _cpu_percent()
    nproc = os.cpu_count() or 0
    uptime = _uptime_seconds()
    meta = _metadata()
    hostname = socket.gethostname()

    # Hostname like iZ7xvhybxi640caw3qhoq4Z → best-effort instance hint empty;
    # Aliyun discovery uses public IP when instance id unset.
    instance_hint = str(meta.get("instance_id") or settings.aliyun_ecs_instance_id or "").strip()
    region_hint = str(
        meta.get("region_id") or settings.aliyun_ecs_region_id or "cn-guangzhou"
    ).strip()

    cloud = _collect_aliyun_cloud(instance_hint=instance_hint, region_hint=region_hint)

    services: dict[str, str] = {
        "acquireenglish-api": _service_status("acquireenglish-api"),
        "acquireenglish-oral-coach": _service_status("acquireenglish-oral-coach"),
        "acquireenglish-openlist": _service_status("acquireenglish-openlist"),
        "nginx": _service_status("nginx"),
        "coturn": _service_status("coturn"),
    }
    pg = "unknown"
    for unit in (
        "postgresql",
        "postgresql@18-main",
        "postgresql@16-main",
        "postgresql@15-main",
        "postgresql@14-main",
    ):
        st = _service_status(unit)
        if st == "active":
            pg = st
            break
        if st not in ("unknown", ""):
            pg = st
    services["postgresql"] = pg
    redis = _service_status("redis-server")
    if redis == "unknown":
        redis = _service_status("redis")
    services["redis"] = redis

    endpoint_health = _probe_backend_endpoints()

    app_dirs = []
    for label, path in (
        ("media", media_dir),
        ("data", data_dir),
        ("exam_packs", packs_dir),
        ("www", Path("/opt/acquireenglish/www")),
    ):
        size = _dir_size(path) if path.exists() else None
        app_dirs.append(
            {
                "name": label,
                "path": str(path),
                "bytes": size,
                "human": _bytes_human(size) if size is not None else "—",
                "exists": path.exists(),
            }
        )

    mounts = _mounts()
    root_mount = next((m for m in mounts if m["mount"] == "/"), mounts[0] if mounts else None)

    return {
        "ok": True,
        "collected_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "host": {
            "hostname": hostname,
            "fqdn": _run(["hostname", "-f"]) or hostname,
            "uptime_seconds": uptime,
            "uptime_human": (
                f"{int(uptime // 86400)}d {int((uptime % 86400) // 3600)}h"
                if uptime is not None
                else "—"
            ),
            "cpu_percent": cpu_pct,
            "cpu_cores": nproc,
            "loadavg": _loadavg(),
            "memory": {
                "total_bytes": mem_total,
                "used_bytes": mem_used,
                "available_bytes": mem_avail,
                "used_pct": mem_pct,
                "total_human": _bytes_human(mem_total),
                "used_human": _bytes_human(mem_used),
                "available_human": _bytes_human(mem_avail),
            },
            "root_disk": root_mount,
            "metadata": meta,
        },
        "mounts": mounts,
        "block_devices": _block_devices(),
        "services": services,
        "endpoint_health": endpoint_health,
        "app_dirs": app_dirs,
        "aliyun": cloud,
        "alerts": _build_alerts(
            cpu_pct, mem_pct, root_mount, services, cloud, endpoint_health
        ),
    }


def _http_json(
    url: str,
    *,
    timeout: float = 5.0,
    expect: Callable[[dict[str, Any]], str | None] | None = None,
) -> dict[str, Any]:
    started = time.perf_counter()
    try:
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "AcquireEnglish-InfraMonitor/1.0", "Accept": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            status = int(getattr(resp, "status", 200) or 200)
            raw = resp.read(65536).decode("utf-8", errors="replace")
            latency_ms = int((time.perf_counter() - started) * 1000)
            body: dict[str, Any] = {}
            try:
                parsed = json.loads(raw)
                if isinstance(parsed, dict):
                    body = parsed
            except json.JSONDecodeError:
                body = {}
            detail = f"HTTP {status}"
            state = "healthy"
            if status >= 400:
                state = "unhealthy"
                detail = f"HTTP {status}"
            elif expect is not None:
                err = expect(body)
                if err:
                    state = "unhealthy"
                    detail = err
            if state == "healthy" and latency_ms >= 2500:
                state = "degraded"
                detail = f"HTTP {status} · 偏慢 {latency_ms}ms"
            return {
                "ok": state == "healthy",
                "state": state,
                "http_status": status,
                "latency_ms": latency_ms,
                "detail": detail,
                "url": url,
            }
    except Exception as exc:  # noqa: BLE001
        return {
            "ok": False,
            "state": "unhealthy",
            "http_status": 0,
            "latency_ms": int((time.perf_counter() - started) * 1000),
            "detail": str(exc)[:160],
            "url": url,
        }


def _probe_backend_endpoints() -> dict[str, Any]:
    """HTTP-level health for API / coach / GPU-box dependencies."""
    def status_ok(body: dict[str, Any]) -> str | None:
        if str(body.get("status") or "").lower() in ("ok", "healthy", "up"):
            return None
        return f"status={body.get('status')!r}"

    def coach_ready(body: dict[str, Any]) -> str | None:
        if body.get("ready") is True:
            return None
        return f"ready={body.get('ready')!r}"

    gpu_ip = (
        os.environ.get("GPU_BOX_TAILSCALE_IP", "").strip()
        or "100.115.252.55"
    )
    probes = [
        ("api_local", "API 本机", "http://127.0.0.1:5200/api/health", status_ok, True),
        ("oral_coach_local", "口语管线本机", "http://127.0.0.1:8770/api/health", coach_ready, True),
        (
            "livetalking_gpu",
            "LiveTalking GPU",
            f"http://{gpu_ip}:8010/",
            None,
            False,
        ),
        (
            "ollama_gpu",
            "本地 Qwen GPU",
            f"http://{gpu_ip}:11434/health",
            status_ok,
            False,
        ),
    ]
    services: list[dict[str, Any]] = []
    for sid, name, url, expect, critical in probes:
        # livetalking often returns HTML/302 — treat any 2xx/3xx without expect as up
        if expect is None:
            started = time.perf_counter()
            try:
                req = urllib.request.Request(
                    url,
                    headers={"User-Agent": "AcquireEnglish-InfraMonitor/1.0"},
                )
                with urllib.request.urlopen(req, timeout=5.0) as resp:
                    status = int(getattr(resp, "status", 200) or 200)
                    latency_ms = int((time.perf_counter() - started) * 1000)
                    state = "healthy" if status < 400 else "unhealthy"
                    if state == "healthy" and latency_ms >= 2500:
                        state = "degraded"
                    outcome = {
                        "ok": state == "healthy",
                        "state": state,
                        "http_status": status,
                        "latency_ms": latency_ms,
                        "detail": f"HTTP {status}",
                        "url": url,
                    }
            except Exception as exc:  # noqa: BLE001
                outcome = {
                    "ok": False,
                    "state": "unhealthy",
                    "http_status": 0,
                    "latency_ms": int((time.perf_counter() - started) * 1000),
                    "detail": str(exc)[:160],
                    "url": url,
                }
        else:
            outcome = _http_json(url, expect=expect)
        services.append(
            {
                "id": sid,
                "name": name,
                "critical": critical,
                **outcome,
            }
        )

    unhealthy = [s for s in services if s["state"] == "unhealthy"]
    degraded = [s for s in services if s["state"] == "degraded"]
    critical_bad = [s for s in unhealthy if s.get("critical")]
    overall = "healthy"
    if unhealthy:
        overall = "unhealthy" if critical_bad else "degraded"
    elif degraded:
        overall = "degraded"
    return {
        "overall": overall,
        "ok": overall == "healthy",
        "services": services,
        "counts": {
            "total": len(services),
            "healthy": sum(1 for s in services if s["state"] == "healthy"),
            "degraded": len(degraded),
            "unhealthy": len(unhealthy),
            "critical_unhealthy": len(critical_bad),
        },
    }


def _build_alerts(
    cpu_pct: float | None,
    mem_pct: float | None,
    root_mount: dict[str, Any] | None,
    services: dict[str, str],
    cloud: dict[str, Any],
    endpoint_health: dict[str, Any] | None = None,
) -> list[dict[str, str]]:
    alerts: list[dict[str, str]] = []
    if cpu_pct is not None and cpu_pct >= 85:
        alerts.append({"level": "warn", "message": f"CPU 使用率偏高：{cpu_pct}%"})
    if mem_pct is not None and mem_pct >= 85:
        alerts.append({"level": "warn", "message": f"内存使用率偏高：{mem_pct}%"})
    if root_mount and float(root_mount.get("used_pct") or 0) >= 85:
        alerts.append(
            {
                "level": "warn",
                "message": f"系统盘 {root_mount.get('mount')} 使用率 {root_mount.get('used_pct')}%",
            }
        )
    for name, st in services.items():
        if st not in ("active", "unknown"):
            alerts.append({"level": "critical", "message": f"服务 {name} 状态异常：{st}"})
    for row in (endpoint_health or {}).get("services") or []:
        state = str(row.get("state") or "")
        if state == "unhealthy":
            alerts.append(
                {
                    "level": "critical" if row.get("critical") else "warn",
                    "message": f"后端探测 {row.get('name')} 不健康：{row.get('detail')}",
                }
            )
        elif state == "degraded":
            alerts.append(
                {
                    "level": "warn",
                    "message": f"后端探测 {row.get('name')} 偏慢：{row.get('detail')}",
                }
            )
    if cloud.get("configured") and not cloud.get("ok") and cloud.get("error"):
        alerts.append(
            {
                "level": "info",
                "message": f"阿里云盘 API：{cloud.get('error')}",
            }
        )
    return alerts
