# 音视频：OSS（主）/ ECS 缓存 与按需播放

## 原则

| 允许 | 禁止 |
|---|---|
| 阿里云 OSS 保存 `.mp3` / `.mp4` / PDF 等（主存储） | 打进 `apps/mobile/assets` |
| ECS `{media_cache_dir}` 作迁移期本地缓存 | 第三方音视频原文件随包分发 |
| App 经 manifest/lookup 拿 URL 后流式播放 | 把 Magic/GitHub 的 mp3 拷进工程 |
| 文本 JSON/TXT/CSV/EPUB 按需下载到本地缓存 | 把 `*.sqlite3` 任务库上传到 OSS |

## 首页技能模块（秒播）

官方技能课（国际音标 / 美式音标 / 自然拼读 / 核心口语9000句）的视频与字幕落在：

```
media/course/{series_id}/{nn}/video.mp4
media/course/{series_id}/{nn}/en.srt
media/course/{series_id}/{nn}/zh.srt
```

App 打开单集时：

1. HEAD 探测 ECS `video.mp4` → 有则 **HTTP Range 流式秒播**（不下载整集）
2. 同步 GET ECS `en.srt` / `zh.srt` 进内存解析（小文件，无本机落盘）
3. ECS 缺视频时回退 B 站 **流式**播放（仍不「先下后学」）

运维：

```bash
# 从 shared_bilibili_subtitles 物化字幕到 course/
PYTHONPATH=/opt/acquireenglish/services/api \
  /opt/acquireenglish/services/api/.venv/bin/python \
  /opt/acquireenglish/tools/course_media/materialize_skill_subs_from_shared.py

# 本机 5060 Ti 镜像视频后再 scp 到 ECS（见 tools/course_media/mirror_skill_videos.py）
```

## 磁盘布局

```
{media_cache_dir}/
  foundation/{book_id}/{key}.mp3|.mp4
  reading/{pack_id}/{doc_or_slug}.mp3|.mp4
  reading/textbooks/{book_id}/book.pdf|book.json|audio/*.mp3  # K12 有声教材（本地点选上传）
  oral/...
  course/...
  misc/...
  exam/{family_id}/{sha256[:2]}/{sha256}.ext   # 社区真题资料
  imports/{import_id}/study.m4a   # 外链课缓存，服务端生成
```

公开基址：`MEDIA_PUBLIC_BASE`（默认 `https://acquireenglish.curlhairai.com`）。  
启用 OSS 后，manifest 里的播放 URL 优先用 `OSS_PUBLIC_BASE`（或 `https://{bucket}.{endpoint}/…`）。

## 迁到阿里云 OSS

1. 控制台创建 Bucket（建议与 ECS 同区域，如 `oss-cn-guangzhou`），容量按套餐（如 500GB）。
2. 建 RAM 用户，授予该 Bucket 的 `oss:PutObject` / `GetObject` / `ListObjects` / `DeleteObject`（勿用短信专用 AK）。
3. Bucket 读权限：公共读，或私有 + CDN 回源；把对外 HTTPS 基址写入 `OSS_PUBLIC_BASE`。
4. 在 API 机 `services/api/.env` 配置：

```bash
OSS_ENABLED=1
OSS_ACCESS_KEY_ID=...
OSS_ACCESS_KEY_SECRET=...
OSS_ENDPOINT=oss-cn-guangzhou.aliyuncs.com
OSS_BUCKET=your-bucket
OSS_KEY_PREFIX=media
OSS_PUBLIC_BASE=https://your-bucket.oss-cn-guangzhou.aliyuncs.com
OSS_KEEP_LOCAL_CACHE=1
```

5. 安装依赖并全量上传（约数 GB，可重复跑）：

```bash
cd /opt/acquireenglish/services/api
.venv/bin/pip install -q oss2
.venv/bin/python scripts/migrate_media_to_oss.py --dry-run
.venv/bin/python scripts/migrate_media_to_oss.py --skip-existing
systemctl restart acquireenglish-api
```

6. 抽查一条 URL（manifest / `OSS_PUBLIC_BASE/...`）能 Range 播放后，再把 `OSS_KEEP_LOCAL_CACHE=0`，并视情况清理 ECS 本地副本（`--delete-local-after` 仅在确认无误后使用）。

对象键：`media/{namespace}/…`（与本地相对路径一致）。任务库 `reading-tts-jobs.sqlite3` 等留在 ECS。

## API

- `GET /api/content/media/manifest?namespace=reading`
- `GET /api/content/media/lookup?namespace=reading&book_id=…&key=…`
- `POST /api/content/media/upload`（form: `namespace`, `book_id`, `key`, `file`）
- 社区真题：`GET/POST /api/community/exam-assets`（`exam` 命名空间，含文本/音视频）
- 兼容：`/api/foundation/media/*` → `namespace=foundation`
- 静态：`GET /media/{namespace}/…`

### Nginx `/media/` 必须指向 API 缓存目录

生产机 uvicorn 工作目录下的 `{media_cache_dir}` 通常是  
`/opt/acquireenglish/services/api/media/`。  
`location /media/` 的 `alias` 必须与此一致（见 `deploy/nginx/acquireenglish-media.conf`），  
不要指到空的 `/opt/acquireenglish/media/`，否则阅读/背词 TTS 会返回 200 URL 但播放 404。

## 上传示例

```bash
curl -X POST "$API/api/content/media/upload" \
  -F namespace=reading \
  -F book_id=magic \
  -F key=story-01 \
  -F file=@story-01.mp3
```

上传后 App 通过 `contentMediaManifest(namespace: 'reading')` 解析 `audio_url` / `video_url` 播放。

## 与阅读书库的关系

在线书库只拉取**文本**（OneStop / CEFR / Magic 文案 / Standard Ebooks EPUB）。配套朗读须运营上传到 `reading` 命名空间；客户端用 `readingContentMediaProvider` 查找，不从 GitHub 拉音频进包。

### K12 有声教材

本机 PDF + 同目录 MP3 经 `tools/k12_textbooks/` 打包上传到 `reading/textbooks/`。  
清单：`GET /api/reading/textbooks`；册次：`GET /api/reading/textbooks/{book_id}`。  
勿把整盘「教材」镜像进 ECS，只上传点选册次。详见该目录 README。

## 阅读页 TTS 预生成（手机不扛合成）

打开读物后，App 调用 `POST /api/reading/speech/pregen`，把**当前页**排队。ECS 后台或 5060 Ti worker（`tools/reading/tts_worker.py`）逐句合成，写入：

| 位置 | 用途 |
|---|---|
| `reading/tts/{voice}/{hash}.mp3` | 内容寻址共享缓存（全站复用） |
| `reading/packs/{doc}/{voice}/page-{n}.json` | 共享库：页→句→URL |
| `reading/personal/{user_id}/packs/...` | 个人库：该用户已就绪页指针 |

长篇小说 `book-pregen` **固定排队两套有感情音色**：女声 `longanfengyue`、男声 `longze_v3.1`，各自落到 `packs/{doc}/{voice}/`。`GET /api/reading/voices` 返回 `default_female` / `default_male` / `book_pair`。

下次打开同一页可直接播缓存 URL，避免手机端整本切句 + 现合成导致闪退。
