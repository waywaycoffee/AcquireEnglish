# AcquireEnglish

三端英文视频学习：Android / iOS App + PC 网站，账号登录后课程进度同步。

## 仓库结构

```text
apps/mobile/              Flutter（基于 TideSparrow/shadowing-english）
apps/web/                 PC 网站（React + Vite）
services/api/             账号 / 课程 / 进度 API（FastAPI）
packages/course-schema/   三端共用课程 JSON 协议
```

## 快速开始

### API

```bash
cd services/api
python -m venv .venv
.\.venv\Scripts\activate          # Windows
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8001
```

健康检查：`http://127.0.0.1:8001/api/health`  
Swagger：`http://127.0.0.1:8001/docs`

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
# 本机 SDK：C:\src\flutter\bin（可加入 PATH）
flutter pub get
flutter run --flavor prod
```


## 许可证

- 移动端底座源自 [TideSparrow/shadowing-english](https://github.com/TideSparrow/shadowing-english)（MIT），保留原作者致谢。
- 本仓库自有代码默认 MIT（见各子目录 LICENSE）。
