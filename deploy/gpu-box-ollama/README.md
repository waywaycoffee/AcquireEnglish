# GPU 箱：Ollama + LiveTalking 同机

目标机：**5060 Ti**（Tailscale `100.115.252.55`）。本仓库的 Mac / 开发机**不跑**这些服务，只提交脚本与 App 预设。

## 架构

```text
手机 App (Tailscale)
  ├─ 翻译 / 字幕补全 ──▶ Ollama :11434/v1   (qwen3:8b ≈ 7B 档)
  └─ 数字人陪练 ──────▶ LiveTalking :8010
         └── 同机、同卡，按需交错占用 VRAM
```

| 服务 | 端口 | App 设置 |
|------|------|----------|
| Ollama | `11434`（OpenAI 兼容 `/v1`） | 翻译来源 → **本地 Ollama** |
| LiveTalking | `8010` | 口语陪练 → LiveTalking URL |

默认 Base URL（已写入 App）：

- Ollama：`http://100.115.252.55:11434/v1`
- LiveTalking：`http://100.115.252.55:8010`

## 模型选择

用户口头说的「qwen3:7b」在 Ollama 官方库对应 **`qwen3:8b`**（~5.2GB，Q4）。  
同机还要跑 LiveTalking，**不要**上 14B/32B；VRAM 紧张可改 `qwen3:4b` 或 `qwen2.5:7b`。

## 在 5060 Ti 上执行（不要在本机跑）

```bash
# 在 GPU 箱上，仓库已 clone 到例如 /opt/acquireenglish
cd /opt/acquireenglish/deploy/gpu-box-ollama
chmod +x install.sh verify.sh
./install.sh          # 安装 Ollama、拉 qwen3:8b、写 systemd、放行 Tailscale
./verify.sh           # 健康检查 + 试翻一句
```

可选环境变量：

| 变量 | 默认 | 说明 |
|------|------|------|
| `OLLAMA_MODEL` | `qwen3:8b` | 拉取并设为翻译模型 |
| `OLLAMA_HOST` | `0.0.0.0:11434` | 监听地址（需 Tailscale 可达） |
| `LIVETALKING_PORT` | `8010` | 仅用于 verify 探测，不改 LiveTalking 本身 |

## App 侧

1. 手机加入同一 Tailscale。
2. 设置 → 翻译来源 → **本地 Ollama**（自动填 URL + `qwen3:8b`，无需真实 API Key）。
3. 「拉取模型列表」可连 GPU 箱确认已安装的 tag。
4. 字幕中文补全、查词、语法解析走同一 OpenAI 兼容接口，**无云端限流**。

## VRAM 与并发建议

- 先起 LiveTalking，再 `ollama run qwen3:8b` 看剩余显存。
- 翻译请求短、并发低；陪练说话时若 OOM，可把 Ollama 的 `num_gpu` / 上下文调小，或临时停 LiveTalking 测翻译。
- `install.sh` 会设置 `OLLAMA_KEEP_ALIVE=10m`，闲置后卸模型，给数字人让路。

## 安全

- 只通过 Tailscale 访问，不要把 `11434` 暴露到公网。
- Ollama 不校验 Key；App 用占位符 `ollama` 即可。
