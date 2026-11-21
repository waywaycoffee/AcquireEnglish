# Commerce (full suite)

Product modules (`video` / `reading` / `exam` / `course`), free-tier + paid quotas, trial, points with real spend effects, efficiency / direct packs, and minimal gamification (学力值 · 打卡 · 词义速配).

Legacy content×capability codes (`exam_reading` …) still resolve via `LEGACY_MODULE_ALIASES`.

**WeChat MCH:** **BLOCKED** without `WECHAT_MCH_*`. Production → clear 503 / App **待配置商户**. Non-prod → `provider=mock` + `mark-paid`.

OpenMAIC is **out of scope** (separate track).

## Status checklist (2026-11-21)

| Area | Status | Notes |
|------|--------|--------|
| A1 Usage quotas + free-tier + quota_exhausted | **DONE** | `usage_counters`, `/commerce/quotas*`, HTTP 402 |
| A2 Points spend → real effects | **DONE** | coach +10, ai_explain credit, … |
| A3 Server-side earn + thresholds/caps | **DONE** | accuracy/duration/dedupe; ignore client amount |
| A4 Efficiency SKUs fulfill + UI | **DONE** | double_points / arena_extra |
| A5 course_pack / vocab_pack direct SKUs | **DONE** | permanent entitlements |
| B6 rank_state + 学力值 | **DONE** | bronze→master |
| B7 Arena MVP (词义速配) | **DONE** | `/commerce/arena/*` |
| B8 Anti-abuse basics | **DONE** | 7d dedupe, duration floor, caps |
| C Analytics events | **DONE** | `commerce_events` |
| Admin commerce peek | **DONE** | `/api/admin/commerce/*` |
| WeChat App pay | **BLOCKED** | needs MCH secrets |
| Net-floor publish gate UI | **PARTIAL** | `floor_cents` in meta only |
| Full 4 arena modes / 2D avatar | **DEFERRED** | art + matchmaking |
| B-side | **DEFERRED** | out of period |

## Modules

| Code | Title |
|------|--------|
| `video` | 视频模块 |
| `reading` | 阅读模块 |
| `exam` | 考试模块 |
| `course` | 课程板块 |

Combos: `any2` monthly/yearly, `all4` monthly/yearly.  
Efficiency: `boost.double_points.7d`, `boost.arena.extra.5`.  
Direct: `pack.vocab.*`, `pack.course.*`.

## Quotas

Free: 精读 1/日、AI 精讲 2/周、外教 10 分/周、上传 5/日 · 20/月、对战 3/日.  
Paid: from `MODULE_DEFS.quota`. Arena free 3 / paid 10 + extras.

## Free tier (permanent starters)

See [FREE_TIER.md](./FREE_TIER.md). Each module keeps ~5 permanent free starters with a short learn path; bookshelf free stays free; personal uploads ≥15.

## Default owner Pro

Display name `weiwei` (product default / demo account) is granted **lifetime Pro** (`membership` / `pro`, `ends_at=null`, `campaign=default_owner_pro`) on API startup (`ensure_default_pro_users`) and again after each successful auth. Pro unlocks all four modules; no separate module SKUs required.

## Points

Earn validates PRD gates server-side. Spend grants entitlements. Free users 1.5× spend. Double-points card multiplies earns.

## Gamification

`rank_state` + `POST /checkin` + arena vocab_match vs bot. Season board at `/rank/board`.

## App

Membership: trial, rank/arena/quotas, efficiency+direct catalog, WeChat or 开发模拟支付, restore entitlements. Home: trial countdown + tier strip. Paywall supports quota_exhausted copy.

## Admin

`GET /api/admin/commerce/overview|orders|points-ledger|events` · `GET /api/admin/skus?kind=`

## Blocked / deferred only

1. **BLOCKED:** WeChat MCH secrets  
2. **DEFERRED:** battle pass, 2D avatar, 3 more arena modes  
3. **NEVER:** audio/video in APK; invent exam packs
