$ErrorActionPreference = 'Stop'
$output = Join-Path $PSScriptRoot 'AcquireEnglishMonitor.exe'
Add-Type -Path (Join-Path $PSScriptRoot 'Monitor.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing,System.Web.Extensions -OutputAssembly $output -OutputType WindowsApplication
Write-Output $output
