# Restart LiveTalking if the process exits, and periodically clear zombie sessions.
$ErrorActionPreference = "Continue"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\third_party\LiveTalking")).Path
$Run = Join-Path $PSScriptRoot "run_livetalking.ps1"
$Cleanup = Join-Path $PSScriptRoot "cleanup_livetalking_sessions.ps1"
Set-Location $Root

# Background session hygiene every 90s while the process is up.
$cleanupJob = Start-Job -ScriptBlock {
  param($CleanupPath)
  while ($true) {
    try {
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CleanupPath | Out-Host
    } catch {
      Write-Host ("cleanup error: {0}" -f $_)
    }
    Start-Sleep -Seconds 90
  }
} -ArgumentList $Cleanup

try {
  while ($true) {
    try {
      Write-Host ("[{0}] starting LiveTalking" -f (Get-Date -Format o))
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Run
    } catch {
      Write-Host ("[{0}] LiveTalking crashed: {1}" -f (Get-Date -Format o), $_)
    }
    Start-Sleep -Seconds 5
  }
} finally {
  if ($cleanupJob) {
    Stop-Job $cleanupJob -ErrorAction SilentlyContinue
    Remove-Job $cleanupJob -Force -ErrorAction SilentlyContinue
  }
}
