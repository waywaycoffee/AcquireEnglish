# Official OpenMAIC (THU-MAIC) on the GPU box

AcquireEnglish does **not** vendor [THU-MAIC/OpenMAIC](https://github.com/THU-MAIC/OpenMAIC) (MIT). Install it **outside** this repo and point the API at it.

## Install path (this PC)

```
D:\OpenMAIC
```

Prerequisites:

- Node.js >= 22.19, pnpm >= 10 (`npm i -g pnpm@10.28.0`)
- PostgreSQL reachable as `DATABASE_URL` (this box **or** ECS via SSH tunnel)
- LLM key (DeepSeek recommended; reused from `tools/oral_coach/.env`)

OpenMAIC itself is cloud/local LLM HTTP — it does **not** require CUDA. Optional local Ollama/FunASR stay on this 5060 Ti.

## Database (ECS Postgres + tunnel)

ECS already has Postgres listening on `localhost:5432`. Create the OpenMAIC DB once:

```bash
# from GPU box
scp tools/openmaic/setup_ecs_pg.sh acquireenglish:/tmp/setup_ecs_pg.sh
ssh acquireenglish 'sed -i "s/\r$//" /tmp/setup_ecs_pg.sh; bash /tmp/setup_ecs_pg.sh'
```

`start.ps1` opens `ssh -L 5433:127.0.0.1:5432 acquireenglish` automatically.

```env
DATABASE_URL=postgres://openmaic:openmaic-dev@127.0.0.1:5433/openmaic
```

## Start (keep this process running)

```powershell
cd D:\AcquireEnglish\tools\openmaic
.\start.ps1
```

| Endpoint | URL |
|----------|-----|
| Local | `http://127.0.0.1:3000` |
| Tailscale (ECS) | `http://100.115.252.55:3000` |
| Capabilities | `GET /api/generate-classroom/capabilities` |

Bind is `0.0.0.0:3000` so Guangzhou ECS can reach the GPU box over Tailscale.

**Leave `start.ps1` running.** Classroom generation is server-side and stops if Node exits. The SSH tunnel must stay up too.

## ECS

```env
OPENMAIC_URL=http://100.115.252.55:3000
PREFER_OPENMAIC=true
```

## Mock fallback (optional, :8093)

```powershell
cd D:\AcquireEnglish\tools\openmaic_mock
.\start.ps1
```

Point `OPENMAIC_URL` at `:8093` only when official OpenMAIC is down. The API adapter auto-detects mock (`/api/v1/decompose`) vs native (`/api/generate-classroom/capabilities`).

## Smoke

```powershell
curl http://127.0.0.1:3000/api/generate-classroom/capabilities
# from ECS after env update:
curl http://100.115.252.55:3000/api/generate-classroom/capabilities
```

Native flow used by `OpenMaicSplitter`: `POST /api/materials` → `POST /api/generate-classroom` → poll `pollUrl`.
