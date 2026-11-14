# AcquireEnglish — Morning Acceptance Checklist

**Prepared for:** next-day QA / product acceptance  
**Production base:** https://acquireenglish.curlhairai.com  
**Oral coach:** https://acquireenglish.curlhairai.com/coach  
**LiveTalking (Tailscale digital human):** http://100.115.252.55:8010  
**API host (SSH):** `acquireenglish` → ECS `8.163.45.100`  
**DB (production):** `postgresql+asyncpg://acquireenglish:***@127.0.0.1:5432/acquireenglish`  
**SQLite backup:** `/opt/acquireenglish/backups/` (pre-cutover retained)

### Verified run (automated)

| Item | Result | Timestamp (UTC+8) |
|------|--------|-------------------|
| Full suite `test_prod_e2e_suite.py` | **21 passed / 0 failed** | 2026-11-15 00:18 UTC+8 |
| WebRTC lip-sync E2E (aiortc) | **PASS** — offer/answer + `/human` code=0 + video/audio frames | 2026-11-15 00:18 (suite) / earlier standalone ~00:00 |
| Postgres cutover + data migrate | **PASS** — 18 users (+e2e→29) migrated; API on PG; register persists | 2026-11-15 00:17 CUTOVER_OK / 00:21 users=29 |
| Oral coach draft/confirm/turn | **PASS** (suite) | 2026-11-15 |
| LiveKit token | **PASS** (suite) | 2026-11-15 |
| Bilibili import + SRT | **PASS** (suite + web `link-6`) | 2026-11-15 |
| Auth SMS / WeChat | **mock-mode pass** | 2026-11-15 |
| Web UI login + course + prefs + feed | **PASS** (browser) | 2026-11-15 ~00:21 |
| LiveTalking browser UI | **PASS** — connected + avatar video | 2026-11-15 ~00:21 |

Suite: `services/api/tests/test_prod_e2e_suite.py`  
WebRTC helper: `tools/livetalking/test_webrtc_e2e.py` (use LiveTalking `.venv` for `aiortc`)

```bash
# Re-run from repo root (Windows / Linux)
python -m pytest services/api/tests/test_prod_e2e_suite.py -v --tb=short

# Standalone WebRTC (Tailscale + LiveTalking GPU)
third_party/LiveTalking/.venv/Scripts/python.exe tools/livetalking/test_webrtc_e2e.py \
  --base http://100.115.252.55:8010 --avatar wav2lip_avatar_glass_man
```

---

## 0. Auth policy (read first)

| Path | Current production behavior | Accept as |
|------|-----------------------------|-----------|
| SMS login (`/api/auth/sms/*`) | `AUTH_SMS_MOCK=true`, code **123456** | **Accepted mock** unless real SMS secrets/webhook appear |
| WeChat login (`/api/auth/wechat/login`) | `AUTH_WECHAT_MOCK=true` (or AppID/Secret empty) — any `code` maps to stable mock openid | **Accepted mock** unless WeChat App secrets are configured |
| Email register/login | Real JWT against **Postgres** | Real |

Confirm mock flags via health:

```bash
curl -fsS https://acquireenglish.curlhairai.com/api/health
# expect: "auth_sms_mock":"true","auth_wechat_mock":"true"
```

Do **not** fail acceptance because SMS/WeChat are mocked. Mark those rows **mock-mode pass** when login returns a token.

---

## 1. Web (frontend)

Open: https://acquireenglish.curlhairai.com/

- [x] Home / course list loads (no blank error page) *(2026-11-15 browser)*
- [x] Register with a new email (use a real-looking domain, e.g. `@example.com` — not `.test`) *(qa_accept_1794673159@example.com via API + UI login)*
- [x] Login with that email/password *(browser → 你好, QA Accept)*
- [x] Open a catalog course + lesson player *(slow-english-demo; 字幕/跟读/听写/练习/词卡)*
- [x] Progress updates after scrubbing / play (refresh still shows position) *(play → position_sec 16.8; API PUT/GET 42.5 roundtrip)*
- [x] Add a vocab word; list shows it *(API POST `acceptance` → count=1)*
- [x] Settings / preferences: change level + tags; save succeeds *(UI 保存并刷新 → 今日更新变为 TED + 慢速故事)*
- [ ] Optional: paste Bilibili cookie in settings — UI must **not** echo full SESSDATA afterward (only “saved” / has-cookie style) *(web 无独立设置页；prefs 仅返回 has_bilibili_cookie boolean — N/A web / App 手动)*
- [x] Daily feed page returns courses *(今日更新 2 课)*
- [x] Paste-link import with a public Bilibili URL (e.g. `https://www.bilibili.com/video/BV1BsWwz7Eeo/`) completes or shows a clear error *(link-6 出现在全部课程)*

