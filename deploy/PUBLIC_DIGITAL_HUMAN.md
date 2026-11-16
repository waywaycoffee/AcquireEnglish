# 公网数字人（CurlHair 同款）

App **不需要**装 Tailscale。只需 **ECS + GPU** 同一 Tailscale 账号：

```text
手机 App ──公网 HTTPS──► ECS nginx
                              │
                              ├── /livetalking/ ──Tailscale──► GPU LiveTalking :8010
                              ├── /ollama/v1/  ──Tailscale──► GPU Qwen :11434（翻译，免费）
                              └── TURN :443 SNI ──► coturn（数字人媒体）
```

对照 CurlHair：

| CurlHair | AcquireEnglish |
|----------|----------------|
| 手机 → `https://api…` | 手机 → `https://acquireenglish.curlhairai.com/livetalking` |
| ECS API → Tailscale → Comfy `:8188` | ECS nginx → Tailscale → LiveTalking `:8010` |
| 手机从不直连 GPU | 同上；媒体经 ECS TURN |

## App

默认 LiveTalking 地址：

`https://acquireenglish.curlhairai.com/livetalking`

设置里若仍是旧 Tailscale `http://100.115.252.55:8010`，打开 App 会自动迁到公网地址。

ICE（TURN）由 oral-coach `/api/health` → `webrtc_ice_servers` 下发。

## ECS

- nginx snippet: `deploy/nginx/acquireenglish-livetalking.conf`（已 include 到 `acquireenglish` 站点）
- coturn：`deploy/coturn/`（媒体中继；CurlHair 的 Comfy 是纯 HTTP，数字人 WebRTC 多这一步）
- coach `.env`：
  - `LIVETALKING_URL=http://100.115.252.55:8010`（仅 ECS→GPU 探测）
  - `LIVETALKING_PUBLIC_URL=https://acquireenglish.curlhairai.com/livetalking`
  - `TURN_USERNAME` / `TURN_PASSWORD` / `TURN_URLS`

### 阿里云安全组（CurlHair 同款：只开 80/443）

| 端口 | 协议 | 说明 |
|------|------|------|
| 80 / 443 | TCP | HTTPS 信令 + **TURN over TLS**（`turn.curlhairai.com` SNI → coturn `:5349`） |

不需要额外放行 3478。ICE URL：`turns:turn.curlhairai.com:443?transport=tcp`。

## GPU

LiveTalking 仍只对本机/Tailscale 监听；开机脚本加载 `tools/livetalking/livetalking_turn.env.ps1`（勿提交）。
