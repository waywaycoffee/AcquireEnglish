# App 连接 GPU 数字人（LiveTalking）

目标：手机陪练 Tab 看到外教画面，并用 `/human` 口型播报。

## GPU 箱

```powershell
powershell -ExecutionPolicy Bypass -File tools/livetalking/run_livetalking.ps1
# 或计划任务 watchdog
```

浏览器本机打开 `http://127.0.0.1:8010/index.html` 应能看到画面。

Tailscale 地址：

- MagicDNS：`http://5060ti.tailc30b42.ts.net:8010`
- IP：`http://100.115.252.55:8010`

## 手机

1. 安装并登录 **同一 Tailscale**。
2. 设置 → 口语陪练：引擎选「视频陪练管线」或「LiveTalking」。
3. LiveTalking 地址保持 App 默认（MagicDNS）；连不上再试 IP。
4. 打开视频 → 陪练 Tab → **连接数字人** → 应出画面；点说话回合后外教口型播报。

## 常见失败

| 现象 | 原因 | 处理 |
|------|------|------|
| 连接失败 / cleartext | Android/iOS 拦明文 HTTP | 已放行 `ts.net` + Tailscale IP；重装含此配置的 APK |
| 黑屏但“已建连” | WebRTC UDP 被拦 | 检查 Tailscale；同网浏览器先过 E2E |
| 回合只用 TTS | `/human` 失败或未连上 | 看 Tab 红色错误；先点「连接数字人」 |
| session not found | 服务端替 App 调 `/human` | 不要；由 App WebRTC session 调 |

## 验收

```bash
# 任意同 tailnet 机器
python tools/livetalking/test_webrtc_e2e.py --url http://100.115.252.55:8010
```

App：连接数字人有画面 → 说话回合状态含「数字人口型播报」。
