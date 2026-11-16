param([switch]$Install, [switch]$Uninstall, [switch]$Check)
$ErrorActionPreference = 'Stop'
$startupKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$startupName = 'AcquireEnglish-Monitor'
if ($Uninstall) {
    Remove-ItemProperty -Path $startupKey -Name $startupName -ErrorAction SilentlyContinue
    exit
}
if ($Install) {
    New-Item -Path $startupKey -Force | Out-Null
    $launch = 'powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    Set-ItemProperty -Path $startupKey -Name $startupName -Value $launch
}
if ($Check) {
    Invoke-RestMethod 'http://127.0.0.1:11435/stats' -TimeoutSec 3 | ConvertTo-Json -Depth 5
    exit
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$created = $false
$mutex = [Threading.Mutex]::new($true, 'Local\AcquireEnglish-Tray-Monitor', [ref]$created)
if (-not $created) { $mutex.Dispose(); exit }
[Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object Windows.Forms.Form
$form.Text = '爱快英语 - 本地服务监控'
$form.Size = New-Object Drawing.Size(880, 540)
$form.StartPosition = 'CenterScreen'
$summary = New-Object Windows.Forms.Label
$summary.Dock = 'Top'
$summary.Height = 100
$summary.Padding = New-Object Windows.Forms.Padding(12)
$summary.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10)
$grid = New-Object Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.AutoSizeColumnsMode = 'Fill'
@('客户端标识', '身份类型', '今日请求', 'Token', '处理中', '最近访问') | ForEach-Object { [void]$grid.Columns.Add($_, $_) }
$footnote = New-Object Windows.Forms.Label
$footnote.Dock = 'Bottom'
$footnote.Height = 55
$footnote.Text = "账号为客户端自报匿名标识，未经身份校验；活跃指最近 5 分钟有请求。`r`nToken 使用模型返回的实际用量，缺失计数单列；按北京时间统计。关闭窗口后收起到托盘。"
$form.Controls.Add($grid)
$form.Controls.Add($summary)
$form.Controls.Add($footnote)
$tray = New-Object Windows.Forms.NotifyIcon
$tray.Icon = [Drawing.SystemIcons]::Information
$tray.Text = 'AcquireEnglish monitor'
$tray.Visible = $true
$menu = New-Object Windows.Forms.ContextMenuStrip
$openItem = $menu.Items.Add('打开监控面板')
$refreshItem = $menu.Items.Add('刷新')
$quitItem = $menu.Items.Add('退出监控（保留推理服务）')
$tray.ContextMenuStrip = $menu
$open = { $form.Show(); $form.Activate() }
$tray.add_DoubleClick($open)
$openItem.add_Click($open)
$refresh = {
    try {
        $stats = Invoke-RestMethod 'http://127.0.0.1:11435/stats' -TimeoutSec 2
        $summary.Text = "日期：$($stats.day)（北京时间）    活跃客户端：$($stats.active_clients)`r`n今日请求：$($stats.requests)    失败：$($stats.failures)    Token：$($stats.total_tokens)（输入 $($stats.input_tokens) / 输出 $($stats.output_tokens)）`r`n未返回 Token 用量的请求：$($stats.requests_without_usage)"
        $tray.Text = "AcquireEnglish: $($stats.active_clients) active / $($stats.total_tokens) tokens".Substring(0, [Math]::Min(63, "AcquireEnglish: $($stats.active_clients) active / $($stats.total_tokens) tokens".Length))
        $grid.Rows.Clear()
        foreach ($client in $stats.clients) {
            $last = [DateTimeOffset]::FromUnixTimeSeconds([long]$client.last_seen).ToOffset([TimeSpan]::FromHours(8)).ToString('HH:mm:ss')
            [void]$grid.Rows.Add($client.client, $client.kind, $client.requests, $client.tokens, $client.in_flight, $last)
        }
    } catch {
        try {
            $null = Invoke-RestMethod 'http://127.0.0.1:11434/v1/models' -TimeoutSec 2
            $summary.Text = '推理服务可连接，统计模块未加载，请更新后重启后台。历史用量无法追溯。'
        } catch { $summary.Text = '本地推理服务与统计模块暂不可连接。' }
        $tray.Text = 'AcquireEnglish: statistics unavailable'
    }
}
$refreshItem.add_Click($refresh)
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 5000
$timer.add_Tick($refresh)
$form.add_FormClosing({ param($sender, $eventArgs) $eventArgs.Cancel = $true; $form.Hide() })
$quitItem.add_Click({ $timer.Stop(); $tray.Visible = $false; [Windows.Forms.Application]::ExitThread() })
try {
    & $refresh
    $timer.Start()
    [Windows.Forms.Application]::Run()
} finally {
    $timer.Dispose(); $tray.Dispose(); $form.Dispose()
    $mutex.ReleaseMutex(); $mutex.Dispose()
}
