# AcquireEnglish API

账号 / 登录（邮箱、手机号、微信）/ 课程目录 / 进度 / 词库同步。  
ASR、翻译、影子跟读、口语陪练等能力跑在 **App 端**（或可选本机 sidecar），不部署在此服务。

## 本地开发

```bash
cd services/api
python3.12 -m venv .venv
source .venv/bin/activate   # Windows: .\.venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload --host 0.0.0.0 --port 8001
```

健康检查：`GET http://127.0.0.1:8001/api/health`  
文档：`http://127.0.0.1:8001/docs`

## 生产部署

| 项 | 值 |
|----|-----|
| ECS | `root@8.163.45.100` |
| 目录 | `/opt/acquireenglish/services/api` |
| 进程 | systemd `acquireenglish-api` → `127.0.0.1:5200` |
| 公网 | `https://acquireenglish.curlhairai.com` |

```bash
cd services/api
./deploy.sh
curl -fsS https://acquireenglish.curlhairai.com/api/health
```

## App 连接

默认 `API_BASE=https://acquireenglish.curlhairai.com/`（见 `apps/mobile/lib/constants/endpoints.dart`）。  
也可在 App **设置 → 爱快账号 → 云端 API 地址** 覆盖。
