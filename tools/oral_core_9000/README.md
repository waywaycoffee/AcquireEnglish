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
python seed_pack_subs.py                   # 用课包句生成可跟读临时 SRT（无 Whisper 时）
python upload_to_ecs.py --scp              # 上传到 ECS media/course/oral_core_9000
```

部署 API 清单：`services/api/data/oral_core_9000/manifest.json` + `content_courses` 路由。
App 打开官方课时会把 ECS `/media/course/oral_core_9000/{nn}/en.srt|zh.srt` 挂到分集。

`build_packs.py` 默认：

1. 拉 B 站分 P 元数据 / 官方字幕
2. 无英文字幕则调用本机 Whisper（CUDA）
3. 规则抽句型；有 `DEEPSEEK_API_KEY` 时生成 quiz + discuss
4. 合并回 `manifest.json`（同步到 `apps/mobile/assets/courses/` 与 `services/api/data/oral_core_9000/`）

视频优先上传 ECS（`media/course/oral_core_9000/{nn}/video.mp4`）供秒播；缺集时 App 回退 B 站流。镜像脚本：`tools/course_media/mirror_skill_videos.py`。
