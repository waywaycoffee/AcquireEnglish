# 音视频：ECS 存储与按需播放

## 原则

| 允许 | 禁止 |
|---|---|
| API/ECS 磁盘保存 `.mp3` / `.mp4` 等 | 打进 `apps/mobile/assets` |
| App 经 manifest/lookup 拿 URL 后流式播放 | 第三方音视频原文件随包分发 |
| 文本 JSON/TXT/CSV/EPUB 按需下载到本地缓存 | 把 Magic/GitHub 的 mp3 拷进工程 |

## 磁盘布局

```
{media_cache_dir}/
  foundation/{book_id}/{key}.mp3|.mp4
  reading/{pack_id}/{doc_or_slug}.mp3|.mp4
  oral/...
  course/...
  misc/...
  exam/{family_id}/{sha256[:2]}/{sha256}.ext   # 社区真题资料
  imports/{import_id}/study.m4a   # 外链课缓存，服务端生成
```

公开基址：`MEDIA_PUBLIC_BASE`（默认 `https://acquireenglish.curlhairai.com`）。

## API

- `GET /api/content/media/manifest?namespace=reading`
- `GET /api/content/media/lookup?namespace=reading&book_id=…&key=…`
- `POST /api/content/media/upload`（form: `namespace`, `book_id`, `key`, `file`）
- 社区真题：`GET/POST /api/community/exam-assets`（`exam` 命名空间，含文本/音视频）
- 兼容：`/api/foundation/media/*` → `namespace=foundation`
- 静态：`GET /media/{namespace}/…`

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
