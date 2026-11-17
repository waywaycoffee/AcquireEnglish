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
    readonly DataGridView grid = new DataGridView();
    readonly NotifyIcon tray = new NotifyIcon();
    readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
    readonly EventWaitHandle open;
    bool quitting;
    public MonitorWindow(EventWaitHandle signal, bool background) {
        open = signal;
        Text = "爱快英语 - 本地服务监控";
        Size = new Size(950, 560);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Microsoft YaHei UI", 10);
        Icon = SystemIcons.Information;
        summary.Dock = DockStyle.Top; summary.Height = 100; summary.Padding = new Padding(12);
        grid.Dock = DockStyle.Fill; grid.ReadOnly = true; grid.AllowUserToAddRows = false;
        grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
        foreach (string title in new [] {"客户端标识", "身份类型", "今日请求", "Token", "处理中", "最近访问"}) grid.Columns.Add(title, title);
        Label footer = new Label { Dock = DockStyle.Bottom, Height = 55, Text = "按北京时间统计；活跃为最近5分钟有请求。账号标识由客户端自报，未经身份验证。\r\n关闭窗口收起到托盘；再次打开桌面快捷方式可唤起。安装前的历史用量无法追溯。" };
        Controls.Add(grid); Controls.Add(summary); Controls.Add(footer);
        tray.Icon = Icon; tray.Text = "爱快英语 · 本地服务监控"; tray.Visible = true;
        ContextMenuStrip menu = new ContextMenuStrip();
        menu.Items.Add("打开监控面板", null, (s,e) => Reveal());
        menu.Items.Add("刷新", null, (s,e) => RefreshStats());
        menu.Items.Add("退出监控（保留推理服务）", null, (s,e) => { quitting = true; Close(); });
        tray.ContextMenuStrip = menu; tray.DoubleClick += (s,e) => Reveal();
        timer.Interval = 5000;
        timer.Tick += (s,e) => { if (open.WaitOne(0)) Reveal(); RefreshStats(); };
        FormClosing += (s,e) => { if (!quitting) { e.Cancel = true; Hide(); } };
        FormClosed += (s,e) => { timer.Dispose(); tray.Dispose(); };
        Shown += (s,e) => { if (background) Hide(); RefreshStats(); timer.Start(); };
    }
    void Reveal() { Show(); WindowState = FormWindowState.Normal; Activate(); BringToFront(); }
    void RefreshStats() {
        try {
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create("http://127.0.0.1:11435/stats");
            request.Timeout = 2000; request.Proxy = null;
            string json;
            using (var response = request.GetResponse())
            using (var reader = new System.IO.StreamReader(response.GetResponseStream())) json = reader.ReadToEnd();
            var data = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(json);
            summary.Text = String.Format("日期：{0}（北京时间）   活跃客户端：{1}\r\n今日请求：{2}   失败：{3}   Token：{4}（输入 {5} / 输出 {6}）\r\n未返回 Token 用量的请求：{7}", data["day"], data["active_clients"], data["requests"], data["failures"], data["total_tokens"], data["input_tokens"], data["output_tokens"], data["requests_without_usage"]);
            tray.Text = "爱快英语：" + data["active_clients"] + " 活跃 / " + data["total_tokens"] + " Token";
            grid.Rows.Clear();
            foreach (Dictionary<string, object> client in (ArrayList)data["clients"]) {
                DateTime last = new DateTime(1970,1,1).AddSeconds(Convert.ToDouble(client["last_seen"])).AddHours(8);
                grid.Rows.Add(client["client"], (string)client["kind"] == "self-reported account" ? "自报账号" : "匿名客户端", client["requests"], client["tokens"], client["in_flight"], last.ToString("HH:mm:ss"));
            }
        } catch (Exception error) { summary.Text = "统计暂不可用：" + error.Message + "\r\n请检查本地推理服务是否已启动。"; }
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
