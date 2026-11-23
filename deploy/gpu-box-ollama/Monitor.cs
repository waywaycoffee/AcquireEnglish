using System;
using System.Drawing;
using System.Net;
using System.Threading;
using System.Windows.Forms;
using System.Web.Script.Serialization;
using System.Collections;
using System.Collections.Generic;

class MonitorWindow : Form {
    readonly Label summary = new Label();
    readonly DataGridView servicesGrid = new DataGridView();
    readonly DataGridView grid = new DataGridView();
    readonly NotifyIcon tray = new NotifyIcon();
    readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
    readonly EventWaitHandle open;
    readonly HashSet<string> knownUnhealthy = new HashSet<string>();
    bool quitting;
    int refreshTick;

    public MonitorWindow(EventWaitHandle signal, bool background) {
        open = signal;
        Text = "爱快英语 - 本地服务监控";
        Size = new Size(980, 720);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Microsoft YaHei UI", 10);
        Icon = SystemIcons.Information;

        summary.Dock = DockStyle.Top;
        summary.Height = 118;
        summary.Padding = new Padding(12);

        Label servicesTitle = new Label {
            Dock = DockStyle.Top,
            Height = 28,
            Padding = new Padding(12, 6, 12, 0),
            Text = "后端服务健康（HTTP / 进程探测；红=不健康，橙=偏慢）"
        };

        servicesGrid.Dock = DockStyle.Top;
        servicesGrid.Height = 220;
        servicesGrid.ReadOnly = true;
        servicesGrid.AllowUserToAddRows = false;
        servicesGrid.RowHeadersVisible = false;
        servicesGrid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
        servicesGrid.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
        foreach (string title in new[] { "服务", "位置", "状态", "延迟ms", "说明" })
            servicesGrid.Columns.Add(title, title);

        grid.Dock = DockStyle.Fill;
        grid.ReadOnly = true;
        grid.AllowUserToAddRows = false;
        grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
        foreach (string title in new[] { "客户端标识", "身份类型", "今日请求", "Token", "处理中", "最近访问" })
            grid.Columns.Add(title, title);

        Label footer = new Label {
            Dock = DockStyle.Bottom,
            Height = 58,
            Text = "用量按北京时间；后端健康每约 15 秒探测一次。关闭窗口收起到托盘。关键服务异常会托盘气泡提醒。"
        };

        Controls.Add(grid);
        Controls.Add(servicesGrid);
        Controls.Add(servicesTitle);
        Controls.Add(summary);
        Controls.Add(footer);

        tray.Icon = Icon;
        tray.Text = "爱快英语 · 本地服务监控";
        tray.Visible = true;
        ContextMenuStrip menu = new ContextMenuStrip();
        menu.Items.Add("打开监控面板", null, (s, e) => Reveal());
        menu.Items.Add("刷新", null, (s, e) => RefreshAll(true));
        menu.Items.Add("退出监控（保留推理服务）", null, (s, e) => { quitting = true; Close(); });
        tray.ContextMenuStrip = menu;
        tray.DoubleClick += (s, e) => Reveal();

        timer.Interval = 5000;
        timer.Tick += (s, e) => {
            if (open.WaitOne(0)) Reveal();
            RefreshAll(false);
        };
        FormClosing += (s, e) => { if (!quitting) { e.Cancel = true; Hide(); } };
        FormClosed += (s, e) => { timer.Dispose(); tray.Dispose(); };
        Shown += (s, e) => {
            if (background) Hide();
            RefreshAll(true);
            timer.Start();
        };
    }

    void Reveal() {
        Show();
        WindowState = FormWindowState.Normal;
        Activate();
        BringToFront();
    }

    string GetJson(string url, int timeoutMs) {
        HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
        request.Timeout = timeoutMs;
        request.Proxy = null;
        using (var response = request.GetResponse())
        using (var reader = new System.IO.StreamReader(response.GetResponseStream()))
            return reader.ReadToEnd();
    }

    void RefreshAll(bool forceBackend) {
        RefreshStats();
        refreshTick++;
        if (forceBackend || refreshTick % 3 == 0)
            RefreshBackendHealth();
    }