---

## 2. API smoke (curl / Postman)

Base: `https://acquireenglish.curlhairai.com`  
Auth header: `Authorization: Bearer <token>`  
Note: auth routes are under **`/api/auth/...`** (not `/api/login`).

| # | Check | How | Pass criteria | Result |
|---|--------|-----|---------------|--------|
| 1 | Health | `GET /api/health` | `status=ok` | **pass** |
| 2 | Register | `POST /api/auth/register` | 200 + `access_token` | **pass** (suite + QA user) |
| 3 | Login | `POST /api/auth/login` | 200 + token | **pass** |
| 4 | Me | `GET /api/auth/me` | 200 + email | **pass** (suite) |
| 5 | SMS mock | `POST /api/auth/sms/send` then `/sms/login` with `123456` | 200; `mock:true` → **mock-mode pass** | **mock-mode pass** |
| 6 | WeChat mock | `POST /api/auth/wechat/login` `{"code":"qa_wx_1"}` | 200 + `wechat_bound` → **mock-mode pass** | **mock-mode pass** |
| 7 | Courses | `GET /api/courses` + `GET /api/courses/{id}` | list + detail | **pass** |
| 8 | Progress | `PUT` then `GET /api/progress` | roundtrip | **pass** (`position_sec`) |
| 9 | Vocab | `POST` then `GET /api/vocab` | word present | **pass** |
| 10 | Preferences | `GET`/`PUT /api/preferences` | no raw cookie in JSON | **pass** (`has_bilibili_cookie` only) |
| 11 | Feed | `GET /api/feed/daily` | 200 list | **pass** |
| 12 | Import | `POST /api/imports/link` + SRT `PUT`/`GET` | course `link-*` + SRT body | **pass** |
| 13 | Learning | tasks → sessions → turns → feedback → reviews → due → complete | all 200 | **pass** (suite) |
| 14 | LiveKit | `GET /api/livekit/status` + `POST /api/livekit/token` | if `configured=true`, token+url returned | **pass** |
| 15 | Postgres persist | register → put prefs → login → get prefs | level/tags roundtrip (suite `TestPostgresPersistence`) | **pass** |

Never paste full tokens / SESSDATA into chat logs or tickets — mask (`abcd…wxyz`).

---

## 3. Oral coach (`/coach`)

Public: https://acquireenglish.curlhairai.com/coach/api/health

- [x] `GET /coach/api/health` → `ready: true` + provider map *(suite 2026-11-15)*
- [x] `GET /coach/api/providers` → `active` + `options`
- [x] `POST /coach/api/sessions` → 201 + session id
- [x] `PATCH /coach/api/sessions/{id}/context` updates fields
- [x] `POST .../draft` with a tiny WAV → draft_id (silence may yield empty ASR; still OK)
- [x] `POST .../confirm` with `confirmed_text` → `coach_text` (+ optional `tts_url`)
- [x] `POST .../turn` one-shot with `confirmed_text` → coach reply
- [x] If `tts_url` present, `GET /coach/api/tts/...` returns audio bytes
- [ ] App “口语教练” entry opens without 502/403 *(manual — no device this run)*

Local systemd (SSH): `systemctl is-active acquireenglish-oral-coach` → `active` (uvicorn `:8770`).

Note: Coach avatar cue uses `livetalking_connect` (probe only). App owns WebRTC `/offer` session and POSTs `/human` with `sessionid`.

---

## 4. LiveKit

- [x] Health shows a `wss://…livekit.cloud` when configured *(suite 2026-11-15)*
- [x] `POST /api/livekit/token` with JWT returns `{url, token, room, identity}`
- [ ] App can join a room / digital-human path that uses the token *(manual — no device this run)*

If `configured=false`, token must be **503** with a clear message — still acceptable only if product explicitly demos without LiveKit.

---

