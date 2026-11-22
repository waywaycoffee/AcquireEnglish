# GPU 箱：Ollama + LiveTalking 同机

目标机：**5060 Ti**（Tailscale `100.115.252.55`）。本仓库的 Mac / 开发机**不跑**这些服务，只提交脚本与 App 预设。

## 架构

```text
手机 App (Tailscale)
  ├─ 翻译 / 字幕补全 ──▶ Ollama :11434/v1   (qwen2.5:3b)
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

当前 GPU 箱默认 **`qwen2.5:3b`**（`Qwen/Qwen2.5-3B-Instruct`，4bit，省显存）。备选：`qwen2.5:7b` / `qwen3:4b`。不要上 14B/32B。

## 在 5060 Ti 上执行

### Windows（当前 GPU 箱）

官方 Ollama 安装包约 1.7GB 且 GitHub 下载极慢时，用 **ModelScope + transformers 4bit** 起同端口兼容服务：

```powershell
cd D:\AcquireEnglish\deploy\gpu-box-ollama
powershell -ExecutionPolicy Bypass -File .\install_windows.ps1
powershell -File .\verify_windows.ps1
```

会拉取 `Qwen/Qwen2.5-3B-Instruct`，对外仍暴露 `http://0.0.0.0:11434/v1`，App 模型名 **`qwen2.5:3b`**。

### Linux（可选：官方 Ollama）

```bash
# 在 GPU 箱上，仓库已 clone 到例如 /opt/acquireenglish
cd /opt/acquireenglish/deploy/gpu-box-ollama
chmod +x install.sh verify.sh
OLLAMA_MODEL=qwen2.5:3b ./install.sh   # 安装 Ollama、拉 3b、写 systemd
MODEL=qwen2.5:3b ./verify.sh           # 健康检查 + 试翻一句
```

可选环境变量：

| 变量 | 默认 | 说明 |
|------|------|------|
| `OLLAMA_MODEL` | `qwen2.5:3b` | 拉取并设为翻译模型 |
| `OLLAMA_HOST` | `0.0.0.0:11434` | 监听地址（需 Tailscale 可达） |
| `LIVETALKING_PORT` | `8010` | 仅用于 verify 探测，不改 LiveTalking 本身 |

## App 侧

1. 手机加入同一 Tailscale。
2. 设置 → 翻译来源 → **本地 Ollama**（自动填 URL + `qwen2.5:3b`，无需真实 API Key）。
3. 「拉取模型列表」可连 GPU 箱确认已安装的 tag。
4. 字幕中文补全、查词、语法解析走同一 OpenAI 兼容接口，**无云端限流**。

## VRAM 与并发建议

- 3B 4bit 大约 2–3GB VRAM，给 LiveTalking / 阅读 TTS worker 留余量。
- 翻译请求短、并发低；陪练说话时若仍吃紧，再降并发或停非必要 worker。
- Linux `install.sh` 使用官方 Ollama 时会设 `OLLAMA_KEEP_ALIVE=10m`。

## 安全

- 只通过 Tailscale 访问，不要把 `11434` 暴露到公网。
- Ollama 不校验 Key；App 用占位符 `ollama` 即可。


## Windows 托盘监控（2026-11-16）

运行 `powershell -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File .\tray_monitor.ps1 -Install`，安装当前用户登录自启动并显示托盘图标。双击打开监控，关闭窗口收起，菜单退出仅关闭监控，不停止推理。取消自启动：使用 `-Uninstall`。

更新后台后重启推理进程，`usage_monitor.py` 随 FastAPI 启动；统计接口仅监听 `127.0.0.1:11435/stats`，不走公网代理。托盘每 5 秒刷新。SQLite 文件 `usage.sqlite3` 被 Git 忽略；按北京时间统计今日请求、失败、最近 5 分钟活跃客户端、每客户端请求和输入/输出 Token。未返回 usage 的请求单列，不伪造精确值；安装前历史用量无法追溯。

新版 App 通过匿名设备 ID 或账号邮箱哈希区分客户端，不发送明文邮箱及登录令牌。账号标识由客户端自报，不是服务端验证的身份。旧版客户端没有标识时按连接地址聚合，经过反向代理的多个用户可能合并；不能据此声称是真实在线人数。

本次已在本机加载统计模块、启动托盘并配置登录自启动。真实推理冒烟：HTTP 200，输入 33 / 输出 2 / 总计 35 Token，与统计接口一致。不需要为了统计重新加载其他陪练服务。

查词故障复现：公网接口返回 HTTP 200，但 Qwen 偶尔生成 `tag: "noun"` 这种未给字段名加双引号的 JSON。旧客户端 jsonDecode 抛错后统一显示“翻译服务不可用”。新版客户端支持此键名格式及 Markdown JSON 围栏，增加生成预算与请求超时，并通过模拟实际响应的回归测试。服务器同时兑现 json_object 请求，规范化该格式以兼容当前手机版本；更新后的 App 还增加了客户端兼容。


### 独立 Windows 应用（2026-11-17）

旧 PowerShell 宿主的托盘不易发现，现增加无终端窗口的独立 WinForms 应用。

- 编译：`powershell -NoProfile -File .\build_monitor.ps1`，生成本地 `AcquireEnglishMonitor.exe`。
- 安装入口：`powershell -NoProfile -File .\install_monitor.ps1`，创建桌面 `AcquireEnglish Monitor` 快捷方式、配置当前用户登录自启动并打开面板。
- 手动启动默认显示面板；登录启动用 `--background` 收起到托盘；关闭面板继续常驻。
- 再次双击快捷方式通过命名事件唤起已有窗口，不创建重复实例；托盘菜单可退出监控而保留推理服务。
- 本机已编译、打开窗口并通过桌面 UI 验证中文标签和真实统计数据显示。可执行文件为本地生成产物，不提交 Git。
