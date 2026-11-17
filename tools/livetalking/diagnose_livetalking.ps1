# Read-only diagnostics. Run on the GPU Windows host; no secrets are printed.
param([int]$Port = 8010)
$ErrorActionPreference = 'Continue'
Write-Host "=== LiveTalking listeners ($Port) ==="
$listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
if ($listeners.Count -eq 0) {
  Write-Host "NO_LISTENER: LiveTalking is not listening on port $Port."
} else {
  $listeners | Select-Object LocalAddress, LocalPort, OwningProcess | Format-Table
  if (@($listeners | Where-Object { $_.LocalAddress -eq '0.0.0.0' -or $_.LocalAddress -eq '::' }).Count -eq 0) {
    Write-Host 'CHECK_BIND: loopback-only listener cannot be reached from ECS.'
  }
}
Write-Host '=== Local HTTP ==='
try {
  $reply = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/index.html" -TimeoutSec 5
  Write-Host "LOCAL_HTTP=$($reply.StatusCode)"
} catch { Write-Host 'LOCAL_HTTP_FAILED' }
Write-Host '=== Tailscale ==='
if (Get-Command tailscale -ErrorAction SilentlyContinue) { tailscale ip -4 }
Write-Host '=== Firewall profile ==='
Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction | Format-Table
Write-Host 'If local HTTP succeeds but ECS cannot reach the port, check inbound firewall and Tailscale ACLs.'
Write-Host 'Do not disable the firewall. Allow TCP only from the ECS Tailscale address 100.91.187.101 when needed.'
