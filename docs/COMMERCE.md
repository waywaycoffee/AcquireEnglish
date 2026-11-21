# Commerce (modules · trial · points)

P0 commercialization for Acquire English: modular SKUs, 7-day full-feature trial with daily-login extension, and a points wallet.

## Modules

Four sellable modules (content × capability):

| Code | Title |
|------|--------|
| `exam_reading` | 考试阅读 |
| `exam_listening` | 考试听说 |
| `acquire_reading` | 习得阅读 |
| `acquire_listening` | 习得听说 |

Combos: `module.combo.any2.monthly` (pick 2), `module.combo.all4.monthly` / `.yearly`. Permanent unlocks: `module.{code}.permanent`.

SKUs are upserted on API startup via `ensure_commerce_skus` (after `ensure_default_skus`). Entitlements use `asset_kind=module` and `asset_ref=<code>`. Combo orders may pass `selected_modules` on create-order for any2.

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
| GET | `/catalog` | no | modules + combos + efficiency |
| GET | `/trial/status` | yes | days left, login streak, claim eligibility |
| POST | `/trial/claim-extend` | yes | issue `trial_extend_7` coupon |
| GET | `/points` | yes | balance + rules |
| POST | `/points/earn` | yes | body `{reason, amount?}` |
| POST | `/points/spend` | yes | body `{item}` |

Related: `/api/assets/membership-coupons/{id}/redeem` honors `trial_extend_7` full-feature extension.

## App

Membership screen shows trial banner (days left / login streak / claim), module/combo purchase (any2 uses `selected_modules`), points balance + spend catalog, and module catalog cards; client methods live on `AcquireApiClient` (`commerce*`).

Module entry gates (`ModuleGate`): `exam_reading` / `exam_listening` / `acquire_reading` / `acquire_listening`. Access = active Pro (incl. full trial) **or** matching `asset_kind=module` entitlement. API: `GET /api/commerce/modules/{code}/access`.

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
