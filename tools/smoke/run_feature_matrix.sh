#!/usr/bin/env bash
# AcquireEnglish feature matrix runner — all suites must exit 0.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPORT="$ROOT/.tmp/feature_matrix_report.txt"
mkdir -p "$ROOT/.tmp"
: >"$REPORT"

pass() { echo "✅ $1" | tee -a "$REPORT"; }
fail() { echo "❌ $1" | tee -a "$REPORT"; exit 1; }

echo "=== AcquireEnglish Feature Matrix ===" | tee -a "$REPORT"
echo "root=$ROOT" | tee -a "$REPORT"

echo "" | tee -a "$REPORT"
echo "## 1) Flutter unit / widget / acceptance" | tee -a "$REPORT"
(
  cd "$ROOT/apps/mobile"
  flutter test
) && pass "Flutter tests" || fail "Flutter tests"

echo "" | tee -a "$REPORT"
echo "## 2) API feature matrix (local pytest)" | tee -a "$REPORT"
(
  cd "$ROOT/services/api"
  if [[ -f .venv/bin/activate ]]; then
    # shellcheck disable=SC1091
    source .venv/bin/activate
  fi
  python -m pytest tests/test_feature_matrix.py tests/test_phone_wechat_auth.py -q
) && pass "API pytest" || fail "API pytest"

echo "" | tee -a "$REPORT"
echo "## 3) Production API smoke" | tee -a "$REPORT"
python3 - <<'PY' | tee -a "$REPORT"
import json, urllib.request, ssl, sys
BASE = "https://acquireenglish.curlhairai.com"
ctx = ssl.create_default_context()

def http(method, path, data=None, headers=None, timeout=25):
    body = None if data is None else json.dumps(data).encode()
    req = urllib.request.Request(BASE + path, data=body, method=method)
    req.add_header("Content-Type", "application/json")
    if headers:
        for k, v in headers.items():
            req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode())
    except Exception as e:
        if hasattr(e, "read"):
            try:
                return getattr(e, "code", "ERR"), json.loads(e.read().decode())
            except Exception:
                return getattr(e, "code", "ERR"), str(e)
        return "ERR", str(e)

checks = []
st, health = http("GET", "/api/health")
checks.append(("health", st == 200 and (health or {}).get("status") == "ok", health))
st, coach = http("GET", "/coach/api/health")
checks.append(("coach_health", st == 200 and (coach or {}).get("ready") is True, coach))
st, _ = http("POST", "/api/auth/sms/send", {"phone": "13900001111"})
checks.append(("sms_send", st == 200, _))
st, login = http("POST", "/api/auth/sms/login", {"phone": "13900001111", "code": "123456"})
token = (login or {}).get("access_token") if isinstance(login, dict) else None
checks.append(("sms_login", st == 200 and bool(token), {"has_token": bool(token)}))
if token:
    h = {"Authorization": f"Bearer {token}"}
    st, prefs = http("GET", "/api/preferences", headers=h)
    checks.append(("preferences", st == 200 and isinstance(prefs, dict), {
        "has_bilibili_cookie": (prefs or {}).get("has_bilibili_cookie") if isinstance(prefs, dict) else None
    }))
    st, lk = http("POST", "/api/livekit/token", {"room": "matrix-smoke"}, headers=h)
    checks.append(("livekit_token", st == 200 and isinstance(lk, dict) and bool((lk or {}).get("token")), {
        "url": (lk or {}).get("url") if isinstance(lk, dict) else None
    }))
    st, sess = http("POST", "/coach/api/sessions", {"difficulty": "B1"}, headers=h)
    checks.append(("coach_session", st in (200, 201) and isinstance(sess, dict) and bool((sess or {}).get("id")), {
        "id": (sess or {}).get("id") if isinstance(sess, dict) else None
    }))

all_ok = True
for name, ok, detail in checks:
    mark = "PASS" if ok else "FAIL"
    print(f"  [{mark}] {name}: {detail}")
    all_ok = all_ok and ok
sys.exit(0 if all_ok else 1)
PY
pass "Production API smoke"

echo "" | tee -a "$REPORT"
echo "ALL GREEN" | tee -a "$REPORT"
