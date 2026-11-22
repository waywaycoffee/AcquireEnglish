# oral_core_9000 内容管线（本机 5060 Ti → ECS）

官方课「英语核心口语句型9000句」（`BV1CS4y1v7sQ`，151 课）。

## 产物

- `manifest.json`：系列清单（App asset / API `data/oral_core_9000/` 同源）
- `media/course/oral_core_9000/{nn}/en.srt|zh.srt`：字幕（ECS `course` namespace）
- 每课 `pack`：句型 / 跟读 / quiz / discuss（写入 manifest）

## 本机步骤

```powershell
cd D:\AcquireEnglish\tools\oral_core_9000
python build_packs.py --pages 1-5          # 先验证前 5 课
python build_packs.py --pages 1-151        # 全量（需 GPU ASR 时缺 CC）
python upload_to_ecs.py                    # 上传 srt + 刷新 API 侧 manifest
```

`build_packs.py` 默认：

1. 拉 B 站分 P 元数据 / 官方字幕
2. 无英文字幕则调用本机 Whisper（CUDA）
3. 规则抽句型；有 `DEEPSEEK_API_KEY` 时生成 quiz + discuss
4. 合并回 `manifest.json`（同步到 `apps/mobile/assets/courses/` 与 `services/api/data/oral_core_9000/`）

视频**不**上传 ECS；播放仍走 B 站源。
