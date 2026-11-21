# OpenMAIC mock (textbook decompose)

Lightweight HTTP stand-in for [THU-MAIC/OpenMAIC](https://github.com/THU-MAIC/OpenMAIC) used by AcquireEnglish course decompose P1.

## Why

True OpenMAIC is a full Next.js multi-agent classroom generator (Postgres + LLM slots + scenes). For private textbook → lesson packs we need a fast `cleaned_text → lessons[]` path. This mock implements that contract; the API client also speaks native OpenMAIC when pointed at a real instance.

## Run (5060 Ti box)

```powershell
cd D:\AcquireEnglish\tools\openmaic_mock
.\start.ps1
```

Optional LLM enrichment (DeepSeek / OpenAI-compatible / DashScope):

```powershell
$env:DEEPSEEK_API_KEY = "sk-..."
# or OPENAI_API_KEY / DASHSCOPE_API_KEY + OPENAI_BASE_URL
.\start.ps1
```

- Health: `http://127.0.0.1:8093/api/health`
- Tailscale: `http://100.115.252.55:8093/api/health`
- Decompose: `POST /api/v1/decompose`

## API → ECS (fallback only)

Prefer official OpenMAIC on `:3000` — see `tools/openmaic/README.md`.

```
# temporary fallback when official Next.js is down:
OPENMAIC_URL=http://100.115.252.55:8093
PREFER_OPENMAIC=true
```

If the URL is empty or unreachable, the API falls back to `HeuristicSplitter` (private uploads never hard-fail).

## True OpenMAIC

```powershell
cd D:\AcquireEnglish\tools\openmaic
.\start.ps1   # D:\OpenMAIC, bind 0.0.0.0:3000
```

Then set `OPENMAIC_URL=http://100.115.252.55:3000`. The adapter uses materials + generate-classroom and maps scenes back to lessons.