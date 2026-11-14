# Restart LiveTalking if the process exits.
$ErrorActionPreference = "Continue"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\third_party\LiveTalking")).Path
$Run = Join-Path $PSScriptRoot "run_livetalking.ps1"
Set-Location $Root
while ($true) {
  try {
    Write-Host ("[{0}] starting LiveTalking" -f (Get-Date -Format o))
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Run
  } catch {
    Write-Host ("[{0}] LiveTalking crashed: {1}" -f (Get-Date -Format o), $_)
  }
  Start-Sleep -Seconds 5
}
