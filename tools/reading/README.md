# Reading TTS worker (5060 Ti → ECS)

## Classic book covers

Featured Standard Ebooks jackets are resolved via Open Library and stored on
ECS under `media/reading/covers/`. Guangzhou ECS often cannot reach
openlibrary.org — seed from this PC:

```powershell
python tools/reading/seed_book_covers.py --upload
```

App shelf calls `POST /api/reading/covers/ensure` in the background and shows
the ECS URL (cloth hardcover fallback if missing).

## Long novels (绿野仙踪 class)

App shelves the book → `POST /api/reading/speech/book-pregen` splits the whole
text into pages and queues **both emotional CosyVoice packs** (女声
`longanfengyue` + 男声 `longze_v3.1`) for the 5060 Ti worker / ECS. The tile
shows combined progress; **opening is blocked until both voices are `ready`**.

- Prefer GPU worker (`process_on_ecs: false`)
- If GPU is offline ~90s, App calls `/book-pregen/fallback` so ECS fills gaps
- Status: `GET /api/reading/speech/book-pregen?doc_id=&voice=` (aggregates pair)
- Voice catalog: `GET /api/reading/voices` → `default_female` / `default_male` / `book_pair`

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

## Local EPUB → shelf + book TTS

Import personal novels (e.g. Harry Potter series) without putting EPUB binaries in git:

```powershell
python tools/reading/import_local_epubs.py --upload --seed-backup `
  "D:\AcquireEnglish\docs\书籍\哈利波特\*.epub"
```

- Text corpus: `media/reading/personal/{user_id}/ebooks/{series}/`
- Shelf: merges into `/api/reading-backup` (owner sync)
- Queue TTS (no ECS drain — local worker fills):

```powershell
python tools/reading/enqueue_book_tts.py --doc-id ebook-harry-potter-01 --index 1
python tools/reading/tts_worker.py
```

Packs land at `media/reading/packs/{doc_id}/{voice}/page-*.json` and sentence MP3s under `media/reading/tts/`.
