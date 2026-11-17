$ErrorActionPreference = 'Stop'
$executable = Join-Path $PSScriptRoot 'AcquireEnglishMonitor.exe'
if (-not (Test-Path -LiteralPath $executable)) { & (Join-Path $PSScriptRoot 'build_monitor.ps1') }
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'AcquireEnglish-Monitor' -Value ('"' + $executable + '" --background')
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'AcquireEnglish Monitor.lnk'
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
$shortcut.TargetPath = $executable
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Save()
Start-Process -FilePath $executable -WindowStyle Normal
