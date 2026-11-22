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

CosyVoice 是**云端 API**（DashScope），本机不装权重；本机跑的是 **worker 排队 + 代合成 + 写回 ECS 缓存**。

一次性注册登录自启：

```powershell
cd D:\AcquireEnglish
powershell -ExecutionPolicy Bypass -File .\tools\reading\install_tts_worker.ps1
```

前台调试：

```powershell
cd D:\AcquireEnglish
python tools\reading\tts_worker.py
```

Optional local DashScope key（有则本机调 CosyVoice；无则走 ECS RPC，ECS 上已有 `DASHSCOPE_API_KEY`）：

```powershell
$env:DASHSCOPE_API_KEY="sk-..."
python tools\reading\tts_worker.py
```

SSH host defaults to `acquireenglish`（与字幕 GPU worker 相同）。
