# Start LiveKit oral-coach agent worker (Windows).
# Usage:
#   powershell -File tools/digital_human_coach/scripts/run_agent.ps1
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

$VenvPython = Join-Path $Root ".venv\Scripts\python.exe"
if (-not (Test-Path $VenvPython)) {
  Write-Error "Missing venv at $VenvPython — create with Python 3.12 and install requirements-agent.txt."
}

$EnvFile = Join-Path $Root ".env"
if (-not (Test-Path $EnvFile)) {
  Write-Error "Missing .env — copy .env.example and fill LIVEKIT_* / DEEPSEEK_API_KEY."
}

Get-Content $EnvFile | ForEach-Object {
  $line = $_.Trim()
  if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) { return }
  $parts = $line.Split("=", 2)
  $key = $parts[0].Trim()
  $val = $parts[1].Trim().Trim('"').Trim("'")
  Set-Item -Path "Env:$key" -Value $val
}

foreach ($required in @("LIVEKIT_URL", "LIVEKIT_API_KEY", "LIVEKIT_API_SECRET")) {
  $cur = [Environment]::GetEnvironmentVariable($required)
  if ([string]::IsNullOrWhiteSpace($cur)) {
    Write-Error "Set $required in .env"
  }
}

$agentName = if ($env:LIVEKIT_AGENT_NAME) { $env:LIVEKIT_AGENT_NAME } else { "acquire-oral-coach" }
Write-Host "Agent → $env:LIVEKIT_URL  name=$agentName"
Write-Host "oral_coach → $($env:ORAL_COACH_URL)"
& $VenvPython -m agent.main start
