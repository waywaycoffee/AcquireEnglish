# 抓包手册：REA + ADB + mitmproxy（Hi Echo / Midoo）

**目的**：把竞品「交互时序」从假设升级为观测，写入 PRD / interaction-sequences。  
**范围**：产品流程与协议形态分析，用于自研对照；不提取密钥破解、不绕过付费。

## 0. 前置

| 项 | 说明 |
|----|------|
| 手机 | USB 调试开；`adb devices` 可见 |
| 包名 | Hi Echo：`com.youdao.dict.feature_speaker`；Midoo：`com.midoo.ai` |
| 证书 | mitmproxy CA 已装到用户/系统证书（Android 7+ 用户证书常被忽略，优先用可调试/Frida 或模拟器） |
| 工具 | REA MCP（本机已接）、adb、mitmproxy / mitmdump、可选 Wireshark |

当前会话状态：**无 ADB 设备** → 无法执行 O1–O5，仅保留本手册。

## 1. 设备与安装

```bash
adb devices -l
adb shell pm path com.youdao.dict.feature_speaker
adb shell pm path com.midoo.ai
# 若未装：从官方商店安装后再拉 APK 备份（仅自用分析）
adb shell pm path <pkg>
adb pull <apk-path> ./captures/<pkg>.apk
```

REA：

- `list_adb_devices` → `list_adb_packages` / `inspect_adb_package`
- 对 APK：`inspect_android_package` → 搜 WebRTC / okhttp / 信令类名
- 需要运行时：`start_adb_app` + `observe_native_calls` / `capture_process_scenario`（按 REA 工具 schema）

## 2. mitmproxy 时序抓取

```bash
# 电脑
mitmweb --listen-port 8080 --web-port 8081 \
  --set store_streamed_bodies=true \
  -w ./captures/hi-echo-$(date +%Y%m%d).flow

# 手机 Wi-Fi 代理 → 电脑局域网 IP:8080
# 浏览一次目标流程：开聊 → 打断 → 看评分 → 出报告 → 退出
```

建议标注的用户动作时间戳（秒表 / 屏幕录制）：

1. 点「开始对话」
2. 外教首句出声
3. 用户插话打断
4. 外教停下
5. 评分卡片出现
6. 结束并打开报告

将 HAR/flow 与录屏对齐后填 [interaction-sequences.md](./interaction-sequences.md) 观测表。

## 3. 关注的流量特征

| 信号 | 可能含义 |
|------|----------|
| `wss://` + SDP / ice | WebRTC 信令 |
| LiveKit / Agora / TRTC / 自研 room | 实时底座厂商 |
| 短轮询 `/asr` `/chat` | 非全双工或半双工 |
| 音频 `multipart` 上传 | 回合制（类当前 oral_coach） |
| 评分 path 含 `pronunciation` / `phoneme` | 评测时机 |

## 4. 产出物清单

写入 `docs/digital-human-coach/captures/`（勿提交含 cookie 的 raw flow）：

- `YYYYMMDD-hiecho-notes.md`：时间线（动作 ↔ 请求）
- 脱敏 HAR 摘要（去 Authorization / Cookie）
- REA Evidence id 列表
- 更新 PRD §10、interaction-sequences §7 状态为 **O**

## 5. 一键脚本（设备在线时）

```bash
./tools/digital_human_coach/scripts/check_capture_ready.sh
```

仅检查 adb / 包是否安装 / 目录是否可写，不自动开 mitm。
