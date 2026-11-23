# Commerce (full suite)

Product modules (`video` / `reading` / `exam` / `vocab` / `digital_human`; `course` free), free-tier + paid quotas, trial, points, and minimal gamification.

**Storefront (2026-11):**

| Product | Price | Duration |
|---------|-------|----------|
| Pro 全开卡 | ¥19.9 | **7 天**（唯一会员短卡） |
| 阅读模块 | ¥199 | 年卡 |
| 视频模块 | ¥299 | 年卡 |
| 考试模块 | ¥199 | 年卡 |
| 数字人模块 | ¥20 | 月卡 |
| 单词 / 词书 | **免费** | 永久 |
| 课程板块 | **免费** | 永久 |

Retired from storefront: module monthly/permanent, combos, vocab packs, efficiency packs, Pro day/month/year cards.

Legacy content×capability codes (`exam_reading` …) still resolve via `LEGACY_MODULE_ALIASES`.

**WeChat MCH:** **BLOCKED** without `WECHAT_MCH_*`. Production → clear 503 / App **待配置商户**. Non-prod → `provider=mock` + `mark-paid`.

OpenMAIC is **out of scope** (separate track).

## Status checklist (2026-11-23)

| Area | Status | Notes |
|------|--------|--------|
| A1 Usage quotas + free-tier + quota_exhausted | **DONE** | `usage_counters`, `/commerce/quotas*`, HTTP 402 |
| A2 Points spend → real effects | **DONE** | coach +10, ai_explain credit, … |
| A3 Server-side earn + thresholds/caps | **DONE** | accuracy/duration/dedupe; ignore client amount |
| Pricing SKUs (7d / yearly / DH monthly) | **DONE** | `catalog.py` + `membership.pro.7d` |
| Vocab free access | **DONE** | `FREE_MODULE_CODES` |
| B6 rank_state + 学力值 | **DONE** | bronze→master |
| B7 Arena MVP (词义速配) | **DONE** | `/commerce/arena/*` |
| B8 Anti-abuse basics | **DONE** | 7d dedupe, duration floor, caps |
| C Analytics events | **DONE** | `commerce_events` |
| Admin commerce peek | **DONE** | `/api/admin/commerce/*` |
| WeChat App pay | **BLOCKED** | needs MCH secrets |
| Full 4 arena modes / 2D avatar | **DEFERRED** | art + matchmaking |

## Modules

| Code | Title | Sell |
|------|--------|------|
| `video` | 视频模块 | yearly ¥299 |
| `reading` | 阅读模块 | yearly ¥199 |
| `exam` | 考试模块 | yearly ¥199 |
| `digital_human` | 数字人模块 | monthly ¥20 |
| `vocab` | 单词 / 词书 | free |
| `course` | 课程板块 | free (not on paid storefront) |

## Quotas

Free: 精读 1/日、AI 精讲 2/周、外教 10 分/周、上传 5/日 · 20/月、对战 3/日.  
Paid: from `MODULE_DEFS.quota`. Arena free 3 / paid 10 + extras.

## Free tier (permanent starters)

See [FREE_TIER.md](./FREE_TIER.md). Each paid module keeps ~5 permanent free starters; vocab/course stay free; personal uploads ≥15.

## Default owner Pro

Display name `weiwei` is granted **lifetime Pro** on API startup and after each successful auth.

## Trial

Welcome Pro trial **7 days** (claim-once). Login streak can claim +7d extend coupon.

## WeChat Pay merchant

Required env (API host `/opt/acquireenglish/services/api/.env`):

```bash
WECHAT_MCH_ID=
WECHAT_MCH_SERIAL_NO=
WECHAT_MCH_API_V3_KEY=          # 32 chars
WECHAT_MCH_PRIVATE_KEY=         # PEM or absolute path to apiclient_key.pem
WECHAT_PAY_NOTIFY_URL=https://acquireenglish.curlhairai.com/api/assets/wechat/notify
```

Bind the merchant to Open Platform AppID (`WECHAT_APP_ID`). Then `systemctl restart acquireenglish-api` and confirm `wechat_pay_configured=true` on `/api/health`.

## App

Membership: Pro 7 天卡、模块年卡、数字人月卡；微信或开发模拟支付；restore entitlements.

## Admin

`GET /api/admin/commerce/overview|orders|points-ledger|events` · `GET /api/admin/skus?kind=`

## Blocked / deferred only

1. **BLOCKED:** WeChat MCH secrets  
2. **DEFERRED:** battle pass, 2D avatar, 3 more arena modes  
3. **NEVER:** audio/video in APK; invent exam packs