## 5. Tailscale digital human (LiveTalking) — WebRTC lip-sync

URL: http://100.115.252.55:8010  
Avatar: `wav2lip_avatar_glass_man` (CUDA)  
Requires Tailscale connectivity on the QA machine.

### Morning / automated pass criteria (required)

- [x] `GET /` → **200 or 302** (service up)
- [x] `POST /human` with `{}` (no session) → `{"code":-1,"msg":"session not found"}` (expected error shape)
- [x] **WebRTC `/offer` → SDP answer + non-empty `sessionid`**
- [x] **`POST /human` with that `sessionid` + `type=echo` → `code: 0`** (not `-1`)
- [x] **Media proof:** at least one video **or** audio frame/packet received (aiortc `ontrack` + `recv`), *or* browser CDP equivalent
- [x] Standalone script / suite test green: `tools/livetalking/test_webrtc_e2e.py` and `TestLiveTalking::test_livetalking_webrtc_offer_human_tracks`

Verified example (2026-11-15 ~00:14 UTC+8): `connection_state=connected`, tracks=`audio`+`video`, after speak ~153 video / ~302 audio frames, `/human` `code=0`.

### Optional manual

- [x] Open UI in browser on Tailscale and confirm avatar page loads / lip motion visible *(2026-11-15 ~00:21 — 已连接 + glass_man 视频画面 + 发送 echo)*

---

## 6. App settings (client)

- [ ] API base points at `https://acquireenglish.curlhairai.com` *(manual — no device)*
- [ ] Coach base points at `https://acquireenglish.curlhairai.com/coach` *(manual)*
- [ ] LiveTalking / avatar URL: `http://100.115.252.55:8010` (Tailscale) *(manual)*
- [ ] Login: email works; SMS uses mock code **123456**; WeChat mock login works without real App secrets *(manual)*
- [ ] Preferences: Bilibili cookie / ASR key fields save without displaying secrets again *(manual)*
- [ ] No crash on cold start / resume *(manual)*

---

## 7. Ops quick check (if something looks down)

SSH: `ssh acquireenglish`

```bash
systemctl is-active acquireenglish-api acquireenglish-oral-coach postgresql
curl -fsS http://127.0.0.1:5200/api/health
curl -fsS http://127.0.0.1:8770/api/health
# Confirm Postgres (mask password)
grep '^DATABASE_URL=' /opt/acquireenglish/services/api/.env | sed -E 's#(postgresql\+asyncpg://[^:]+:)[^@]+@#\1***@#'
sudo -u postgres psql -d acquireenglish -c 'SELECT count(*) FROM users;'
curl -fsS -o /dev/null -w "%{http_code}\n" https://acquireenglish.curlhairai.com/api/health
curl -fsS -o /dev/null -w "%{http_code}\n" https://acquireenglish.curlhairai.com/coach/api/health
```

**Ops verified 2026-11-15 ~00:21:** `api` / `oral-coach` / `postgresql` / `nginx` all **active**; users=**29**; LiveKit Agent schtask **Running**; LiveTalking `:8010` **up**.

Redeploy API (from a machine with bash/rsync): `services/api/deploy.sh`  
Or copy a single module: `scp … acquireenglish:/opt/acquireenglish/services/api/app/...` then `systemctl restart acquireenglish-api`.

---

## Sign-off

| Area | Result (pass / fail / mock-mode pass) | Notes |
|------|----------------------------------------|-------|
| Web | **pass** | login/course/prefs/feed/import UI + API |
| API | **pass** | 21/21 suite 2026-11-15 |
| Auth SMS | **mock-mode pass** | accepted per §0 |
| Auth WeChat | **mock-mode pass** | accepted per §0 |
| Oral coach | **pass** | draft/confirm/turn |
| LiveKit | **pass** | token issued; App join = manual |
| LiveTalking Tailscale | **pass** | WebRTC frames + browser UI connected |
| Postgres | **pass** | migrated; users=29; persist OK |
| App settings | **N/A (no device)** | deferred to device QA |

**Overall:** **PASS** for server / web / coach / LiveTalking production acceptance. App client rows remain manual.

**Tester:** automated overnight agent  
**Date:** 2026-11-15  
**Build / time:** ~00:21 UTC+8  
**QA account:** `qa_accept_1794673159@example.com` (password in `deploy/_qa_web_creds.json`)
