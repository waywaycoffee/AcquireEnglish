# AcquireEnglish API

账号 / 登录（邮箱、手机号、微信）/ 课程目录 / 进度 / 词库同步。  
ASR、翻译、影子跟读、口语陪练等能力跑在 **App 端**（或可选本机 sidecar），不部署在此服务。

## 本地开发

```bash
cd services/api
python3.12 -m venv .venv
source .venv/bin/activate   # Windows: .\.venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload --host 0.0.0.0 --port 8001
```

健康检查：`GET http://127.0.0.1:8001/api/health`  
文档：`http://127.0.0.1:8001/docs`

## 生产部署

| 项 | 值 |
|----|-----|
| ECS | `root@8.163.45.100` |
| 目录 | `/opt/acquireenglish/services/api` |
| 进程 | systemd `acquireenglish-api` → `127.0.0.1:5200` |
| 公网 | `https://acquireenglish.curlhairai.com` |

```bash
cd services/api
./deploy.sh
curl -fsS https://acquireenglish.curlhairai.com/api/health
```

## App 连接

默认 `API_BASE=https://acquireenglish.curlhairai.com/`（见 `apps/mobile/lib/constants/endpoints.dart`）。  
也可在 App **设置 → 爱快账号 → 云端 API 地址** 覆盖。

### Public lexicon

The shared dictionary is a separate read-only SQLite database. The API serves
`GET /api/public-lexicon/{word}` and `GET /api/public-lexicon/{word}/audio`.
Use `PUBLIC_LEXICON_PATH` to set the snapshot location. It defaults to
`public-lexicon.sqlite3` next to the service working tree. Empty fields denote
missing source data.

Build a staging snapshot with Python and `xlrd` installed:

```sh
python scripts/build_public_lexicon.py SUBTLEXusfrequencyabove1.xls ecdict.csv eng_sentences.tsv.bz2 staging.sqlite3
python scripts/attach_lexicon_attribution.py staging.sqlite3 sentences_detailed.tar.bz2
python scripts/build_lexicon_audio.py staging.sqlite3
```

The last command needs the eSpeak NG shared library and its en-us voice data.
Build in staging, check the SQLite integrity and coverage, then atomically
rename the snapshot into place on the same filesystem. Do not commit generated
databases. Difficulty bands are frequency rank heuristics for this app.

- Frequency data: [SUBTLEX-US, Brysbaert & New (2009)](https://www.ugent.be/pp/experimentele-psychologie/en/research/documents/subtlexus).
- Dictionary: [ECDICT](https://github.com/skywind3000/ECDICT), MIT. The project
  preserves the notice in `apps/mobile/assets/dictionary/LICENSE-ECDICT.txt`.
- Examples: [Tatoeba contributors](https://tatoeba.org/en/downloads),
  [CC BY 2.0 FR](https://creativecommons.org/licenses/by/2.0/fr/). Each response
  includes the original sentence link and the contributor when available.

### Discovery audio sampling

The daily Bilibili feed checks up to three 8-second audio samples from the first
part of a video that is at least 24 seconds long. It prioritizes candidates with
at least two confident English samples and filters out candidates with a
confident non-English sample. It labels unavailable or inconclusive samples
"原声待确认".

Install FFmpeg and the whisper.cpp tools `whisper-cli` and
`whisper-vad-speech-segments`. Put the multilingual `ggml-tiny-q5_1.bin` and
`ggml-silero-v6.2.0.bin` models in `.audio-language-models` under the service
working directory, or set `AUDIO_LANGUAGE_MODELS` to that directory. See the
[whisper.cpp model and VAD instructions](https://github.com/ggml-org/whisper.cpp).
If audio or the models are unavailable, the feed can still return unverified
candidates. Samples are temporary and classification results are cached in
memory.
