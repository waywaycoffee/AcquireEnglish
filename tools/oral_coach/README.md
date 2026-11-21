# 视频主题口语陪练管线（Oral Coach）

以**整集视频 / 全文主题**为话题做自由对话 + 虚拟外教头像（Midoo 式），不是逐句跟读。优先可插拔，默认 mock 可无 GPU 跑通 UI。

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
PRON_PROVIDER=simple       # simple | phoneme | http | wav2vec2 | mock
LLM_PROVIDER=mock          # deepseek | openai | ollama | mock
TTS_PROVIDER=mock          # qwen-audio | xtts | fishspeech | edge | mock
AVATAR_PROVIDER=livetalking  # none | livetalking | musetalk | liveportrait
LIVETALKING_URL=http://127.0.0.1:8010
```

`PRON_PROVIDER=simple` 为默认真分（词重叠 + 序列 Levenshtein，无需 GPU）。非 simple 实现多为 **adapter 壳**：填 API Key / 本机服务地址后启用。

## 阿里云百炼音色

在运行陪练服务的机器上配置 `tools/oral_coach/.env`，重启陪练服务：

```dotenv
TTS_PROVIDER=qwen-audio
DASHSCOPE_API_KEY=在服务器填写百炼API密钥
```

App 调用陪练服务，服务端使用 `qwen-audio-3.0-tts-flash`。App 和 GitHub 仓库里只配置公开的音色 ID，实际密钥留在服务端。`GET /api/health` 的 `providers.tts` 应显示 `qwen-audio`。

在服务端本机调用，以下以 Luna 的英文音色为例：

```bash
curl -fsS http://127.0.0.1:8770/api/tts/speak \
  -H 'Content-Type: application/json' \
  -d '{"text":"Hi! Let us practise English together.","digital_human_id":"luna","tts_voice":"qwen-audio-3.0-tts-flash-loonglunawang","language":"en"}'
```

响应里的 `tts_url` 是相对地址。将其拼到同一个陪练服务地址之后，用 GET 获取 MP3。线上使用陪练服务的 `/coach` 基地址。

双语试听可传 `tts_voice: longanxiaoxin`、`language: zh` 和中英混合文本。英文音色的中文回复走角色的独立中文音色。百炼调用失败时会回退到 Edge，所以健康检查和拿到 MP3 只确认陪练服务工作正常。要确认实际使用了百炼音色，还需查看陪练日志中是否出现 `Coach TTS fell back to Edge`。

- `app/providers/qwen_audio_tts.py` 中的 `VOICES`、`BILINGUAL_VOICES` 和 `PERSONA_VOICES` 定义可调用音色及默认映射。
- `app/providers/tts.py` 根据语言和音色选择合成服务。
- Flutter 的音色选单和角色推荐分别在 `coach_english_voices.dart` 和 `digital_human_catalog.dart` 中。

## 与 App

设置 →「口语陪练」选 **视频陪练管线**，填 `http://电脑局域网IP:8770`。  
陪练 Tab 会带上课程名、当前句、前后句作为 LLM 语境；接通 LiveTalking 时用数字人播报回复。
