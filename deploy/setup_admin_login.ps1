# Seed admin username/password/token on ECS + save login token file on this PC.
# Usage: powershell -File deploy/setup_admin_login.ps1
# Optional env: AE_SSH_HOST, AE_ADMIN_USERNAME, AE_ADMIN_PASSWORD, AE_ADMIN_TOKEN
$ErrorActionPreference = "Stop"
$hostAlias = if ($env:AE_SSH_HOST) { $env:AE_SSH_HOST } else { "acquireenglish" }
$localDir = Join-Path $env:USERPROFILE ".acquireenglish"
New-Item -ItemType Directory -Force -Path $localDir | Out-Null

$username = if ($env:AE_ADMIN_USERNAME) { $env:AE_ADMIN_USERNAME } else { "admin" }
$password = $env:AE_ADMIN_PASSWORD
if (-not $password) {
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  $bytes = New-Object byte[] 18
  $rng.GetBytes($bytes)
  $password = [Convert]::ToBase64String($bytes).TrimEnd("=") -replace "[+/]", "A"
}

$token = $env:AE_ADMIN_TOKEN
if (-not $token) {
  $existing = ssh -o ConnectTimeout=40 -o BatchMode=yes $hostAlias "grep -E '^ADMIN_API_TOKEN=' /opt/acquireenglish/services/api/.env | head -1 | cut -d= -f2-"
  if ($existing) { $token = $existing.Trim() }
}
if (-not $token) {
  $token = -join ((48..57 + 65..90 + 97..122 | Get-Random -Count 48 | ForEach-Object { [char]$_ }))
}

$payload = @{ username = $username; password = $password; token = $token } | ConvertTo-Json -Compress
$tmpJson = Join-Path $env:TEMP "ae_admin_seed.json"
$tmpPy = Join-Path $env:TEMP "ae_seed_admin_login.py"
[System.IO.File]::WriteAllText($tmpJson, $payload)
$remotePy = @'
import json
import re
from pathlib import Path

data = json.loads(Path("/tmp/ae_admin_seed.json").read_text(encoding="utf-8"))
user = str(data["username"]).strip()
password = str(data["password"]).strip()
token = str(data["token"]).strip()
root = Path("/root")
for name, value in [
    ("acquireenglish-admin-username", user),
    ("acquireenglish-admin-password", password),
    ("acquireenglish-admin-token", token),
]:
    path = root / name
    path.write_text(value + "\n", encoding="utf-8")
    path.chmod(0o600)

env_path = Path("/opt/acquireenglish/services/api/.env")
text = env_path.read_text(encoding="utf-8") if env_path.exists() else ""

def upsert(key: str, value: str) -> None:
    global text
    line = f"{key}={value}"
    pat = re.compile(rf"^{re.escape(key)}=.*$", re.M)
    if pat.search(text):
        text = pat.sub(line, text)
    else:
        if text and not text.endswith("\n"):
            text += "\n"
        text += line + "\n"

upsert("ADMIN_USERNAME", user)
upsert("ADMIN_PASSWORD", password)
upsert("ADMIN_API_TOKEN", token)
env_path.write_text(text, encoding="utf-8")
print("seeded_ok")
'@
Set-Content -Path $tmpPy -Value $remotePy -Encoding utf8

scp -o ConnectTimeout=40 -o BatchMode=yes $tmpJson $tmpPy "${hostAlias}:/tmp/"
ssh -o ConnectTimeout=40 -o BatchMode=yes $hostAlias "/opt/acquireenglish/services/api/.venv/bin/python /tmp/ae_seed_admin_login.py; shred -u /tmp/ae_admin_seed.json 2>/dev/null || rm -f /tmp/ae_admin_seed.json; systemctl restart acquireenglish-api; sleep 2; systemctl is-active acquireenglish-api"

Set-Content -Path (Join-Path $localDir "admin_username") -Value $username -Encoding utf8
Set-Content -Path (Join-Path $localDir "admin_password") -Value $password -Encoding utf8
Set-Content -Path (Join-Path $localDir "admin_login_token") -Value $token -Encoding utf8
Set-Content -Path (Join-Path $localDir "acquireenglish-admin-login.token") -Value "$token`n" -Encoding utf8

Remove-Item $tmpJson, $tmpPy -Force -ErrorAction SilentlyContinue
Write-Host "Local token file: $(Join-Path $localDir 'acquireenglish-admin-login.token')"
Write-Host "Username: $username"
Write-Host "Password and token saved under $localDir (not in git)."
