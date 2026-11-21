# Start official THU-MAIC/OpenMAIC on this GPU box (Next.js :3000, bind 0.0.0.0).
# Clone lives outside the AcquireEnglish repo: D:\OpenMAIC (MIT, not vendored).
# Keep this process running — generation jobs die when Node exits.
$ErrorActionPreference = "Stop"

$OpenMaicRoot = if ($env:OPENMAIC_ROOT) { $env:OPENMAIC_ROOT } else { "D:\OpenMAIC" }
$HostBind = if ($env:OPENMAIC_HOST) { $env:OPENMAIC_HOST } else { "0.0.0.0" }
$Port = if ($env:OPENMAIC_PORT) { [int]$env:OPENMAIC_PORT } else { 3000 }
$PgLocalPort = if ($env:OPENMAIC_PG_LOCAL_PORT) { [int]$env:OPENMAIC_PG_LOCAL_PORT } else { 5433 }
$EcsSshHost = if ($env:OPENMAIC_ECS_SSH) { $env:OPENMAIC_ECS_SSH } else { "acquireenglish" }

if (-not (Test-Path (Join-Path $OpenMaicRoot "package.json"))) {
  Write-Error @"
OpenMAIC not found at $OpenMaicRoot
See tools/openmaic/README.md for clone / slim-transfer steps.
"@
}

Set-Location $OpenMaicRoot

if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
  npm install -g pnpm@10.28.0
}

if (-not (Test-Path ".\node_modules\next")) {
  Write-Host "Installing OpenMAIC deps (first run may take a long time)..."
  pnpm install
}

if (-not (Test-Path ".\.env.local")) {
  Copy-Item .env.example .env.local
  Write-Host "Created .env.local — set DATABASE_URL and an LLM API key."
}

if (-not (Test-Path ".\openmaic.yml")) {
  Copy-Item openmaic.example.yml openmaic.yml
}

# Prefer DeepSeek from oral_coach .env when not already set.
if (-not $env:DEEPSEEK_API_KEY) {
  $oralEnv = "D:\AcquireEnglish\tools\oral_coach\.env"
  if (Test-Path $oralEnv) {
    Get-Content $oralEnv | ForEach-Object {
      if ($_ -match '^\s*DEEPSEEK_API_KEY\s*=\s*(.+)\s*$') {
        $env:DEEPSEEK_API_KEY = $Matches[1].Trim().Trim('"').Trim("'")
      }
    }
  }
}

$envLocal = Get-Content .\.env.local -Raw -ErrorAction SilentlyContinue
if ($env:DEEPSEEK_API_KEY -and $envLocal -notmatch '(?m)^\s*DEEPSEEK_API_KEY\s*=') {
  Add-Content .\.env.local "`nDEEPSEEK_API_KEY=$($env:DEEPSEEK_API_KEY)"
}

# Default DATABASE_URL via SSH tunnel to ECS Postgres (listen_addresses=localhost there).
if ($envLocal -notmatch '(?m)^\s*DATABASE_URL\s*=') {
  $dbUrl = "postgres://openmaic:openmaic-dev@127.0.0.1:$PgLocalPort/openmaic"
  Add-Content .\.env.local "`nDATABASE_URL=$dbUrl"
  Write-Host "Appended DATABASE_URL → local tunnel :$PgLocalPort"
}

# Ensure openmaic.yml uses DeepSeek when key present and still on openai default.
if ($env:DEEPSEEK_API_KEY) {
  $yml = Get-Content .\openmaic.yml -Raw
  if ($yml -match 'llm:\s*openai:' -or $yml -notmatch '(?m)^\s*deepseek:') {
    @"
providers:
  deepseek:
    preset: deepseek
    apiKey: `${DEEPSEEK_API_KEY}
    models: [deepseek-chat]

slots:
  llm: deepseek:deepseek-chat
  video: null
"@ | Set-Content .\openmaic.yml -Encoding utf8
    Write-Host "Wrote openmaic.yml for DeepSeek."
  }
}

# SSH tunnel for ECS Postgres (skip if already listening).
$tunnelUp = $false
try {
  $c = New-Object System.Net.Sockets.TcpClient
  $c.Connect("127.0.0.1", $PgLocalPort)
  $c.Close()
  $tunnelUp = $true
} catch { $tunnelUp = $false }

if (-not $tunnelUp) {
  Write-Host "Starting SSH tunnel $EcsSshHost → 127.0.0.1:$PgLocalPort (ECS Postgres)..."
  Start-Process -FilePath "ssh.exe" -ArgumentList @(
    "-N",
    "-o", "ServerAliveInterval=30",
    "-o", "ExitOnForwardFailure=yes",
    # ECS openmaic-pg listens on 127.0.0.1:5433 (host Postgres keeps :5432).
    "-L", "${PgLocalPort}:127.0.0.1:5433",
    $EcsSshHost
  ) -WindowStyle Hidden | Out-Null
  Start-Sleep -Seconds 2
  $c2 = New-Object System.Net.Sockets.TcpClient
  try {
    $c2.Connect("127.0.0.1", $PgLocalPort)
    $c2.Close()
  } catch {
    Write-Error "Postgres tunnel failed. Run tools/openmaic/setup_ecs_pg.sh on ECS first, then: ssh -N -L ${PgLocalPort}:127.0.0.1:5433 $EcsSshHost"
  }
}

Write-Host "OpenMAIC → http://127.0.0.1:$Port"
Write-Host "Tailscale → http://100.115.252.55:$Port"
Write-Host "Capabilities → GET /api/generate-classroom/capabilities"
Write-Host "ECS OPENMAIC_URL=http://100.115.252.55:$Port"
Write-Host "Keep this window open while ECS uses the engine."
Write-Host "Mock fallback (optional): tools/openmaic_mock on :8093"

pnpm exec next dev -H $HostBind -p $Port
