# 5060 Ti / GPU 工作站部署 LiveKit Agent

生产 API 与 oral_coach 已在 ECS：

- API：`https://acquireenglish.curlhairai.com`
- oral_coach：`https://acquireenglish.curlhairai.com/coach`

本机（5060 Ti）只跑 **LiveKit Agent worker**，不需要再部署整站。

## 1. 拉取仓库

```bash
git clone git@github.com:waywaycoffee/AcquireEnglish.git
# 或 HTTPS: https://github.com/waywaycoffee/AcquireEnglish.git
cd AcquireEnglish/tools/digital_human_coach
./scripts/setup_gpu_agent.sh
```

要求：Python **3.11 或 3.12**（避开 3.14）、能访问外网。默认 LLM 用 **DeepSeek**（不用 OpenAI），**不必先装 CUDA**；以后本地 WhisperX 再开 GPU。

## 2. 填 `.env`

```bash
cp -n .env.example .env
$EDITOR .env
```

必填：

| 变量 | 来源 |
|------|------|
| `LIVEKIT_URL` | LiveKit Cloud → Project → Keys（`wss://…`） |
| `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` | 同上 |
| `DEEPSEEK_API_KEY` | [platform.deepseek.com](https://platform.deepseek.com/api_keys)（默认 LLM，**不用 OpenAI**） |

语音（二选一，都不用 OpenAI）：

| 方案 | 变量 | 说明 |
|------|------|------|
| Edge TTS（默认） | `TTS_PROVIDER=auto` + 本机 `ffmpeg` | 免费；听写 STT 仍建议配 Deepgram |
| Deepgram | `DEEPGRAM_API_KEY` | 注册送额度，STT+TTS 一把钥匙 |

可保持默认：

- `LLM_PROVIDER=deepseek`
- `ORAL_COACH_URL=https://acquireenglish.curlhairai.com/coach`
- `LEARNING_API_URL=https://acquireenglish.curlhairai.com/api/learning`

## 3. 同步 LiveKit 到 API 服务器

在 ECS `/opt/acquireenglish/services/api/.env` 写入**同一套**三件套，然后：

```bash
systemctl restart acquireenglish-api
curl -fsS https://acquireenglish.curlhairai.com/api/livekit/status
# → {"configured":"true"}
```

## 4. 启动 Agent

```bash
./scripts/run_agent.sh
```

保持该进程在线。Cloud 控制台应能看到 worker `acquire-oral-coach`。

## 5. App

1. 登录生产账号  
2. 设置 → LiveKit 房间地址 = 同一个 `wss://…`  
3. 口语陪练管线地址保持 `https://acquireenglish.curlhairai.com/coach`  
4. 开始会话：应显示 `LiveKit + HTTP 管线`

## 架构速记

```
App ──JWT──▶ API /api/livekit/token
App ──wss──▶ LiveKit Cloud
Agent(本机) ──同房间── VAD / LLM / TTS
         └──HTTP──▶ /coach（发音）+ /api/learning
```

## 可选：本机 oral_coach + GPU ASR

仅当你要本机 WhisperX 时：

```bash
cd ../oral_coach
./bootstrap.sh
# .env: ASR_PROVIDER=whisperx  WHISPERX_MODEL=small.en
./run_server.sh
# 再把 Agent .env 的 ORAL_COACH_URL 改成 http://127.0.0.1:8770
```
