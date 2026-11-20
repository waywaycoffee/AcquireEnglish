# 零基础真人音视频（服务器托管）

App **不内嵌** IPA / 自然拼读真人示范；上传到 API 服务器后按网络地址播放。

## 目录约定

服务器 `MEDIA_CACHE_DIR`（默认 `./media`）下：

```
media/foundation/{book_id}/{safe_key}.mp3|.m4a|.wav   # 音频
media/foundation/{book_id}/{safe_key}.mp4|.webm|.mov  # 视频
```

- `book_id`：与内置书一致，如 `foundation_ipa_48`、`foundation_phonics_combos`
- `safe_key`：条目英文键的规范化形式（小写、空格变 `-`），须与书中 `word` 字段对应  
  例：书中 `short a` → 文件 `short-a.mp3`

上传后自动重建 `media/foundation/manifest.json`。

## HTTP API

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/foundation/media/manifest` | 清单（含绝对 URL） |
| GET | `/api/foundation/media/lookup?book_id=&key=` | 单条查找 |
| POST | `/api/foundation/media/upload` | 登录后 multipart：`book_id` + `key` + `file` |
| GET | `/media/foundation/...` | 静态直链（nginx / StaticFiles） |

`media_public_base`（默认 `https://acquireenglish.curlhairai.com`）用于拼绝对 URL。

## 上传示例

```bash
TOKEN='登录后的 Bearer token'
curl -X POST "https://acquireenglish.curlhairai.com/api/foundation/media/upload" \
  -H "Authorization: Bearer $TOKEN" \
  -F "book_id=foundation_ipa_48" \
  -F "key=short a" \
  -F "file=@/path/to/short-a.mp4;type=video/mp4"
```

也可用本目录脚本：

```bash
python tools/foundation_media/upload_file.py \
  --base https://acquireenglish.curlhairai.com \
  --token "$TOKEN" \
  --book foundation_ipa_48 \
  --key "short a" \
  --file ./demos/short-a.mp4
```

## App 行为

复习页优先播清单里的 `audio_url`；有 `video_url` 时显示「看真人示范视频」。
无远程文件时回退 TTS / 词库发音。
