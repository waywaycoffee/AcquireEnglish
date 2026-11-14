# Digital Human Oral Coach

数字人口语外教完整栈编排（相对 `tools/oral_coach` 的「单回合 HTTP」升级）。

| 层 | 技术 | 目录 |
|----|------|------|
| 实时基座 | LiveKit Agents + VAD 打断 | `agent/` |
| 能力 | WhisperX / wav2vec2 / 第三方评测 / MuseTalk·LivePortrait | 复用 `../oral_coach/app/providers` |
| 业务 | ChatterPal 式任务·错题·复习 | `learning/` |
| 文档 | PRD / 时序 / 抓包 | `../../docs/digital-human-coach/` |

## 快速骨架

```bash
cd tools/digital_human_coach
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env

# 业务层单测（无需 LiveKit）
pytest learning/tests -q

# LiveKit Agent（需 LIVEKIT_* 与真实/mock 插件）
python -m agent.main download-files   # 首次
python -m agent.main start
```

**5060 Ti / GPU 工作站一键部署**见 [`DEPLOY_GPU.md`](./DEPLOY_GPU.md)：

```bash
./scripts/setup_gpu_agent.sh   # venv + requirements-agent.txt
# 编辑 .env 填 LIVEKIT_* + OPENAI_API_KEY
./scripts/run_agent.sh
```

App 侧：设置填同一 `wss://`；数字人画面仍可接 LiveTalking WebRTC。

## 与 oral_coach 关系

- **oral_coach**：`POST /turn` 回合制，适合无 GPU 先跑通 UI。
- **本目录**：全双工 Agent + 学习闭环；能力层 import oral_coach providers，避免双份适配器。

## ChatterPal

业务语义对齐 [likebeans/ChatterPal](https://github.com/likebeans/ChatterPal)（MIT）：转写核对、原话反馈、单句重练、间隔复习。  
此处为 **嵌入式精简实现**（SQLite），完整 UI/任务包可后续 `git submodule` 引入 upstream。
