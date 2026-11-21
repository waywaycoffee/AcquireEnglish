# One-shot: sync admin analytics/usage to ECS and restart API.
# Uses Tailscale host by default (public :22 may accept TCP without SSH banner).
$ErrorActionPreference = "Stop"
$api = Join-Path $PSScriptRoot "..\services\api" | Resolve-Path
$hostAlias = if ($env:AE_SSH_HOST) { $env:AE_SSH_HOST } else { "acquireenglish" }

$files = @(
  "app\models.py",
  "app\main.py",
  "app\services\api_usage.py",
  "app\routers\usage.py",
  "app\routers\admin_analytics.py",
  "app\routers\writing.py",
  "app\routers\reading_speech.py"
)

Write-Host "Uploading API modules to $hostAlias ..."
scp -o ConnectTimeout=40 @($files | ForEach-Object { Join-Path $api $_ }) "${hostAlias}:/tmp/"

ssh -o ConnectTimeout=40 $hostAlias "set -e; cp /tmp/models.py /opt/acquireenglish/services/api/app/models.py; cp /tmp/main.py /opt/acquireenglish/services/api/app/main.py; cp /tmp/api_usage.py /opt/acquireenglish/services/api/app/services/api_usage.py; cp /tmp/usage.py /opt/acquireenglish/services/api/app/routers/usage.py; cp /tmp/admin_analytics.py /opt/acquireenglish/services/api/app/routers/admin_analytics.py; cp /tmp/writing.py /opt/acquireenglish/services/api/app/routers/writing.py; cp /tmp/reading_speech.py /opt/acquireenglish/services/api/app/routers/reading_speech.py"

Write-Host "Uploading admin_web..."
scp -o ConnectTimeout=40 -r (Join-Path $api "app\admin_web\*") "${hostAlias}:/opt/acquireenglish/services/api/app/admin_web/"
scp -o ConnectTimeout=40 -r (Join-Path $api "app\admin_web\*") "${hostAlias}:/opt/acquireenglish/www/admin/"

Write-Host "Restarting API and verifying..."
$verify = @'
from pathlib import Path
import urllib.request
token = ""
for line in Path("/opt/acquireenglish/services/api/.env").read_text().splitlines():
    if line.startswith("ADMIN_API_TOKEN="):
        token = line.split("=", 1)[1].strip()
for path in [
    "/api/admin/analytics/users?days=30",
    "/api/admin/usage/summary?days=30",
    "/api/admin/usage/pnl?days=30",
    "/api/admin/analytics/resources",
]:
    req = urllib.request.Request(
        "http://127.0.0.1:5200" + path,
        headers={"X-Admin-Token": token},
    )
    with urllib.request.urlopen(req, timeout=20) as r:
        body = r.read().decode()[:120].replace("\n", " ")
        print(path, r.status, body[:100])
'@
$tmp = Join-Path $env:TEMP "ae_verify_admin.py"
Set-Content -Path $tmp -Value $verify -Encoding utf8
scp -o ConnectTimeout=40 $tmp "${hostAlias}:/tmp/ae_verify_admin.py"
ssh -o ConnectTimeout=40 $hostAlias "systemctl restart acquireenglish-api; sleep 3; systemctl is-active acquireenglish-api; /opt/acquireenglish/services/api/.venv/bin/python /tmp/ae_verify_admin.py"
Write-Host "Done."
