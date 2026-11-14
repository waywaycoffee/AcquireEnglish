$ErrorActionPreference = 'Continue'
$Root = 'D:\AcquireEnglish\tools\digital_human_coach'
$RunAgent = 'D:\AcquireEnglish\tools\digital_human_coach\scripts\run_agent.ps1'
Set-Location $Root
while ($true) {
  try {
    Write-Host ("[{0}] starting acquire-oral-coach agent" -f (Get-Date -Format o))
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RunAgent
  } catch {
    Write-Host ("[{0}] agent crashed: {1}" -f (Get-Date -Format o), $_)
  }
  Start-Sleep -Seconds 5
}
