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

验收应同时核对队列 completed 和公共库中英文字幕，避免仅以进程退出判断成功。该流程仍依赖 B 站可获取的音轨与合法访问权限；无音轨的任务会重试后失败。
