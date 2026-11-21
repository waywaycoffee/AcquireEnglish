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

Balance lives on `wallet_accounts`; audit rows in `points_ledger`. Monthly earn caps: paid 800 / free 200. Spend catalog covers consumables only (no permanent unlocks).

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

Membership screen shows trial banner (days left / login streak / claim) and module catalog cards; client methods live on `AcquireApiClient` (`commerce*`).
