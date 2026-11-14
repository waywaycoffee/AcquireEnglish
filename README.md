# AcquireEnglish

三端英文视频学习：Android / iOS App + PC 网站，账号登录后课程进度同步。

## 运行边界

| 位置 | 内容 |
|------|------|
| **服务器** `services/api` | 账号（邮箱 / 手机 / 微信）、课程目录、进度 / 词库同步 |
| **App 内** | 播放、本地 Whisper ASR、翻译 key、选词、影子跟读 UI、口语陪练（默认真机 TTS） |
| **可选本机 sidecar** | `tools/voice`、`tools/oral_coach`、`tools/digital_human_coach`（LiveKit 数字人口语外教） |
| **产品文档** | `docs/digital-human-coach/`（PRD / 时序 / 抓包手册） |

## 仓库结构

```text
apps/mobile/              Flutter（基于 TideSparrow/shadowing-english）
apps/web/                 PC 网站（React + Vite）
services/api/             账号 / 课程 / 进度 API（FastAPI）→ 部署到服务器
packages/course-schema/   三端共用课程 JSON 协议
```

## 快速开始

### API（本机）

```bash
cd services/api
python3.12 -m venv .venv
source .venv/bin/activate         # Windows: .\.venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload --host 0.0.0.0 --port 8001
```

健康检查：`http://127.0.0.1:8001/api/health`  
Swagger：`http://127.0.0.1:8001/docs`

### API（生产）

- 公网：`https://acquireenglish.curlhairai.com`（ECS `8.163.45.100`，systemd `:5200` + nginx）
- 部署：`cd services/api && ./deploy.sh`

详见 [services/api/README.md](services/api/README.md)。

### Web（需 Node 18+）

```bash
cd apps/web
npm install
npm run dev
```

Vite 已代理 `/api` → `http://127.0.0.1:8001`。

### Mobile（需 Flutter）

底座已在 `apps/mobile`。说明见 [apps/FETCH_MOBILE.md](apps/FETCH_MOBILE.md)。

```bash
cd apps/mobile
flutter pub get
# 默认已指向 https://acquireenglish.curlhairai.com/
flutter run --flavor prod
```

也可在 App **设置 → 爱快账号 → 云端 API 地址** 覆盖。

### GPU 工作站（LiveKit Agent，如 5060 Ti）

生产 oral_coach 已托管：`https://acquireenglish.curlhairai.com/coach`。  
在 GPU 机器上只跑 Agent：

```bash
git clone git@github.com:waywaycoffee/AcquireEnglish.git
cd AcquireEnglish/tools/digital_human_coach
./scripts/setup_gpu_agent.sh
# 编辑 .env：LIVEKIT_* + OPENAI_API_KEY
./scripts/run_agent.sh
```

完整步骤：[tools/digital_human_coach/DEPLOY_GPU.md](tools/digital_human_coach/DEPLOY_GPU.md)。

## 许可证

- 移动端底座源自 [TideSparrow/shadowing-english](https://github.com/TideSparrow/shadowing-english)（MIT），保留原作者致谢。
- 本仓库自有代码默认 MIT（见各子目录 LICENSE）。
