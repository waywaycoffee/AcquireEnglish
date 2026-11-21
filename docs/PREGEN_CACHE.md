# 预生成缓存落地（省 Token）

按顺序：推荐课字幕共享 → 阅读 TTS 内容寻址 → 话题/词卡/句译表 → 静态语块 gloss。

## 1. 推荐课字幕共享

- 存储：Postgres `shared_bilibili_subtitles`（非 media 文件）
- App：官方软字幕 → `GET /api/shared-subtitles/bilibili` → 本地 ASR
- ASR 完成后：`syncEpisodeSubtitlesToCloud` 会尝试 `PUT` 共享（需登录）
- ECS 播种官方轨：

```bash
cd /opt/acquireenglish/services/api
.venv/bin/python tools/subtitle/seed_recommended_bilibili_subs.py --dry-run
.venv/bin/python tools/subtitle/seed_recommended_bilibili_subs.py
.venv/bin/python tools/subtitle/_ecs_shared_health_check.py
```

目录 `seed_pages` 已生效（`all` / `1-3` / `[1,2]`）。

## 2. 阅读 TTS 内容寻址

- 陪练侧：`tools/oral_coach` 将相同 `persona|voice|lang|text` 落到 `data_dir/tts/cache/{sha}.mp3`
- API 侧：`GET /api/reading/speech/lookup`、`POST /api/reading/speech/upload` → `media_cache_dir/reading/tts/{voice}/{sha}.mp3`
- App：`speakReadingText` 先查 ECS lookup，再走陪练 `/api/tts/speak`（自带缓存），最后本机 TTS

批量预生成示例（在能调用 CosyVoice 的环境）：对阅读语料逐句 `speak`，或合成后 `POST /api/reading/speech/upload`。

## 3. 话题 / 词卡 / 句译表

JSON 文件缓存：`media_cache_dir/misc/pregen/`

| 资源 | API |
|------|-----|
| 句译 | `GET/PUT /api/pregen/sentences` |
| 词卡 enrichment | `GET/PUT /api/pregen/vocab/{word}` |
| 口语话题 | `GET/PUT /api/pregen/oral-topics/{key}` |

## 4. 静态语块 gloss

```bash
python tools/syllabus/fill_chunks_gloss.py
```

从 ECDICT 填充 `services/api/data/syllabus/chunks_conversational_1000.json` 的空 `gloss`。

## 5. 扫描版 PDF OCR + 云端图书库

- 本地：`flutter_ocr_native` 渲染页面 + OCR（最多 120 页）
- 流程：文字层 → `GET /api/shared-ocr-books?content_sha256=` → 本机 OCR → 登录后 `PUT` 共享
- 表：`shared_ocr_books`（按文件 sha256 去重，更长/更高质量可覆盖）
