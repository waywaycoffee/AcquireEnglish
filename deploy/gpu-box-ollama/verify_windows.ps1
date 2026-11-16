# Verify local OpenAI-compatible qwen2.5:7b on the GPU box / Tailscale.
param(
  [string]$Base = "http://127.0.0.1:11434",
  [string]$Model = "qwen2.5:3b"
)

$ErrorActionPreference = "Stop"
$native = $Base.TrimEnd("/") -replace "/v1$", ""

Write-Host "==> GET $native/v1/models"
Invoke-RestMethod -Uri "$native/v1/models" -Headers @{ Authorization = "Bearer ollama" } -TimeoutSec 15 |
  ConvertTo-Json -Depth 4

Write-Host "==> Chat smoke ($Model)"
$body = @{
  model = $Model
  messages = @(
    @{ role = "system"; content = "You translate English to Simplified Chinese. Reply with Chinese only." }
    @{ role = "user"; content = "Hello, how are you?" }
  )
  temperature = 0.2
  max_tokens = 64
} | ConvertTo-Json -Depth 6

$resp = Invoke-RestMethod -Uri "$native/v1/chat/completions" `
  -Method Post -ContentType "application/json" `
  -Headers @{ Authorization = "Bearer ollama" } `
  -Body $body -TimeoutSec 180

$text = $resp.choices[0].message.content
Write-Host "REPLY: $text"
if ($text -match "[\u4e00-\u9fff]") {
  Write-Host "OK: Chinese translation-shaped reply"
} else {
  Write-Host "WARN: reply did not look like Chinese"
}

Write-Host ""
Write-Host "App: 翻译来源=本地 Ollama  Base=http://100.115.252.55:11434/v1  Model=$Model"
