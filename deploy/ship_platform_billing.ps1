# Sync multi-vendor platform billing + admin UI to ECS and restart API.
$ErrorActionPreference = "Stop"
$root = Join-Path $PSScriptRoot ".." | Resolve-Path
$api = Join-Path $root "services\api" | Resolve-Path
$hostAlias = if ($env:AE_SSH_HOST) { $env:AE_SSH_HOST } else { "acquireenglish" }

Write-Host "Uploading platform billing modules to $hostAlias ..."
$pairs = @(
  @{ Local = "app\services\platform_billing.py"; Remote = "/opt/acquireenglish/services/api/app/services/platform_billing.py" },
  @{ Local = "app\services\api_usage.py"; Remote = "/opt/acquireenglish/services/api/app/services/api_usage.py" },
  @{ Local = "app\services\gpu_subtitle_rpc.py"; Remote = "/opt/acquireenglish/services/api/app/services/gpu_subtitle_rpc.py" },
  @{ Local = "app\routers\admin_analytics.py"; Remote = "/opt/acquireenglish/services/api/app/routers/admin_analytics.py" },
  @{ Local = "app\routers\writing.py"; Remote = "/opt/acquireenglish/services/api/app/routers/writing.py" },
  @{ Local = "app\routers\reading_speech.py"; Remote = "/opt/acquireenglish/services/api/app/routers/reading_speech.py" },
  @{ Local = "app\models.py"; Remote = "/opt/acquireenglish/services/api/app/models.py" },
  @{ Local = "app\db_migrate.py"; Remote = "/opt/acquireenglish/services/api/app/db_migrate.py" }
)
foreach ($p in $pairs) {
  $src = Join-Path $api $p.Local
  scp -o ConnectTimeout=40 $src "${hostAlias}:/tmp/$(Split-Path $p.Local -Leaf)"
  ssh -o ConnectTimeout=40 $hostAlias "cp /tmp/$(Split-Path $p.Local -Leaf) $($p.Remote)"
}

Write-Host "Uploading oral_coach llm.py ..."
scp -o ConnectTimeout=40 (Join-Path $root "tools\oral_coach\app\providers\llm.py") "${hostAlias}:/tmp/llm.py"
ssh -o ConnectTimeout=40 $hostAlias "cp /tmp/llm.py /opt/acquireenglish/tools/oral_coach/app/providers/llm.py"

Write-Host "Uploading admin_web..."
scp -o ConnectTimeout=40 -r (Join-Path $api "app\admin_web\*") "${hostAlias}:/opt/acquireenglish/services/api/app/admin_web/"
scp -o ConnectTimeout=40 -r (Join-Path $api "app\admin_web\*") "${hostAlias}:/opt/acquireenglish/www/admin/"

Write-Host "Restarting API + oral_coach and verifying..."
$verify = @'
from pathlib import Path
import json, urllib.request
token = ""
for line in Path("/opt/acquireenglish/services/api/.env").read_text().splitlines():
    if line.startswith("ADMIN_API_TOKEN="):
        token = line.split("=", 1)[1].strip().strip("'").strip('"')
req = urllib.request.Request(
    "http://127.0.0.1:5200/api/admin/usage/platform",
    headers={"X-Admin-Token": token},
)
with urllib.request.urlopen(req, timeout=90) as r:
    data = json.loads(r.read().decode())
print("ok", data.get("ok"), "configured", data.get("configured_count"))
print("platforms", data.get("configured_platforms"))
print("keys", [(k.get("id"), k.get("configured"), k.get("key_label") or k.get("source")) for k in data.get("keys") or []])
print("tencent", (data.get("tencent") or {}).get("ok"), (data.get("tencent") or {}).get("error", "")[:80])
print("deepgram", (data.get("deepgram") or {}).get("ok"), len((data.get("deepgram") or {}).get("projects") or []))
print("deepseek", (data.get("deepseek") or {}).get("configured"))
print("gpu_ok", (data.get("gpu") or {}).get("ok"), (data.get("gpu") or {}).get("error", "")[:100])
'@
$tmp = Join-Path $env:TEMP "ae_verify_platform.py"
Set-Content -Path $tmp -Value $verify -Encoding utf8
scp -o ConnectTimeout=40 $tmp "${hostAlias}:/tmp/ae_verify_platform.py"
ssh -o ConnectTimeout=40 $hostAlias "systemctl restart acquireenglish-api; systemctl restart acquireenglish-oral-coach; sleep 4; systemctl is-active acquireenglish-api; systemctl is-active acquireenglish-oral-coach; /opt/acquireenglish/services/api/.venv/bin/python /tmp/ae_verify_platform.py"
Write-Host "Done."
