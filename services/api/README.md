# AcquireEnglish API

FastAPI 服务：注册/登录、课程目录、学习进度、单词本。

```bash
cd services/api
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
uvicorn app.main:app --reload --port 8001
```

健康检查：`GET http://127.0.0.1:8001/api/health`

文档：`http://127.0.0.1:8001/docs`
