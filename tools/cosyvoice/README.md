# CosyVoice progress → AcquireEnglish admin

Local Harry Potter narration on the **5060 Ti** writes:

| Path | Role |
|------|------|
| `D:\cosyvoice\output\harry-potter\progress.json` | Resumable progress (`all_done`, current chapter/voice, errors) |
| `D:\cosyvoice\output\harry-potter\narrate.pid` | Narrate process PID |
| `…\female_aria\` / `…\male_guy\` | Per-voice chapter WAVs |

AcquireEnglish admin does **not** SSH into the GPU box. A small reporter pushes snapshots to ECS:

```text
GPU box  --POST /api/admin/tts-progress/report-->  ECS API
Admin UI  --GET  /api/admin/tts-progress--------->  ECS store
```

Store location on API host: `{MEDIA_CACHE_DIR}/misc/tts-progress/{job_id}.json`.

## Report once / loop (on 5060 Ti)

From the AcquireEnglish checkout (or copy this script alone):

```powershell
$env:AE_ADMIN_TOKEN = (Get-Content $env:USERPROFILE\acquireenglish-admin-login.token -Raw).Trim()
# optional:
# $env:AE_API_BASE = "https://acquireenglish.curlhairai.com"
# $env:COSYVOICE_HP_DIR = "D:\cosyvoice\output\harry-potter"

python tools\cosyvoice\report_tts_progress.py --once
python tools\cosyvoice\report_tts_progress.py --loop 60
python tools\cosyvoice\report_tts_progress.py --dry-run
```

Requires the same **X-Admin-Token** used by `/admin/`.

Optional: schedule Task Scheduler or add a line to `watch_harry_potter.ps1` to call `--once` after each tick.

## Admin UI

Open `https://…/admin/` → tab **TTS 进度**.

Shows CosyVoice local jobs (status, %, chapter×voice, PID alive, last error, paths) plus a summary of ECS `reading-tts-jobs` book pregen rows when present.
