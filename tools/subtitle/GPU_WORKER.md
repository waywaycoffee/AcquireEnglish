# 本机 GPU 公共字幕 worker

架构：App 在开始下载视频时并行查询公共字幕，未命中后提交 ECS 持久队列；本机经 SSH 领取任务，RTX 5060 Ti 用 faster-whisper small.en 转写；英文文本交给 ECS 已配置的 DeepSeek 翻译；中英时间轴对齐并通过公共字幕质量门槛后入库。手机视频仍须用户手工点击下载。下载后的字幕补全再次查询公共库并应用已生成字幕；当前不提供云端进度实时推送。

Windows 安装（Python 3.11+，NVIDIA 驱动已安装）：

```powershell
python -m venv tools/subtitle/.venv
tools/subtitle/.venv/Scripts/python.exe -m pip install -r tools/subtitle/requirements-gpu.txt
tools/subtitle/.venv/Scripts/python.exe tools/subtitle/gpu_worker.py
```

CUDA 12/cuDNN DLL 安装在隔离环境中，无须修改系统 CUDA。首次运行会下载 Whisper 模型；模型不进入 APK。SSH 别名 acquireenglish 必须支持免交互登录。翻译密钥只从 ECS 口语服务配置读取，不传回本机。

POST /api/shared-subtitles/jobs（登录）提交 {bvid,page}，重复视频分集复用同一任务；GET /api/shared-subtitles/jobs/{id} 查询 queued/transcribing/translating/completed/failed。每 120 秒续租，20 分钟租约超时可接管，最多尝试 4 次。本机关机时任务保留，worker 恢复后继续领取。临时音频转写结束即清理。

**EN→ZH 必须本机跑**：`SUBTITLE_LLM_MODEL` 默认 `qwen2.5:3b`（与 `deploy/gpu-box-ollama` 一致）。ECS 默认**禁止** DeepSeek/云端翻译回退；仅当显式设置 `SUBTITLE_ALLOW_CLOUD_TRANSLATE=1` 才允许。

当前可直接运行 worker 命令持续监听。未配置开机自动启动；电脑重启后需重新运行该命令。

Worker 会通过 heartbeat 上报 `progress_pct` / `progress_message`（准备音频 → 识别 → 翻译 → 入库），App 轮询 `GET /api/shared-subtitles/jobs/{id}` 展示进度条与文案。

## 合集预约

B 站长合集预约可先写入 `deferred` 状态，工作站会在同一视频的在途分 P 处理完后继续领取。App 关闭后，已提交的任务仍保留在 ECS。

YouTube 集合的分集任务由新版 worker 使用同一虚拟环境里的 `yt-dlp` 读取音频。工作站网络必须能访问 YouTube。识别和翻译在工作站完成，字幕保存到预约账号的个人云字幕库。上线时先更新工作站 worker 和依赖，再更新 ECS API。

## 批量补推荐片源公共字幕

推荐列表里不少合集只有部分分 P 有共享字幕。可在 **ECS** 把缺 EN 的分 P 推进 GPU 队列，由本机 5060 Ti 消化后写入公共库：

```bash
# 先尽量灌官方软字幕（有官方轨就不用 GPU）
cd /opt/acquireenglish/services/api
.venv/bin/python /opt/acquireenglish/tools/subtitle/seed_recommended_bilibili_subs.py

# 再把仍缺 EN 的推荐分 P 入队（默认最多 48 条；合集受每 BV 12 条在途上限）
.venv/bin/python /opt/acquireenglish/tools/subtitle/enqueue_recommended_missing_gpu_subs.py
.venv/bin/python /opt/acquireenglish/tools/subtitle/enqueue_recommended_missing_gpu_subs.py --dry-run
.venv/bin/python /opt/acquireenglish/tools/subtitle/enqueue_recommended_missing_gpu_subs.py --bvid BV1fV4y1p7Ex
```

Windows 保持 `gpu_worker.py` 常开；队列消化完后可再跑一遍 enqueue，把大合集后续分 P 补齐。

验收应同时核对队列 completed 和公共库中英文字幕，避免仅以进程退出判断成功。该流程仍依赖 B 站可获取的音轨与合法访问权限；无音轨的任务会重试后失败。
