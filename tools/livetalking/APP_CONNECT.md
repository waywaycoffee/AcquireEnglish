# App 连接 GPU 数字人（LiveTalking）— 公网

目标：手机**不装 Tailscale**，走公网 HTTPS 连接数字人。

## 架构

```
手机 App
  │  HTTPS
  ▼
https://acquireenglish.curlhairai.com/livetalking/
  │  nginx reverse proxy (ECS)
  ▼
http://100.115.252.55:8010   ← GPU 箱 LiveTalking（仅 ECS↔GPU 用 Tailscale）
```

- 口语管线：`https://acquireenglish.curlhairai.com/coach`（公网）
- 数字人画面：同上域名 `/livetalking`（公网）
- Tailscale 只给 **ECS 访问家里 GPU**，不要求用户手机加入

## GPU 箱

```powershell
powershell -ExecutionPolicy Bypass -File tools/livetalking/run_livetalking.ps1
```

本机打开 `http://127.0.0.1:8010/` 应 302/200。

## ECS（已部署）

- Nginx snippet：`/etc/nginx/snippets/acquireenglish-livetalking.conf`
- oral_coach `.env`：
  - `LIVETALKING_URL=http://100.115.252.55:8010`（服务端探测）
  - `LIVETALKING_PUBLIC_URL=https://acquireenglish.curlhairai.com/livetalking`（下发给 App）

探测：

```bash
# / 必须直接 200（不要 302 到 :8443）
curl -sI https://acquireenglish.curlhairai.com/livetalking/
curl -sI https://acquireenglish.curlhairai.com/livetalking/index.html
curl -s https://acquireenglish.curlhairai.com/coach/api/health
# livetalking_url 应为 https://acquireenglish.curlhairai.com/livetalking
# webrtc_ice_servers 应含 turns:turn.curlhairai.com:443
```

## 手机

1. 设置 → LiveTalking 地址留空或填  
   `https://acquireenglish.curlhairai.com/livetalking`
2. **不要**填 `100.115.*` / `*.ts.net`（那是 Tailscale，手机连不上）
3. 数字人 Tab → 连接数字人

## 常见失败

| 现象 | 原因 | 处理 |
|------|------|------|
| 连接超时到 100.115.* | App 仍用 Tailscale 地址 | 升到含公网默认的 APK；清设置里的旧地址 |
| 已建连但黑屏 | WebRTC UDP/ICE 被 NAT 拦 | 确认 GPU LiveTalking 在线；后续可加 Coturn/MediaMtx |
| `/offer` → Maximum session limit (5/5) | 僵尸 WebRTC 会话占满 | 在 GPU 箱运行 `cleanup_livetalking_sessions.ps1` 或 `restart_livetalking.ps1`；watchdog 每 90s 巡检；启动参数默认 `--max_session 10` |
| 只有 TTS / 头像无唇形 | 默认陪练管线不占 WebRTC | 正常：对话用本地头像+TTS；需要真人唇形时在设置里选 **LiveTalking** |

## 验收

```bash
curl -fsS -o /dev/null -w '%{http_code}\n' https://acquireenglish.curlhairai.com/livetalking/
# → 200（勿出现 Location: …:8443）
```

App：连接数字人有画面（或至少 `/offer` 成功）→ 说话回合有外教回复。
