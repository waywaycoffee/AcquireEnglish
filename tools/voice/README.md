# Voice practice sidecar（影子跟读 / 口语练习）

直接引入开源项目 [Zemksh/voice](https://github.com/Zemksh/voice)：本机 Whisper 转写 +（可选）Ollama Gemma 量规反馈。

手机 APK **不能**内嵌 faster-whisper / Ollama；跟读 Tab 在设置了服务地址后，把录音上传到本机/局域网 sidecar。

| 能力 | 路径 | 说明 |
|------|------|------|
| 句级影子跟读 | `POST /api/shadow` | 参考英文句 + 录音 → 转写 + 词重叠分（无需 Gemma） |
| 话题口语练习 | 上游 `/api/sessions*` | 60–90 秒自由说 → 转写 → Gemma 四维评分 |
| 健康检查 | `GET /api/health` | ffmpeg / whisper / ollama 就绪状态 |

## 安装（macOS / Linux 开发机）

```bash
cd tools/voice
./bootstrap.sh
```

需要：FFmpeg、Python 3.11+。句级跟读可先 `MOCK_MODE=true` 或只准备 Whisper；完整话题评分再装 Ollama + `GEMMA_MODEL`。

## 启动（允许手机访问）

```bash
./run_server.sh
# 默认 http://0.0.0.0:8765 ，健康检查 http://127.0.0.1:8765/api/health
```

App「更多 → 设置 → Voice 本地口语」填例如 `http://192.168.1.8:8765`。

## 与 App 的衔接

`apps/mobile/.../voice_practice_client.dart` 调用 `/api/shadow`；跟读 Tab 录音后可点「Voice 反馈」。
