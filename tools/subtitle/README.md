# Subtitle fill tools（缺什么补什么）

导入课程后，App 按「缺英文 / 缺中文」入队补全。本目录**直接引入**两个开源项目作为桌面端 ASR 引擎：

| 项目 | 路径 | 用途 |
|------|------|------|
| [mateusz-kow/auto-subs](https://github.com/mateusz-kow/auto-subs) | `vendor/auto-subs` | 本地 Whisper → 按句切分 → SRT（补英文） |
| [giakinh0823/whisper-subtitle-generator](https://github.com/giakinh0823/whisper-subtitle-generator) | `vendor/whisper-subtitle-generator` | Whisper 批处理 / `write_srt` / 抽音（英文备用引擎） |

手机 APK **不能**跑 Python Whisper；移动端继续用 App 内 `whisper.cpp`（`LocalWhisperAsr`），规则相同：缺英 ASR、缺中 EN→ZH 机翻。

## 安装（macOS / Linux 开发机）

```bash
cd tools/subtitle
./bootstrap.sh
```

需要本机已安装 FFmpeg。

## CLI

```bash
.venv/bin/python fill_missing.py \
  --video /path/to/ep.mp4 \
  --out-dir /tmp/fill-out \
  --need-english \
  --model base.en
```

只缺中文时由 Flutter Worker 做 EN→ZH；本 CLI 在 `--need-chinese` 且已有 `--en-in` 时只校验/拷贝英文轨。

## 与 App 的衔接

`apps/mobile/.../external_subtitle_fill.dart` 会查找：

1. 环境变量 `ACQUIRE_SUBTITLE_TOOLS`
2. 仓库内 `tools/subtitle/fill_missing.py`（从当前工作目录向上搜）

找到且 `.venv` 可用时，导入补全 Worker **优先**走本 CLI；否则回退 on-device / 云端 ASR。
