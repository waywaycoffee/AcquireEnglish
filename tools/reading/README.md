# Reading TTS worker (5060 Ti → ECS)

## Long novels (绿野仙踪 class)

App shelves the book → `POST /api/reading/speech/book-pregen` splits the whole
text into pages and queues every page for **cloud TTS on the 5060 Ti**. The tile
shows AI progress; **opening is blocked until `ready`**.

- Prefer GPU worker (`process_on_ecs: false`)
- If GPU is offline ~90s, App calls `/book-pregen/fallback` so ECS fills gaps
- Status: `GET /api/reading/speech/book-pregen?doc_id=&voice=`

## Single page (short articles / while reading)

`POST /api/reading/speech/pregen` queues the **current page**.
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
