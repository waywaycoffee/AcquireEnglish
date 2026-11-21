# Start OpenMAIC-compatible decompose mock on the local GPU box (default :8093).
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path .\.venv)) {
  python -m venv .venv
}
.\.venv\Scripts\python.exe -m pip install -q -r requirements.txt

$env:OPENMAIC_MOCK_HOST = if ($env:OPENMAIC_MOCK_HOST) { $env:OPENMAIC_MOCK_HOST } else { "0.0.0.0" }
$env:OPENMAIC_MOCK_PORT = if ($env:OPENMAIC_MOCK_PORT) { $env:OPENMAIC_MOCK_PORT } else { "8093" }

Write-Host "OpenMAIC mock → http://127.0.0.1:$($env:OPENMAIC_MOCK_PORT)/api/health"
Write-Host "Tailscale     → http://100.115.252.55:$($env:OPENMAIC_MOCK_PORT)/api/health"
.\.venv\Scripts\python.exe -m uvicorn app:app --host $env:OPENMAIC_MOCK_HOST --port $env:OPENMAIC_MOCK_PORT
