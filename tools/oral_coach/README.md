# 视频主题口语陪练管线（Oral Coach）

以**当前视频 / 当前句**为话题，组装流畅实时对话 + 虚拟外教头像。优先可插拔，默认 mock 可无 GPU 跑通 UI。

> **完整产品栈（LiveKit 全双工 + ChatterPal 学习闭环 + 竞品 PRD）**  
> 见 [`../digital_human_coach/`](../digital_human_coach/) 与 [`../../docs/digital-human-coach/`](../../docs/digital-human-coach/)。  
> 本目录继续作为**能力 providers**（ASR / 发音 / LLM / TTS / 数字人）与回合制 HTTP 原型。

## 目标栈

| 环节 | 首选实现 | 备用 / 现状 |
|------|----------|-------------|
| 实时基座 | LiveKit Agents（见 digital_human_coach） | 本目录 HTTP `/turn` |
| ASR | WhisperX / Deepgram | `mock`（内置） |
| 发音打分 | wav2vec2 微调 / phoneme alignment / 第三方 API | `mock` |
| LLM | 角色 + 自适应难度 + 纠错 | `mock` / OpenAI 兼容 / Ollama |
| TTS | XTTS / FishSpeech | `mock`（返回静音占位）/ edge |
| 数字人 | MuseTalk / LivePortrait | LiveTalking（App 已接 WebRTC） |
| 业务闭环 | ChatterPal 模式（digital_human_coach/learning） | — |

上游影子跟读 sidecar 见 `tools/voice`（[Zemksh/voice](https://github.com/Zemksh/voice)）。本目录是**能力 + 回合编排**：吃视频上下文，驱动一轮「听→评→说→驱动头像」。

## 回合

```
App ──视频上下文──▶ POST /api/sessions
App ──跟读/说话音频──▶ POST /api/sessions/{id}/turn
                      ASR → 发音 → LLM → TTS
App ◀── transcript / scores / coach_text / tts_url / avatar_cue
App ──(可选)──▶ LiveTalking /human 播报 coach_text
```

## 快速开始

```bash
cd tools/oral_coach
./bootstrap.sh
./run_server.sh
# http://127.0.0.1:8770/api/health
```

`.env` 里切 Provider，例如：

```bash
ASR_PROVIDER=mock          # whisperx | deepgram | mock
PRON_PROVIDER=mock         # wav2vec2 | phoneme | mock
LLM_PROVIDER=mock          # openai | ollama | mock
TTS_PROVIDER=mock          # xtts | fishspeech | edge | mock
AVATAR_PROVIDER=livetalking  # none | livetalking | musetalk | liveportrait
LIVETALKING_URL=http://127.0.0.1:8010
```

非 mock 实现多为 **adapter 壳**：填 API Key / 本机服务地址后启用；权重与模型需自行安装（见各 `providers/*/README` 注释）。

## 与 App

设置 →「口语陪练」选 **视频陪练管线**，填 `http://电脑局域网IP:8770`。  
陪练 Tab 会带上课程名、当前句、前后句作为 LLM 语境；接通 LiveTalking 时用数字人播报回复。