    void RefreshStats() {
        try {
            string json = GetJson("http://127.0.0.1:11435/stats", 2000);
            var data = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(json);
            string backendLine = summary.Tag as string ?? "后端健康：探测中…";
            summary.Text = String.Format(
                "日期：{0}（北京时间）   活跃客户端：{1}\r\n今日请求：{2}   失败：{3}   Token：{4}（输入 {5} / 输出 {6}）\r\n未返回 Token 用量的请求：{7}\r\n{8}",
                data["day"], data["active_clients"], data["requests"], data["failures"],
                data["total_tokens"], data["input_tokens"], data["output_tokens"],
                data["requests_without_usage"], backendLine);
            tray.Text = Truncate("爱快英语：" + data["active_clients"] + " 活跃 / " + data["total_tokens"] + " Token", 60);
            grid.Rows.Clear();
            foreach (Dictionary<string, object> client in (ArrayList)data["clients"]) {
                DateTime last = new DateTime(1970, 1, 1).AddSeconds(Convert.ToDouble(client["last_seen"])).AddHours(8);
                grid.Rows.Add(
                    client["client"],
                    (string)client["kind"] == "self-reported account" ? "自报账号" : "匿名客户端",
                    client["requests"],
                    client["tokens"],
                    client["in_flight"],
                    last.ToString("HH:mm:ss"));
            }
        } catch (Exception error) {
            string backendLine = summary.Tag as string ?? "";
            summary.Text = "统计暂不可用：" + error.Message + "\r\n请检查本地推理服务是否已启动。\r\n" + backendLine;
        }
    }

    void RefreshBackendHealth() {
        try {
            string json = GetJson("http://127.0.0.1:11435/backend-health", 20000);
            var data = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(json);
            var counts = (Dictionary<string, object>)data["counts"];
            string overall = Convert.ToString(data["overall"]);
            string overallZh = overall == "healthy" ? "健康"
                : (overall == "degraded" ? "降级" : "不健康");
            string backendLine = String.Format(
                "后端：{0}（健康 {1} / 偏慢 {2} / 异常 {3}，关键异常 {4}）",
                overallZh, counts["healthy"], counts["degraded"], counts["unhealthy"], counts["critical_unhealthy"]);
            summary.Tag = backendLine;
            if (summary.Text.IndexOf("后端：") < 0)
                summary.Text = summary.Text.TrimEnd() + "\r\n" + backendLine;
            else {
                string[] lines = summary.Text.Replace("\r\n", "\n").Split('\n');
                if (lines.Length > 0) {
                    lines[lines.Length - 1] = backendLine;
                    summary.Text = string.Join("\r\n", lines);
                }
            }

            servicesGrid.Rows.Clear();
            HashSet<string> nowBad = new HashSet<string>();
            foreach (Dictionary<string, object> row in (ArrayList)data["services"]) {
                string state = Convert.ToString(row["state"]);
                string stateZh = state == "healthy" ? "健康"
                    : (state == "degraded" ? "偏慢" : "不健康");
                int idx = servicesGrid.Rows.Add(
                    row["name"], row["where"], stateZh, row["latency_ms"], row["detail"]);
                DataGridViewRow view = servicesGrid.Rows[idx];
                if (state == "unhealthy") {
                    view.DefaultCellStyle.BackColor = Color.FromArgb(255, 220, 220);
                    view.DefaultCellStyle.ForeColor = Color.DarkRed;
                    nowBad.Add(Convert.ToString(row["id"]));
                } else if (state == "degraded") {
                    view.DefaultCellStyle.BackColor = Color.FromArgb(255, 240, 210);
                    view.DefaultCellStyle.ForeColor = Color.DarkOrange;
                } else {
                    view.DefaultCellStyle.BackColor = Color.FromArgb(220, 245, 220);
                    view.DefaultCellStyle.ForeColor = Color.DarkGreen;
                }
            }

            List<string> newly = new List<string>();
            foreach (string id in nowBad)
                if (!knownUnhealthy.Contains(id)) newly.Add(id);
            knownUnhealthy.Clear();
            foreach (string id in nowBad) knownUnhealthy.Add(id);
            if (newly.Count > 0) {
                tray.BalloonTipTitle = "后端服务异常";
                tray.BalloonTipText = backendLine + " · 新异常 " + newly.Count + " 项";
                tray.ShowBalloonTip(5000);
            }
            if (overall != "healthy")
                tray.Text = Truncate("爱快英语 · 后端" + overallZh, 60);
        } catch (Exception error) {
            summary.Tag = "后端健康：暂不可用 · " + error.Message;
            if (servicesGrid.Rows.Count == 0)
                servicesGrid.Rows.Add("（探测失败）", "11435/backend-health", "不健康", 0, error.Message);
        }
    }

    static string Truncate(string text, int max) {
        if (string.IsNullOrEmpty(text) || text.Length <= max) return text;
        return text.Substring(0, max - 1) + "…";
    }

    [STAThread]
    static void Main(string[] args) {
        bool created;
        using (var mutex = new Mutex(true, "Local\\AcquireEnglish-NativeMonitor", out created))
        using (var signal = new EventWaitHandle(false, EventResetMode.AutoReset, "Local\\AcquireEnglish-NativeMonitor-Open")) {
            if (!created) { signal.Set(); return; }
            Application.EnableVisualStyles();
            Application.Run(new MonitorWindow(signal, Array.IndexOf(args, "--background") >= 0));
            mutex.ReleaseMutex();
        }
    }
}
