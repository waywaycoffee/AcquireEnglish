# Official OpenMAIC (THU-MAIC) on the 5060 Ti box

AcquireEnglish does **not** vendor OpenMAIC `node_modules`. Clone and run outside the app repo (or under this folder after clone).

## Install path

Preferred:

```text
D:\OpenMAIC
```

Fallback if that path is locked: `D:\OpenMAIC_official`.

Upstream: https://github.com/THU-MAIC/OpenMAIC (MIT). Needs Node ≥ 22.19, pnpm ≥ 10, PostgreSQL 16+, and an LLM.

## Local LLM (this PC)

Primary model for OpenMAIC / course generation:

| Item | Value |
|------|--------|
| Tag | `qwen2.5:7b` |
| Backend | GPU-box OpenAI shim (ModelScope `Qwen/Qwen2.5-7B-Instruct`, 4-bit) |
| Base URL | `http://127.0.0.1:11434/v1` (Tailscale `http://100.115.252.55:11434/v1`) |
| Fallback | `qwen2.5:3b` / `Qwen/Qwen2.5-3B-Instruct` only if VRAM is tight |

Keep the shim running (watchdog / scheduled task `AcquireEnglish-Ollama-Qwen`). See `deploy/gpu-box-ollama/README.md`.

## Start OpenMAIC

```powershell
cd D:\AcquireEnglish\tools\openmaic
.\start.ps1
```

Defaults:

- Bind `0.0.0.0:3000` so ECS can reach `http://100.115.252.55:3000`
- `openmaic.yml` slots → Ollama-compatible `qwen2.5:7b`
- ACCESS_CODE optional for Tailscale-only LAN

## ECS API

```env
OPENMAIC_URL=http://100.115.252.55:3000
PREFER_OPENMAIC=true
```

Mock fallback (optional, keep on another port):

```env
# OPENMAIC_URL=http://100.115.252.55:8093
```

```powershell
cd D:\AcquireEnglish\tools\openmaic_mock
.\start.ps1   # defaults to qwen2.5:7b @ :11434/v1 when no cloud key
```

## Adapter modes

`services/api/.../openmaic_adapter.py` auto-detects:

1. Native: `/api/generate-classroom/capabilities` → materials + generate + poll
2. Mock contract: `POST /api/v1/decompose`

Private uploads always soft-fall back to `HeuristicSplitter` on failure.

## Keep alive

OpenMAIC generation runs **inside the Next.js process**. Leave `.\start.ps1` (or `pnpm start`) running on this GPU PC; do not rely on ECS for inference.

## ECS database (`openmaic-pg`)

Guangzhou ECS cannot always `docker pull postgres:16` from Docker Hub (timeout). Use a China mirror, then tag:

```bash
docker pull docker.1panel.live/library/postgres:16
docker tag docker.1panel.live/library/postgres:16 postgres:16
docker run -d --name openmaic-pg --restart unless-stopped \
  -p 127.0.0.1:5433:5432 \
  -e POSTGRES_DB=openmaic -e POSTGRES_USER=openmaic -e POSTGRES_PASSWORD=openmaic-dev \
  -v openmaic-pg-data:/var/lib/postgresql/data postgres:16
```

`DATABASE_URL=postgresql://openmaic:openmaic-dev@127.0.0.1:5433/openmaic` in `/opt/OpenMAIC/.env.local`.

The host also runs system PostgreSQL on `:5432` (e.g. other services); OpenMAIC uses the isolated container on **5433**.

If no Postgres image can be pulled on ECS, run OpenMAIC on this Windows GPU box only (`D:\OpenMAIC`, `pnpm db:up` or local Postgres) and point ECS at `OPENMAIC_URL` for inference — persistence stays local to the GPU PC.
