# 用户资产后台数据库

用户侧「拥有什么」集中在 Postgres（本地也可 SQLite），与学习进度/生词本分开。

## 表

| 表 | 作用 |
|----|------|
| `product_skus` | 可售/可发放 SKU（会员、陪练分钟、数字人分钟、积分…） |
| `orders` / `order_items` | 订单与明细 |
| `user_entitlements` | **核心用户资产**（许可 / 配额） |
| `wallet_accounts` / `wallet_ledger` | 积分钱包与流水 |

已有学习数据仍用原表：`lesson_progress`、`vocab_items`、`user_link_courses`（导入课）。

## API（需登录）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/assets` | 资产总览（权益 + 钱包 + 导入课/生词计数） |
| GET | `/api/assets/skus` | 上架 SKU |
| GET | `/api/assets/entitlements` | 有效权益列表 |
| POST | `/api/assets/entitlements/grant` | 发放/叠加权益（运营/活动） |
| POST | `/api/assets/orders` | 创建待支付订单 |
| POST | `/api/assets/orders/{id}/mark-paid` | 模拟/人工支付履约（写权益） |

启动时会 `create_all` 建表，并种子默认 SKU（`membership.pro.monthly` 等）。
