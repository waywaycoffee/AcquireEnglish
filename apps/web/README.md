# AcquireEnglish Web (PC)

React + Vite PC 网站：登录后浏览云课程并进入学习页。

## 运行

需要 Node.js 18+。

```bash
cd apps/web
npm install
npm run dev
```

默认通过 Vite 代理访问 `http://127.0.0.1:8000` 的 API。请先启动 `services/api`。

## 当前范围（P0/P1 骨架）

- 注册 / 登录
- 课程列表与课段切换
- 学习页宽屏布局（视频区 + 字幕占位 + Tab）

完整字幕同步、听写、跟读录音等在后续迭代接入。
