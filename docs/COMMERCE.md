# Commerce (modules · trial · points)

P0 commercialization for Acquire English: modular SKUs, 7-day full-feature trial with daily-login extension, and a points wallet.

## Modules

Four sellable product buckets:

| Code | Title | Gates (examples) |
|------|--------|------------------|
| `video` | 视频模块 | 听说课 / 对话课（原习得听说） |
| `reading` | 阅读模块 | 阅读中心 / 书目 / 读者 |
| `exam` | 考试模块 | 考试阅读与听说专项 |
| `course` | 课程板块 | 教材课 / 课程解构 |

Legacy aliases (existing entitlements still unlock):

| Old code | → New |
|----------|-------|
| `exam_reading` / `exam_listening` | `exam` |
| `acquire_reading` | `reading` + `course` |
| `acquire_listening` | `video` |

Storefront SKUs (only): `module.{video|reading|exam|course}.{monthly|yearly}` — 月卡 / 年卡 per module. No permanent, combo, weekly, credit-pack, or all-in-one plans on sale.

Retired SKUs (`module.*.permanent`, `module.combo.*`, efficiency boosts, legacy Pro/consumable packs) stay in DB with `active=0` so historical grants / entitlement mapping still work; `ensure_commerce_skus` deactivates them on startup.

SKUs are upserted on API startup via `ensure_commerce_skus` (after `ensure_default_skus`). Entitlements use `asset_kind=module` and `asset_ref=<code>`.

## Trial

- New users: `grant_new_user_trial` → `grant_full_feature_trial` grants Pro + all 4 modules + coach quota + starter points for **7 days** (`campaign=new_user_trial_full`).
- Every successful auth path records a UTC login day (`user_login_days`).
- During trial, logging in every day for 7 days unlocks claim of coupon `trial_extend_7` (`kind=days`, `value=7`).
- Redeeming that coupon extends **Pro + all 4 modules** by 7 days.

## Points

Balance lives on `wallet_accounts`; audit rows in `points_ledger`. Monthly earn caps: paid 800 / free 200. Spend catalog covers consumables only (no permanent unlocks). Membership screen lists earn rules + spend catalog; client hooks fire on quiz pass / daily check-in / streak milestones / shadow batches.

## Gamification (PRD chapter)

**Shipped (thin):** check-in streak + commerce points earn/spend (above). Streak milestones (`checkin_3/7/14/30`) are the live retention loop.

**Deferred (needs design + content, not fake UI):** season ranks, arena matching, battle pass, avatar skins unlocked by tier. Tables sketched in PRD (`rank_state`, season scores) are **not** implemented. Revisit after pay + points are stable in production.

## HTTP API (`/api/commerce`)

| Method | Path | Auth | Notes |
|--------|------|------|--------|
| GET | `/catalog` | no | 4 modules × 月/年 (+ empty combos/efficiency for shape) |
| GET | `/trial/status` | yes | days left, login streak, claim eligibility |
| POST | `/trial/claim-extend` | yes | issue `trial_extend_7` coupon |
| GET | `/points` | yes | balance + rules |
| POST | `/points/earn` | yes | body `{reason, amount?}` |
| POST | `/points/spend` | yes | body `{item}` |

Related: `/api/assets/membership-coupons/{id}/redeem` honors `trial_extend_7` full-feature extension.

## App

Membership screen shows trial banner (days left / login streak / claim), per-module 月卡/年卡 purchase, points balance + spend catalog; client methods live on `AcquireApiClient` (`commerce*`).

Module entry gates (`ModuleGate`): `video` / `reading` / `exam` / `course`. Access = active Pro (incl. full trial) **or** matching module entitlement (incl. legacy aliases). API: `GET /api/commerce/modules/{code}/access` (accepts legacy codes). Soft-browse mode keeps catalogs open; item opens require entitlement **or** a free-trial seed.

## Free-trial default seeds (~3 / module)

Catalog: `services/api/data/free_trial_seeds.json` → `GET /api/commerce/free-trial-seeds`.
App bootstrap (`freeTrialSeedBootstrapProvider`) auto-downloads these into **local cache** on launch (not APK media assets):

| Module | Default seeds | How they land locally |
|--------|---------------|------------------------|
| `video` | BV1fV4y1p7Ex / BV1gm411r7yz / BV1Aw4m1k7qU (page 1) | Bilibili import → library local MP4; shared EN/ZH subs from ECS |
| `reading` | `starter-first-morning` / `starter-small-cafe` / `starter-new-route` | `GET /api/reading/starter` via reading cold-start |
| `exam` | CET4 `c4v1` / `c4r1` / `c4l1` | Exam pack JSON from API; optional listening audio under `/media/exam/…` |
| `course` | `course-seed-*` from the three starters | Written into reading library as「免费体验 · 默认课程」 |

**ECS ops (if missing):** deploy `pack_cet4.json`; seed shared Bilibili subtitles for the three BVs (`tools/subtitle/seed_recommended_bilibili_subs.py`); optional `media/imports/{id}/study.m4a` after first import. Never ship `.mp3/.mp4` under `apps/mobile/assets`.

**Free preview (~3 / module):** `FREE_PREVIEW_COUNT` / `kModuleFreePreviewCount = 3`. Catalog seeds: `GET /api/commerce/free-trial-seeds` (`services/api/data/free_trial_seeds.json`). Enforcement: first N curriculum lessons (video), starter docs (reading), first N exam passages, first N material courses — plus curated seed IDs. Hubs soft-browse; paid units show 开通月卡/年卡 CTA.

Points earn hooks (client → `POST /api/commerce/points/earn`):

| Reason | Trigger |
|--------|---------|
| `reading_quiz_pass` | Exam reading session ≥60% correct |
| `daily_tasks_clear` | Daily learning check-in requirements met |
| `shadow_batch` | Every 3 shadowing toggles in a day |
| `checkin_3` / `_7` / `_14` / `_30` | Streak first reaches milestone |

## Shared subtitle EN→ZH cron

On ECS (after LLM keys in `tools/oral_coach/.env` or `services/api/.env`):

```cron
20 4 * * * cd /opt/acquireenglish/services/api && .venv/bin/python tools/backfill_shared_zh_translations.py --mismatch --limit 80 >> /var/log/acquireenglish-shared-zh.log 2>&1
```

Manual: `python tools/backfill_shared_zh_translations.py --mismatch --limit 100`.

## CLOTH / SC-Ques exam banks

Importer: `services/api/tools/import_k12_open_banks.py` (writes `data/exam_packs/`). Vendor trees are gitignored under `data/exam_bank_vendor/`.

Preflight (exits 2 if missing — does not download):

```bash
python tools/fetch_cloth_scques_stub.py
```

| Dataset | Place archive / files at | Upstream |
|---------|--------------------------|----------|
| CLOTH | `exam_bank_vendor/CLOTH/CLOTH.tar.gz` (auto-extract) or JSON under that folder | https://www.qizhexie.com/data/CLOTH (research) / paper “CLOTH” (Xie et al.) |
| SC-Ques | `exam_bank_vendor/SC-Ques/datasets/` (json/jsonl from release) | https://github.com/ai4ed/SC-Ques |

Do **not** invent packs: if archives are missing, the importer prints a skip message and leaves converters ready. After import, redeploy pack JSON to ECS with the usual exam-pack ship path.

**Status (2026-11-21):** archives not found on the developer machine (Downloads / Baidu / vendor). Blocked until research dumps are placed manually.
