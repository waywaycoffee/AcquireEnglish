# Start official THU-MAIC/OpenMAIC on this GPU box (Next.js :3000, bind 0.0.0.0).
# Source tree: D:\OpenMAIC (ECS /tmp/openmaic-src.tgz extract, or git clone — MIT, not vendored).
# Local LLM default: Ollama qwen2.5:7b @ http://127.0.0.1:11434/v1 (gpu-box shim OK).
#
# One-time: cd D:\OpenMAIC; pnpm install; ollama pull qwen2.5:7b
# Run: cd D:\AcquireEnglish\tools\openmaic; .\start.ps1
# Keep this process running — generation jobs die when Node exits.
$ErrorActionPreference = "Stop"

$OpenMaicRoot = if ($env:OPENMAIC_ROOT) { $env:OPENMAIC_ROOT } else { "D:\OpenMAIC" }
$HostBind = if ($env:OPENMAIC_HOST) { $env:OPENMAIC_HOST } else { "0.0.0.0" }
$Port = if ($env:OPENMAIC_PORT) { [int]$env:OPENMAIC_PORT } else { 3000 }
$PgLocalPort = if ($env:OPENMAIC_PG_LOCAL_PORT) { [int]$env:OPENMAIC_PG_LOCAL_PORT } else { 5433 }
$EcsSshHost = if ($env:OPENMAIC_ECS_SSH) { $env:OPENMAIC_ECS_SSH } else { "acquireenglish" }
$LocalLlmModel = if ($env:OPENMAIC_OLLAMA_MODEL) { $env:OPENMAIC_OLLAMA_MODEL } else { "qwen2.5:7b" }
$OllamaBase = if ($env:OLLAMA_BASE_URL) { $env:OLLAMA_BASE_URL } else { "http://127.0.0.1:11434/v1" }

function Resolve-OllamaExe {
  $cmd = Get-Command ollama -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($p in @("$env:LOCALAPPDATA\Programs\Ollama\ollama.exe", "C:\Program Files\Ollama\ollama.exe")) {
    if (Test-Path $p) { return $p }
  }
  return $null
}

$ollamaExe = Resolve-OllamaExe
if ($ollamaExe) {
  $ollamaList = & $ollamaExe list 2>&1 | Out-String
  if ($ollamaList -notmatch [regex]::Escape($LocalLlmModel)) {
    Write-Host "Pulling Ollama $LocalLlmModel in background..."
    Start-Process -FilePath $ollamaExe -ArgumentList "pull", $LocalLlmModel -WindowStyle Hidden
  }
} else {
  Write-Warning "ollama not found — start deploy/gpu-box-ollama shim on :11434 or install Ollama, then: ollama pull $LocalLlmModel"
}

if (-not (Test-Path (Join-Path $OpenMaicRoot "package.json"))) {
  Write-Error @"
OpenMAIC not found at $OpenMaicRoot
From ECS: scp acquireenglish:/tmp/openmaic-src.tgz D:\OpenMAIC-src.tgz; mkdir D:\OpenMAIC; tar -xzf D:\OpenMAIC-src.tgz -C D:\OpenMAIC
Or see tools/openmaic/README.md
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
  Write-Host "Created .env.local — DATABASE_URL via SSH tunnel; LLM via Ollama $LocalLlmModel."
}

if (-not (Test-Path ".\openmaic.yml")) {
  Copy-Item openmaic.example.yml openmaic.yml
}

$envLines = @(Get-Content .\.env.local -ErrorAction SilentlyContinue)
$envPatch = @()
if (($envLines | Out-String) -notmatch '(?m)^\s*ALLOW_LOCAL_NETWORKS\s*=') { $envPatch += "ALLOW_LOCAL_NETWORKS=true" }
if (($envLines | Out-String) -notmatch '(?m)^\s*OLLAMA_BASE_URL\s*=') { $envPatch += "OLLAMA_BASE_URL=$OllamaBase" }
if (($envLines | Out-String) -notmatch '(?m)^\s*OLLAMA_MODELS\s*=') { $envPatch += "OLLAMA_MODELS=$LocalLlmModel" }
if ($envPatch.Count -gt 0) {
  Add-Content .\.env.local ("`n" + ($envPatch -join "`n"))
  Write-Host "Appended Ollama env for $LocalLlmModel"
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

# openmaic.yml: DeepSeek when key present; otherwise local Ollama qwen2.5:7b.
$yml = Get-Content .\openmaic.yml -Raw
if ($env:DEEPSEEK_API_KEY -and ($yml -match 'llm:\s*openai:' -or $yml -notmatch '(?m)^\s*deepseek:')) {
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
} elseif (-not $env:DEEPSEEK_API_KEY -and $yml -match 'llm:\s*openai:' -and $yml -notmatch '(?m)^\s*ollama:') {
  @"
providers:
  ollama:
    preset: ollama
    models: [$LocalLlmModel]

slots:
  llm: ollama:$LocalLlmModel
  video: null
"@ | Set-Content .\openmaic.yml -Encoding utf8
  Write-Host "Wrote openmaic.yml for Ollama ($LocalLlmModel)."
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
    # Host Postgres on ECS (openmaic DB) listens on 127.0.0.1:5432.
    "-L", "${PgLocalPort}:127.0.0.1:5432",
    $EcsSshHost
  ) -WindowStyle Hidden | Out-Null
  Start-Sleep -Seconds 2
  $c2 = New-Object System.Net.Sockets.TcpClient
  try {
    $c2.Connect("127.0.0.1", $PgLocalPort)
    $c2.Close()
  } catch {
    Write-Error "Postgres tunnel failed. Run tools/openmaic/setup_ecs_pg.sh on ECS first, then: ssh -N -L ${PgLocalPort}:127.0.0.1:5432 $EcsSshHost"
  }
}

Write-Host "OpenMAIC → http://127.0.0.1:$Port"
Write-Host "Tailscale → http://100.115.252.55:$Port"
Write-Host "Capabilities → GET /api/generate-classroom/capabilities"
Write-Host "ECS OPENMAIC_URL=http://100.115.252.55:$Port"
Write-Host "Keep this window open while ECS uses the engine."
Write-Host "Mock fallback (optional): tools/openmaic_mock on :8093"

pnpm exec next dev -H $HostBind -p $Port
