# 社区冒险界面设计（游戏感）

## 原则

- **单人冒险为主**：章节地图与通关进度永远属于个人。
- **同桌为辅**：只显示为可选加分条，换人不回滚个人关卡。
- **视觉**：品牌绿 `#58CC02` + 琥珀关卡 `#FFC800` + 咖啡暖色夜景；厚按钮阴影；避免紫色玻璃风。

## 信息架构

| 页面 | 玩家首先看到 | 主行动 | 次行动 |
|---|---|---|---|
| 冒险广场（原社区） | 当前章节英雄条 + 路径节点 | 继续冒险 | 同桌加分 / 任务流 |
| 街角咖啡店地图 | 四站路径 + 当前关高亮 | 开战 / 继续 | 跟练成果卡、去学习桌 |
| 学习桌 | 同一英雄条置顶 | 打开地图 | 邀请同桌、PK、打卡 |
| 通关结算 | 练过的能力（不夸大） | 发布成果卡 | 回地图 |

## Tab 文案

发现页分段：`任务 | 热门 | 找人 | 榜`（任务流承接可开练内容）。

## 组件

`adventure_ui.dart`：`AdventureHeroBanner`、`AdventurePathStrip`、`HubChunkyButton`、`QuestFeedCard`。

## 已落地行为

- 英雄条读取真实通关进度（`cafeProgressProvider`）。
- 通关记入本周有效练习；登录后同步 `POST /api/study-desk/weekly-quest`。
- 成果卡 `learning_result` 可带 `link_url=/community/explore/cafe/{1-4}`；动态优先展示并可「练同一关」。
- 学习桌有同桌时显示本周共同目标卡（换人不丢个人关卡）；提醒复用 `/encourage`。
- 词汇 PK 入口仍在学习桌；发现页不再并行旧 PK。
- 微信/浏览器落地：`GET /api/public/challenges/cafe/{1-4}`；App 深链 `acquireenglish://app/explore/cafe/{n}` 与路由 `/explore/cafe/:stage`。
- 方法/提问帖也可挂同一关卡 `link_url`，任务流同样置顶可开练。
- PK 可选 `source=cafe`（街角咖啡店约定词表），不要求共同学过词交集。
- 延迟复测：首次通关记 `challenge_first_clears`；满 24 小时后重练上报 `/api/study-desk/retest`，地图展示通过率。
- 任务流按关卡帖 `challenge_completes` / `opens` 排序；`POST /api/community/posts/{id}/challenge-event`。
