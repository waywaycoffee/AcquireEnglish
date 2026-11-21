# Start official THU-MAIC/OpenMAIC on this GPU box (Next.js :3000, bind 0.0.0.0).
# Clone lives outside the AcquireEnglish repo: D:\OpenMAIC
# Keep this process running — generation jobs die when Node exits.
$ErrorActionPreference = "Stop"

$OpenMaicRoot = if ($env:OPENMAIC_ROOT) { $env:OPENMAIC_ROOT } else { "D:\OpenMAIC" }
$HostBind = if ($env:OPENMAIC_HOST) { $env:OPENMAIC_HOST } else { "0.0.0.0" }
$Port = if ($env:OPENMAIC_PORT) { [int]$env:OPENMAIC_PORT } else { 3000 }

if (-not (Test-Path (Join-Path $OpenMaicRoot "package.json"))) {
  Write-Error @"
OpenMAIC not found at $OpenMaicRoot
Clone first:
  git clone https://github.com/THU-MAIC/OpenMAIC.git $OpenMaicRoot
  cd $OpenMaicRoot; pnpm install
  Copy-Item .env.example .env.local; Copy-Item openmaic.example.yml openmaic.yml
See tools/openmaic/README.md
"@
}

Set-Location $OpenMaicRoot

if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
  npm install -g pnpm@10.28.0
}

if (-not (Test-Path ".\node_modules")) {
  Write-Host "Installing OpenMAIC deps (first run may take several minutes)..."
  pnpm install
}

if (-not (Test-Path ".\.env.local")) {
  Copy-Item .env.example .env.local
  Write-Host "Created .env.local from .env.example — set DATABASE_URL and an LLM API key."
}

if (-not (Test-Path ".\openmaic.yml")) {
  Copy-Item openmaic.example.yml openmaic.yml
  Write-Host "Created openmaic.yml from example — align slots with your provider."
}

# Prefer DeepSeek from oral_coach .env when not already set for OpenMAIC.
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

# Sync key into .env.local if missing (do not overwrite existing).
$envLocal = Get-Content .\.env.local -Raw -ErrorAction SilentlyContinue
if ($env:DEEPSEEK_API_KEY -and $envLocal -notmatch '(?m)^\s*DEEPSEEK_API_KEY\s*=') {
  Add-Content .\.env.local "`nDEEPSEEK_API_KEY=$($env:DEEPSEEK_API_KEY)"
}
if ($envLocal -notmatch '(?m)^\s*DATABASE_URL\s*=') {
  Write-Warning "DATABASE_URL is not set in .env.local. Start Postgres then uncomment/set it."
  Write-Warning "Docker: pnpm db:up → postgres://openmaic:openmaic-dev@127.0.0.1:5432/openmaic"
}

# Patch openmaic.yml toward DeepSeek when still on openai:gpt-5.5 defaults and we have a key.
if ($env:DEEPSEEK_API_KEY) {
  $yml = Get-Content .\openmaic.yml -Raw
  if ($yml -match 'llm:\s*openai:gpt-5\.5' -and $yml -notmatch '(?m)^\s*deepseek:') {
    $deepseekBlock = @"
providers:
  deepseek:
    preset: deepseek
    apiKey: `${DEEPSEEK_API_KEY}
    models: [deepseek-chat]

slots:
  llm: deepseek:deepseek-chat
"@
    Set-Content .\openmaic.yml $deepseekBlock -Encoding utf8
    Write-Host "Wrote minimal openmaic.yml for DeepSeek (deepseek-chat)."
  }
}

Write-Host "OpenMAIC → http://127.0.0.1:$Port"
Write-Host "Tailscale → http://100.115.252.55:$Port"
Write-Host "Capabilities → GET /api/generate-classroom/capabilities"
Write-Host "ECS OPENMAIC_URL=http://100.115.252.55:$Port"
Write-Host "Keep this window open while ECS uses the engine."

# next dev binds hostname; -H 0.0.0.0 for Tailscale reachability
pnpm exec next dev -H $HostBind -p $Port
