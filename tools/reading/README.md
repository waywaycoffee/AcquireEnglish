# Reading TTS worker (5060 Ti → ECS)

App opens a book → `POST /api/reading/speech/pregen` queues the **current page**.
This worker (or ECS background filler) synthesizes sentence MP3s into the shared
cache `media/reading/tts/` and writes pack JSON:

- Shared: `media/reading/packs/{doc}/{voice}/page-{n}.json`
- Personal: `media/reading/personal/{user_id}/packs/...`

Next open / continuous play hits cached URLs — no phone-side synth storm.

## On the 5060 Ti box

```powershell
cd D:\AcquireEnglish
python tools\reading\tts_worker.py
```

Optional local DashScope key:

```powershell
$env:DASHSCOPE_API_KEY="sk-..."
python tools\reading\tts_worker.py
```

Without a local key, synthesize goes through ECS RPC (`DASHSCOPE_API_KEY` on ECS).

SSH host defaults to `acquireenglish` (same as subtitle GPU worker).
