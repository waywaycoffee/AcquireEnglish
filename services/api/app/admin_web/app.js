(() => {
  const TOKEN_KEY = "ae_admin_token";
  const USER_KEY = "ae_admin_username";
  const TOKEN_FILENAME = "acquireenglish-admin-login.token";
  // Keep in sync with services/api/app/services/commerce/catalog.py MODULE_DEFS.
  const MODULE_DEFS = [
    { code: "exam_reading", title: "考试阅读" },
    { code: "exam_listening", title: "考试听说" },
    { code: "acquire_reading", title: "习得阅读" },
    { code: "acquire_listening", title: "习得听说" },
  ];
  const MODULE_TITLE = Object.fromEntries(
    MODULE_DEFS.map((m) => [m.code, m.title])
  );

  function moduleLabel(code) {
    const key = String(code || "").trim();
    return MODULE_TITLE[key] || key;
  }

  function normalizeGrantKind(kind) {
    const k = String(kind || "").trim();
    if (k === "module" || k === "module_permanent" || k === "module_combo") {
      return "module";
    }
    return k;
  }

  const state = {
    token: localStorage.getItem(TOKEN_KEY) || "",
    username: localStorage.getItem(USER_KEY) || "admin",
    offset: 0,
    limit: 40,
    total: 0,
    q: "",
    selectedId: null,
    skus: [],
    tab: "dashboard",
  };

  const $ = (id) => document.getElementById(id);
  const loginView = $("loginView");
  const appView = $("appView");
  const loginError = $("loginError");
  const titles = {
    dashboard: "可视化看板",
    feedback: "意见反馈",
    infra: "ECS / 云盘监控",
    usage: "用量 / 平台账单",
    resources: "公共资源库",
    fingerprint: "指纹缓存",
    users: "用户与资产",
    community: "社区帖子",
  };
  const feedbackState = { offset: 0, limit: 40, total: 0, status: "open", q: "" };
  const communityState = { offset: 0, limit: 40, total: 0, q: "", status: "" };

  async function api(path, options = {}) {
    const headers = Object.assign(
      { "Content-Type": "application/json", "X-Admin-Token": state.token },
      options.headers || {}
    );
    const res = await fetch(`/api/admin${path}`, { ...options, headers });
    const text = await res.text();
    let data = null;
    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      data = { detail: text };
    }
    if (!res.ok) {
      const detail = (data && (data.detail || data.message)) || `HTTP ${res.status}`;
      throw new Error(typeof detail === "string" ? detail : JSON.stringify(detail));
    }
    return data;
  }

  function escapeHtml(value) {
    return String(value ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }
  function escapeAttr(value) {
    return escapeHtml(value).replace(/'/g, "&#39;");
  }
  function money(n, prefix = "¥") {
    const v = Number(n || 0);
    if (Math.abs(v) < 0.01 && v !== 0) return prefix + v.toFixed(4);
    return prefix + v.toFixed(2);
  }
  function num(n) {
    return Number(n || 0).toLocaleString("zh-CN");
  }

  function barList(items, labelKey, valueKey) {
    const max = Math.max(1, ...items.map((i) => Number(i[valueKey] || 0)));
    if (!items.length) return `<p class="muted">暂无数据</p>`;
    return `<div class="bars">${items
      .map((i) => {
        const v = Number(i[valueKey] || 0);
        const pct = Math.round((v / max) * 100);
        return `<div class="bar-row"><span>${escapeHtml(i[labelKey])}</span>
          <div class="bar-track"><div class="bar-fill" style="width:${pct}%"></div></div>
          <strong>${num(v)}</strong></div>`;
      })
      .join("")}</div>`;
  }

  function sparkline(series, valueKey = "count") {
    if (!series.length) return "";
    const vals = series.map((s) => Number(s[valueKey] || 0));
    const max = Math.max(1, ...vals);
    const w = 640;
    const h = 120;
    const step = w / Math.max(1, vals.length - 1);
    const pts = vals
      .map((v, i) => `${(i * step).toFixed(1)},${(h - (v / max) * (h - 8) - 4).toFixed(1)}`)
      .join(" ");
    return `<svg class="spark" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none">
      <polyline fill="none" stroke="#2f5d3a" stroke-width="3" points="${pts}" />
    </svg>`;
  }

  function showLogin(err = "") {
    loginView.classList.remove("hidden");
    appView.classList.add("hidden");
    loginError.textContent = err;
  }
  function showApp() {
    loginView.classList.add("hidden");
    appView.classList.remove("hidden");
  }

  function setTab(tab) {
    state.tab = tab;
    $("pageTitle").textContent = titles[tab] || tab;
    document.querySelectorAll(".tab").forEach((btn) => {
      btn.classList.toggle("active", btn.dataset.tab === tab);
    });
    ["dashboard", "feedback", "infra", "usage", "resources", "fingerprint", "users", "community"].forEach((id) => {
      $(`panel-${id}`).classList.toggle("hidden", id !== tab);
    });
  }

  async function loadFingerprint() {
    const el = $("panel-fingerprint");
    el.innerHTML = `<p class="muted">加载指纹缓存…</p>`;
    const [stats, cfg] = await Promise.all([
      api("/fingerprint-cache/stats?days=30"),
      api("/fingerprint-cache/config"),
    ]);
    const top = (stats.top_assets || [])
      .map(
        (a) => `<tr>
          <td>${escapeHtml(a.asset_name || a.id)}</td>
          <td>${escapeHtml(a.source_type || "")}</td>
          <td>${num(a.hit_count)}</td>
          <td>${escapeHtml(a.cefr_level || "—")}</td>
          <td><button type="button" class="btn ghost fp-ban" data-id="${escapeAttr(
            a.id
          )}">下架</button></td>
        </tr>`
      )
      .join("");
    const banned = (stats.banned_assets || [])
      .map(
        (a) =>
          `<li>${escapeHtml(a.asset_name || a.id)} · hits ${num(a.hit_count)}</li>`
      )
      .join("");
    el.innerHTML = `
      <div class="kpi-row">
        <div class="stat"><span class="muted">命中</span><strong>${num(
          stats.hit_count
        )}</strong></div>
        <div class="stat"><span class="muted">未命中</span><strong>${num(
          stats.miss_count
        )}</strong></div>
        <div class="stat"><span class="muted">命中率</span><strong>${
          stats.hit_rate == null ? "—" : (Number(stats.hit_rate) * 100).toFixed(1) + "%"
        }</strong></div>
        <div class="stat"><span class="muted">GPU 节省(估)</span><strong>${num(
          stats.gpu_saved_minutes_est
        )} 分</strong></div>
      </div>
      <div class="kpi-row">
        <div class="stat"><span class="muted">公共资产</span><strong>${num(
          stats.asset_cache_total
        )}</strong></div>
        <div class="stat"><span class="muted">有效指纹</span><strong>${num(
          stats.fingerprint_valid_total
        )}</strong></div>
        <div class="stat"><span class="muted">向量后端</span><strong>${escapeHtml(
          stats.vector_backend || "—"
        )}</strong></div>
        <div class="stat"><span class="muted">Embed URL</span><strong>${
          cfg.embed_url_configured ? "已配" : "未配"
        }</strong></div>
      </div>
      <div class="dash-grid">
        <div class="dash-card full">
          <h3>热门缓存 TOP</h3>
          <div class="table-wrap"><table>
            <thead><tr><th>教材</th><th>类型</th><th>命中</th><th>CEFR</th><th></th></tr></thead>
            <tbody>${top || `<tr><td colspan="5" class="muted">暂无</td></tr>`}</tbody>
          </table></div>
        </div>
        <div class="dash-card">
          <h3>违规 / 已下架</h3>
          <ul>${banned || `<li class="muted">无</li>`}</ul>
        </div>
        <div class="dash-card">
          <h3>运维操作</h3>
          <div class="actions" style="flex-direction:column;align-items:stretch;gap:8px">
            <button type="button" class="btn primary" id="fpDrainBtn">排空 GPU 队列</button>
            <button type="button" class="btn ghost" id="fpLruBtn">执行 LRU 淘汰</button>
          </div>
          <p class="muted">阈值改动会写入 media/misc/fingerprint_runtime_config.json，重启后仍生效。</p>
        </div>
        <div class="dash-card full">
          <h3>阈值配置</h3>
          <form id="fpConfigForm" class="grant-grid">
            <label>开关
              <select name="enabled">
                <option value="true" ${cfg.enabled ? "selected" : ""}>开启</option>
                <option value="false" ${!cfg.enabled ? "selected" : ""}>关闭</option>
              </select>
            </label>
            <label>SimHash 汉明上限<input name="sim_hamming_max" type="number" value="${escapeAttr(
              cfg.sim_hamming_max
            )}" /></label>
            <label>最少相似块<input name="min_similar_blocks" type="number" value="${escapeAttr(
              cfg.min_similar_blocks
            )}" /></label>
            <label>向量分下限<input name="vec_score_min" type="number" step="0.01" value="${escapeAttr(
              cfg.vec_score_min
            )}" /></label>
            <label>长度偏差<input name="len_ratio_max" type="number" step="0.01" value="${escapeAttr(
              cfg.len_ratio_max
            )}" /></label>
            <label>最大块数<input name="max_blocks" type="number" value="${escapeAttr(
              cfg.max_blocks
            )}" /></label>
            <label>LRU 最小命中<input name="lru_min_hits" type="number" value="${escapeAttr(
              cfg.lru_min_hits
            )}" /></label>
            <label>LRU 空闲天<input name="lru_idle_days" type="number" value="${escapeAttr(
              cfg.lru_idle_days
            )}" /></label>
            <button class="btn primary full" type="submit">保存配置</button>
          </form>
        </div>
      </div>`;

    el.querySelectorAll(".fp-ban").forEach((btn) => {
      btn.addEventListener("click", async () => {
        if (!confirm("确认下架该公共缓存资产？")) return;
        try {
          await api("/fingerprint-cache/invalidate", {
            method: "POST",
            body: JSON.stringify({ asset_id: btn.dataset.id, ban_asset: true }),
          });
          await loadFingerprint();
        } catch (e) {
          alert(e.message);
        }
      });
    });
    $("fpDrainBtn").addEventListener("click", async () => {
      try {
        const r = await api("/fingerprint-cache/drain-queue?limit=5", { method: "POST" });
        alert(`已处理 ${r.processed || 0} 条`);
        await loadFingerprint();
      } catch (e) {
        alert(e.message);
      }
    });
    $("fpLruBtn").addEventListener("click", async () => {
      try {
        const r = await api("/fingerprint-cache/lru-evict?limit=20", { method: "POST" });
        alert(`淘汰 ${Array.isArray(r.removed) ? r.removed.length : r.removed || 0} 条`);
        await loadFingerprint();
      } catch (e) {
        alert(e.message);
      }
    });
    $("fpConfigForm").addEventListener("submit", async (e) => {
      e.preventDefault();
      const fd = new FormData(e.target);
      const body = {
        enabled: fd.get("enabled") === "true",
        sim_hamming_max: Number(fd.get("sim_hamming_max")),
        min_similar_blocks: Number(fd.get("min_similar_blocks")),
        vec_score_min: Number(fd.get("vec_score_min")),
        len_ratio_max: Number(fd.get("len_ratio_max")),
        max_blocks: Number(fd.get("max_blocks")),
        lru_min_hits: Number(fd.get("lru_min_hits")),
        lru_idle_days: Number(fd.get("lru_idle_days")),
      };
      try {
        await api("/fingerprint-cache/config", {
          method: "PATCH",
          body: JSON.stringify(body),
        });
        alert("已保存");
        await loadFingerprint();
      } catch (err) {
        alert(err.message);
      }
    });
  }

  const FEEDBACK_CAT = {
    bug: "缺陷",
    ux: "体验",
    content: "内容",
    performance: "性能",
    billing: "会员/支付",
    feature: "功能建议",
    general: "综合",
  };

  async function loadFeedback() {
    const params = new URLSearchParams({
      limit: String(feedbackState.limit),
      offset: String(feedbackState.offset),
    });
    if (feedbackState.status) params.set("status", feedbackState.status);
    if (feedbackState.q) params.set("q", feedbackState.q);
    const data = await api(`/feedback?${params.toString()}`);
    feedbackState.total = data.total || 0;
    const badge = $("feedbackOpenBadge");
    if (badge) badge.textContent = `· 待处理 ${data.open_count || 0}`;
    const list = $("feedbackList");
    const items = data.items || [];
    if (!items.length) {
      list.innerHTML = `<p class="empty">暂无反馈</p>`;
    } else {
      list.innerHTML = items
        .map((item) => {
          const who =
            item.user_display_name ||
            item.user_email ||
            item.user_phone ||
            `用户 #${item.user_id}`;
          const when = item.created_at
            ? new Date(item.created_at).toLocaleString("zh-CN")
            : "";
          return `<article class="user-card" data-fid="${item.id}">
            <div class="user-card-top">
              <strong>${escapeHtml(item.title || "意见反馈")}</strong>
              <span class="chip">${escapeHtml(item.status)}</span>
            </div>
            <p class="muted">${escapeHtml(FEEDBACK_CAT[item.category] || item.category)} · ${escapeHtml(who)} · ${escapeHtml(when)}</p>
            <p style="white-space:pre-wrap;margin:8px 0">${escapeHtml(item.body)}</p>
            ${item.contact ? `<p class="muted">联系：${escapeHtml(item.contact)}</p>` : ""}
            ${item.app_version ? `<p class="muted">版本：${escapeHtml(item.app_version)}</p>` : ""}
            <div class="login-actions" style="margin-top:8px">
              <button type="button" class="btn ghost fb-status" data-id="${item.id}" data-status="read">标为已读</button>
              <button type="button" class="btn ghost fb-status" data-id="${item.id}" data-status="done">标为完成</button>
              <button type="button" class="btn ghost fb-status" data-id="${item.id}" data-status="open">重开</button>
            </div>
            ${item.admin_note ? `<p class="muted">备注：${escapeHtml(item.admin_note)}</p>` : ""}
          </article>`;
        })
        .join("");
      list.querySelectorAll(".fb-status").forEach((btn) => {
        btn.addEventListener("click", async () => {
          try {
            await api(`/feedback/${btn.dataset.id}`, {
              method: "PATCH",
              body: JSON.stringify({ status: btn.dataset.status, admin_note: "" }),
            });
            await loadFeedback();
          } catch (e) {
            alert(e.message);
          }
        });
      });
    }
    $("feedbackPageInfo").textContent = `${feedbackState.offset + 1}-${Math.min(
      feedbackState.offset + feedbackState.limit,
      feedbackState.total
    )} / ${feedbackState.total}`;
  }

  function pctBar(pct, label) {
    const v = Math.max(0, Math.min(100, Number(pct || 0)));
    const tone = v >= 85 ? "hot" : v >= 70 ? "warm" : "ok";
    return `<div class="meter ${tone}"><div class="meter-head"><span>${escapeHtml(
      label
    )}</span><strong>${v.toFixed(1)}%</strong></div>
      <div class="bar-track"><div class="bar-fill" style="width:${v}%"></div></div></div>`;
  }

  function downloadTokenFile(token) {
    const blob = new Blob([token + "\n"], { type: "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = TOKEN_FILENAME;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }

  function parseTokenFileText(raw) {
    const text = String(raw || "").trim();
    if (!text) return "";
    try {
      const obj = JSON.parse(text);
      if (obj && typeof obj === "object") {
        return String(obj.token || obj.admin_api_token || obj.ADMIN_API_TOKEN || "").trim();
      }
    } catch {
      /* plain token file */
    }
    const first = text.split(/\r?\n/).map((l) => l.trim()).find((l) => l && !l.startsWith("#"));
    return first || "";
  }

  async function login() {
    const username = $("usernameInput").value.trim();
    const password = $("passwordInput").value;
    const token = $("tokenInput").value.trim();
    if (!username || !password || !token) {
      loginError.textContent = "请填写管理员账号、密码和登录令牌";
      return;
    }
    loginError.textContent = "";
    try {
      const res = await fetch("/api/admin/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username, password, token }),
      });
      const text = await res.text();
      let data = null;
      try {
        data = text ? JSON.parse(text) : null;
      } catch {
        data = { detail: text };
      }
      if (!res.ok) {
        const detail = (data && (data.detail || data.message)) || `HTTP ${res.status}`;
        throw new Error(typeof detail === "string" ? detail : JSON.stringify(detail));
      }
      state.token = (data && data.token) || token;
      state.username = (data && data.username) || username;
      localStorage.setItem(TOKEN_KEY, state.token);
      localStorage.setItem(USER_KEY, state.username);
      $("passwordInput").value = "";
      showApp();
      await bootstrap();
    } catch (e) {
      localStorage.removeItem(TOKEN_KEY);
      showLogin(e.message || "登录失败");
    }
  }
  function logout() {
    state.token = "";
    localStorage.removeItem(TOKEN_KEY);
    $("passwordInput").value = "";
    showLogin();
  }

  function loadTokenFromFile(file) {
    const reader = new FileReader();
    reader.onload = () => {
      const token = parseTokenFileText(reader.result);
      if (!token) {
        loginError.textContent = "令牌文件为空或格式无法识别";
        return;
      }
      $("tokenInput").value = token;
      loginError.textContent = "";
    };
    reader.onerror = () => {
      loginError.textContent = "读取令牌文件失败";
    };
    reader.readAsText(file);
  }

  function saveTokenToLocal() {
    const token = ($("tokenInput").value.trim() || state.token || "").trim();
    if (!token) {
      loginError.textContent = "没有可保存的令牌，请先填写或登录";
      return;
    }
    downloadTokenFile(token);
    loginError.textContent = "";
  }

  async function bootstrap() {
    setTab(state.tab);
    // Do not eagerly load infra/usage here: those endpoints do heavy sync I/O / vendor HTTP
    // and used to block the API event loop, leaving the users pane stuck on 「加载中…」.
    await Promise.all([
      loadDashboard().catch((e) => console.warn(e)),
      loadStats(),
      loadUsers(),
      loadSkus(),
    ]);
    if (state.tab === "resources") {
      loadResources().catch((e) => console.warn(e));
    }
    if (state.tab === "community") {
      loadCommunityPosts().catch((e) => console.warn(e));
    }
    if (state.selectedId) await loadDetail(state.selectedId);
  }

  function formatBytes(n) {
    const v = Number(n || 0);
    if (v < 1024) return `${v} B`;
    if (v < 1024 * 1024) return `${(v / 1024).toFixed(1)} KB`;
    if (v < 1024 * 1024 * 1024) return `${(v / (1024 * 1024)).toFixed(1)} MB`;
    return `${(v / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  }

  async function loadInfra() {
    const data = await api("/analytics/infra");
    const host = data.host || {};
    const mem = host.memory || {};
    const root = host.root_disk || {};
    const aliyun = data.aliyun || {};
    const inst = aliyun.instance || {};
    const el = $("panel-infra");
    const alertHtml = (data.alerts || [])
      .map(
        (a) =>
          `<div class="alert ${escapeAttr(a.level || "info")}">${escapeHtml(
            a.message || ""
          )}</div>`
      )
      .join("");
    el.innerHTML = `
      <div class="kpi-row kpi-5">
        <div class="stat"><span class="muted">主机</span><strong>${escapeHtml(
          host.hostname || "—"
        )}</strong></div>
        <div class="stat"><span class="muted">运行时长</span><strong>${escapeHtml(
          host.uptime_human || "—"
        )}</strong></div>
        <div class="stat"><span class="muted">CPU</span><strong>${
          host.cpu_percent == null ? "—" : host.cpu_percent + "%"
        }</strong><span class="muted">${num(host.cpu_cores)} 核 · load ${escapeHtml(
          String((host.loadavg && host.loadavg["1m"]) ?? "—")
        )}</span></div>
        <div class="stat"><span class="muted">内存</span><strong>${
          mem.used_pct == null ? "—" : mem.used_pct + "%"
        }</strong><span class="muted">${escapeHtml(mem.used_human || "")} / ${escapeHtml(
          mem.total_human || ""
        )}</span></div>
        <div class="stat"><span class="muted">系统盘</span><strong>${
          root.used_pct == null ? "—" : root.used_pct + "%"
        }</strong><span class="muted">${escapeHtml(root.used_human || "")} / ${escapeHtml(
          root.total_human || ""
        )}</span></div>
      </div>
      ${alertHtml ? `<div class="alert-row">${alertHtml}</div>` : ""}
      <div class="dash-grid">
        <div class="dash-card">
          <h3>资源占用</h3>
          ${pctBar(host.cpu_percent, "CPU")}
          ${pctBar(mem.used_pct, "内存")}
          ${pctBar(root.used_pct, "根分区 /")}
          <div class="note-box">采集时间 ${escapeHtml(data.collected_at || "")}</div>
        </div>
        <div class="dash-card">
          <h3>关键服务</h3>
          <div class="table-wrap"><table>
            <thead><tr><th>服务</th><th>状态</th></tr></thead>
            <tbody>
              ${Object.entries(data.services || {})
                .map(
                  ([name, st]) =>
                    `<tr><td>${escapeHtml(name)}</td><td><span class="chip ${
                      st === "active" ? "ok" : "bad"
                    }">${escapeHtml(st)}</span></td></tr>`
                )
                .join("")}
            </tbody>
          </table></div>
        </div>
        <div class="dash-card full">
          <h3>挂载点 / 本机磁盘用量</h3>
          <div class="table-wrap"><table>
            <thead><tr><th>设备</th><th>挂载</th><th>类型</th><th>已用</th><th>总量</th><th>使用率</th></tr></thead>
            <tbody>
              ${(data.mounts || [])
                .map(
                  (m) => `<tr>
                  <td>${escapeHtml(m.device)}</td>
                  <td>${escapeHtml(m.mount)}</td>
                  <td>${escapeHtml(m.fstype)}</td>
                  <td>${escapeHtml(m.used_human)}</td>
                  <td>${escapeHtml(m.total_human)}</td>
                  <td>${num(m.used_pct)}%</td>
                </tr>`
                )
                .join("") || `<tr><td colspan="6" class="muted">无挂载数据</td></tr>`}
            </tbody>
          </table></div>
        </div>
        <div class="dash-card full">
          <h3>块设备（含云盘虚拟盘）</h3>
          <div class="table-wrap"><table>
            <thead><tr><th>名称</th><th>类型</th><th>容量</th><th>挂载</th><th>序列号</th><th>云盘?</th></tr></thead>
            <tbody>
              ${(data.block_devices || [])
                .map(
                  (d) => `<tr>
                  <td>${escapeHtml(d.name)}</td>
                  <td>${escapeHtml(d.type)}</td>
                  <td>${escapeHtml(d.size_human)}</td>
                  <td>${escapeHtml(d.mountpoint || "—")}</td>
                  <td>${escapeHtml(d.serial || "—")}</td>
                  <td>${d.likely_cloud_disk ? "是" : "—"}</td>
                </tr>`
                )
                .join("") || `<tr><td colspan="6" class="muted">无块设备数据</td></tr>`}
            </tbody>
          </table></div>
        </div>
        <div class="dash-card full">
          <h3>阿里云 ECS / 云盘（控制台）</h3>
          <div class="note-box">
            ${
              aliyun.ok
                ? `区域 ${escapeHtml(aliyun.region_id || "")} · 实例 ${escapeHtml(
                    inst.instance_id || aliyun.instance_id || ""
                  )} · 状态 ${escapeHtml(inst.status || "")} · 规格 ${escapeHtml(
                    String(inst.instance_type || "")
                  )}`
                : escapeHtml(aliyun.note || aliyun.error || "云盘 API 未就绪，仍显示本机磁盘。")
            }
          </div>
          <div class="table-wrap"><table>
            <thead><tr><th>DiskId</th><th>名称</th><th>类别</th><th>类型</th><th>容量</th><th>设备</th><th>状态</th><th>性能</th></tr></thead>
            <tbody>
              ${(aliyun.disks || [])
                .map(
                  (d) => `<tr>
                  <td>${escapeHtml(d.disk_id)}</td>
                  <td>${escapeHtml(d.disk_name || "—")}</td>
                  <td>${escapeHtml(d.category || "—")}</td>
                  <td>${escapeHtml(d.type || "—")}</td>
                  <td>${escapeHtml(d.size_human || "")}</td>
                  <td>${escapeHtml(d.device || "—")}</td>
                  <td>${escapeHtml(d.status || "—")}</td>
                  <td>${escapeHtml(
                    [d.performance_level, d.iops ? d.iops + " IOPS" : ""]
                      .filter(Boolean)
                      .join(" · ") || "—"
                  )}</td>
                </tr>`
                )
                .join("") ||
              `<tr><td colspan="8" class="muted">暂无阿里云盘列表。配置具有 ECS 只读权限的 AccessKey 后可显示系统盘/数据盘详情。</td></tr>`}
            </tbody>
          </table></div>
        </div>
        <div class="dash-card full">
          <h3>应用目录占用</h3>
          <div class="table-wrap"><table>
            <thead><tr><th>目录</th><th>路径</th><th>大小</th></tr></thead>
            <tbody>
              ${(data.app_dirs || [])
                .map(
                  (d) =>
                    `<tr><td>${escapeHtml(d.name)}</td><td>${escapeHtml(
                      d.path
                    )}</td><td>${escapeHtml(d.human)}</td></tr>`
                )
                .join("")}
            </tbody>
          </table></div>
        </div>
      </div>`;
  }

  async function loadDashboard() {
    const [users, learning, pnl, infra] = await Promise.all([
      api("/analytics/users?days=90"),
      api("/analytics/learning"),
      api("/usage/pnl?days=30"),
      api("/analytics/infra").catch(() => null),
    ]);
    const host = (infra && infra.host) || {};
    const mem = host.memory || {};
    const root = host.root_disk || {};
    const el = $("panel-dashboard");
    el.innerHTML = `
      <div class="kpi-row">
        <div class="stat"><span class="muted">总用户</span><strong>${num(users.total_users)}</strong></div>
        <div class="stat"><span class="muted">近 ${users.days} 日新增</span><strong>${num(users.new_users)}</strong></div>
        <div class="stat"><span class="muted">30 日收入</span><strong>${money(pnl.revenue_cny)}</strong></div>
        <div class="stat"><span class="muted">30 日毛利</span><strong>${money(pnl.gross_cny)}</strong></div>
      </div>
      ${
        infra
          ? `<div class="kpi-row">
        <div class="stat"><span class="muted">ECS CPU</span><strong>${
          host.cpu_percent == null ? "—" : host.cpu_percent + "%"
        }</strong></div>
        <div class="stat"><span class="muted">内存</span><strong>${
          mem.used_pct == null ? "—" : mem.used_pct + "%"
        }</strong></div>
        <div class="stat"><span class="muted">系统盘</span><strong>${
          root.used_pct == null ? "—" : root.used_pct + "%"
        }</strong></div>
        <div class="stat"><span class="muted">API 服务</span><strong>${escapeHtml(
          (infra.services && infra.services["acquireenglish-api"]) || "—"
        )}</strong></div>
      </div>`
          : ""
      }
      <div class="dash-grid">
        <div class="dash-card full">
          <h3>注册趋势（90 日）</h3>
          ${sparkline(users.registration_series)}
          <div class="note-box">微信绑定 ${num(users.wechat_bound)} · 手机绑定 ${num(users.phone_bound)} · 填写偏好 ${num(users.preference_coverage)}</div>
        </div>
        <div class="dash-card">
          <h3>CEFR / 级别分布</h3>
          ${barList(users.level_distribution, "level", "count")}
        </div>
        <div class="dash-card">
          <h3>学习偏好标签</h3>
          ${barList(users.tag_distribution, "tag", "count")}
          <div class="note-box">${escapeHtml(users.gender?.note || "")}</div>
        </div>
        <div class="dash-card">
          <h3>热门课程（进度）</h3>
          ${barList(
            (learning.top_courses || []).slice(0, 12).map((c) => ({
              label: c.course_id,
              count: c.sessions,
            })),
            "label",
            "count"
          )}
        </div>
        <div class="dash-card">
          <h3>词汇量掌握</h3>
          ${barList(learning.vocab?.mastery || [], "mastery", "count")}
          <div class="note-box">生词总量 ${num(learning.vocab?.total_items)} · 有词用户 ${num(learning.vocab?.users_with_vocab)}</div>
        </div>
        <div class="dash-card full">
          <h3>热门导入视频</h3>
          <div class="table-wrap"><table>
            <thead><tr><th>来源</th><th>标题</th><th>导入次数</th></tr></thead>
            <tbody>
              ${(learning.top_imported_videos || [])
                .slice(0, 15)
                .map(
                  (v) =>
                    `<tr><td>${escapeHtml(v.source)}</td><td>${escapeHtml(
                      v.title
                    )}</td><td>${num(v.imports)}</td></tr>`
                )
                .join("") || `<tr><td colspan="3" class="muted">暂无</td></tr>`}
            </tbody>
          </table></div>
          <div class="note-box">${escapeHtml(learning.note || "")}</div>
        </div>
      </div>`;
  }

  async function loadUsage() {
    const [summary, pnl, platform] = await Promise.all([
      api("/usage/summary?days=30"),
      api("/usage/pnl?days=30"),
      api("/usage/platform").catch((e) => ({ ok: false, error: e.message, keys: [] })),
    ]);
    const platSum = (platform && platform.summary) || {};
    const aliyun = (platform && platform.aliyun) || {};
    const tencent = (platform && platform.tencent) || {};
    const deepgram = (platform && platform.deepgram) || {};
    const deepseek = (platform && platform.deepseek) || {};
    const gpu = (platform && platform.gpu) || {};
    const labelsZh = (platform && platform.module_labels_zh) || {};
    const sfm = ((aliyun.products || {}).sfm || {});
    const gpuLedger = (summary && summary.gpu) || {};
    const moduleLabel = (m) => labelsZh[m] || (m && m !== "unknown" ? m : "未标注模块");
    const el = $("panel-usage");
    el.innerHTML = `
      <div class="kpi-row">
        <div class="stat"><span class="muted">Token 总量</span><strong>${num(summary.tokens)}</strong></div>
        <div class="stat"><span class="muted">估算成本</span><strong>${money(summary.cost_cny)}</strong></div>
        <div class="stat"><span class="muted">平台 COGS</span><strong>${money(pnl.api_cost_cny_platform)}</strong></div>
        <div class="stat"><span class="muted">毛利率</span><strong>${
          pnl.margin_pct == null ? "—" : pnl.margin_pct + "%"
        }</strong></div>
      </div>
      <div class="kpi-row">
        <div class="stat"><span class="muted">已接入平台数</span><strong>${num(
          platform.configured_count || 0
        )}</strong></div>
        <div class="stat"><span class="muted">阿里云余额</span><strong>${
          platSum.aliyun_balance_cny == null ? "—" : money(platSum.aliyun_balance_cny)
        }</strong></div>
        <div class="stat"><span class="muted">百炼本月</span><strong>${money(
          platSum.dashscope_sfm_cny || 0
        )}</strong></div>
        <div class="stat"><span class="muted">5060Ti 今日 Token</span><strong>${
          platSum.gpu_tokens_today == null ? "—" : num(platSum.gpu_tokens_today)
        }</strong></div>
      </div>
      <div class="dash-grid">
        <div class="dash-card full">
          <h3>全部接入平台 / API Key（指纹，无明文）</h3>
          <div class="table-wrap"><table>
            <thead><tr><th>平台</th><th>环境变量</th><th>来源</th><th>状态</th><th>指纹/端点</th><th>用途</th><th>账单来源</th></tr></thead>
            <tbody>
              ${(platform.keys || [])
                .map(
                  (k) => `<tr>
                  <td>${escapeHtml(k.label)}</td>
                  <td><code>${escapeHtml(k.env)}</code></td>
                  <td>${escapeHtml(k.source || "—")}</td>
                  <td><span class="chip ${k.configured ? "ok" : "bad"}">${
                    k.configured ? "已配置" : "未配置"
                  }</span></td>
                  <td>${escapeHtml(k.key_label || k.key_fingerprint || "—")}</td>
                  <td>${escapeHtml(k.usage || "")}</td>
                  <td>${escapeHtml(k.billing || "")}</td>
                </tr>`
                )
                .join("") || `<tr><td colspan="7" class="muted">未发现密钥</td></tr>`}
            </tbody>
          </table></div>
          <div class="note-box">${escapeHtml(
            platSum.note || platform.error || `账单月 ${(platform.billing_cycle || "").toString()}`
          )}</div>
        </div>
        <div class="dash-card full">
          <h3>阿里云 BSS · 百炼 / 短信 / ECS（${escapeHtml(
            (platform.billing_cycle || "").toString()
          )}）</h3>
          <div class="table-wrap"><table>
            <thead><tr><th>产品</th><th>明细</th><th>用量</th><th>税前 CNY</th><th>实例/模型</th></tr></thead>
            <tbody>
              ${["sfm", "dysms", "dysms_system", "ecs"]
                .flatMap((code) => {
                  const prod = (aliyun.products || {})[code] || {};
                  return (prod.lines || []).map(
                    (line) => `<tr>
                    <td>${escapeHtml(prod.label || code)}</td>
                    <td>${escapeHtml(line.detail || line.product_name || "")}</td>
                    <td>${escapeHtml(
                      [line.usage, line.usage_unit].filter(Boolean).join(" ") || "—"
                    )}</td>
                    <td>${money(line.pretax_cny)}</td>
                    <td>${escapeHtml(line.instance_id || "—")}</td>
                  </tr>`
                  );
                })
                .join("") ||
              `<tr><td colspan="5" class="muted">本月暂无百炼/短信/ECS 明细，或 AccessKey 无 BSS 权限。</td></tr>`}
            </tbody>
          </table></div>
          ${
            sfm.pretax_cny
              ? `<div class="note-box">百炼合计税前 ${money(sfm.pretax_cny)} · ${num(
                  sfm.count
                )} 条计费项</div>`
              : ""
          }
        </div>
        <div class="dash-card">
          <h3>腾讯云费用中心</h3>
          ${
            tencent.ok
              ? `<div class="table-wrap"><table>
            <thead><tr><th>产品</th><th>实付 CNY</th><th>现金</th><th>代金券</th></tr></thead>
            <tbody>
              ${(tencent.items || [])
                .map(
                  (it) => `<tr>
                  <td>${escapeHtml(it.product)}</td>
                  <td>${money(it.real_total_cost)}</td>
                  <td>${money(it.cash_pay)}</td>
                  <td>${money(it.voucher)}</td>
                </tr>`
                )
                .join("") || `<tr><td colspan="4" class="muted">本月无明细</td></tr>`}
            </tbody>
          </table></div>
          <div class="note-box">合计 ${money(tencent.total_cny || 0)} · 密钥 ${escapeHtml(
            tencent.key_fingerprint || ""
          )}</div>`
              : `<div class="note-box">${escapeHtml(
                  tencent.error || "未拉取"
                )}${tencent.note ? " · " + escapeHtml(tencent.note) : ""}</div>`
          }
        </div>
        <div class="dash-card">
          <h3>DeepSeek / Deepgram / LiveKit</h3>
          <div class="note-box"><strong>DeepSeek</strong>：${
            deepseek.configured ? "已配置 " + escapeHtml(deepseek.key_label || "") : "未配置"
          } · ${escapeHtml(deepseek.model || "")}<br/>${escapeHtml(
            deepseek.note || deepseek.error || ""
          )}</div>
          <div class="note-box"><strong>Deepgram</strong>：${
            deepgram.ok
              ? `密钥 ${escapeHtml(deepgram.key_label || "")} · 项目 ${num(
                  (deepgram.projects || []).length
                )}`
              : escapeHtml(deepgram.error || "未配置")
          }${
            (deepgram.projects || [])
              .map((p) => `<br/>· ${escapeHtml(p.name || p.project_id || "")}`)
              .join("") || ""
          }</div>
          <div class="note-box"><strong>LiveKit</strong>：${escapeHtml(
            (platform.livekit &&
              (platform.livekit.note || platform.livekit.error)) ||
              ""
          )} · project ${escapeHtml(
            (platform.livekit && platform.livekit.project_hint) || ""
          )}${
            platform.livekit && platform.livekit.manual_cost_cny != null
              ? `<br/>本月手工记账 ${money(platform.livekit.manual_cost_cny)}（LIVEKIT_MANUAL_COST_CNY）`
              : `<br/><span class="muted">无 Scale Analytics；可在 API .env 设 LIVEKIT_MANUAL_COST_CNY</span>`
          }</div>
        </div>
        <div class="dash-card full">
          <h3>本机 RTX 5060 Ti · 按 App 模块 Token</h3>
          <div class="kpi-row">
            <div class="stat"><span class="muted">GPU 监控日</span><strong>${escapeHtml(
              gpu.day || "—"
            )}</strong></div>
            <div class="stat"><span class="muted">请求数</span><strong>${
              gpu.ok ? num(gpu.requests) : "—"
            }</strong></div>
            <div class="stat"><span class="muted">今日 Token</span><strong>${
              gpu.ok ? num(gpu.total_tokens) : "—"
            }</strong></div>
            <div class="stat"><span class="muted">Ledger GPU Token</span><strong>${num(
              gpuLedger.tokens || 0
            )}</strong></div>
          </div>
          ${
            gpu.error
              ? `<div class="note-box">${escapeHtml(gpu.error)}</div>`
              : ""
          }
          <div class="table-wrap"><table>
            <thead><tr><th>来源</th><th>App 模块</th><th>请求/事件</th><th>Tokens</th><th>说明</th></tr></thead>
            <tbody>
              ${(gpu.by_module || [])
                .map(
                  (m) => `<tr>
                  <td>GPU monitor</td>
                  <td>${escapeHtml(m.label_zh || moduleLabel(m.module))}</td>
                  <td>${num(m.requests)}</td>
                  <td>${num(m.tokens)}</td>
                  <td><code>${escapeHtml(m.module || "")}</code></td>
                </tr>`
                )
                .join("")}
              ${(gpuLedger.by_module || [])
                .map(
                  (m) => `<tr>
                  <td>ApiUsageEvent</td>
                  <td>${escapeHtml(moduleLabel(m.module))}</td>
                  <td>${num(m.events)}</td>
                  <td>${num(m.tokens)}</td>
                  <td>成本 ${money(m.cost_cny)}</td>
                </tr>`
                )
                .join("")}
              ${
                !(gpu.by_module || []).length && !(gpuLedger.by_module || []).length
                  ? `<tr><td colspan="5" class="muted">暂无 5060Ti 模块用量。App 调用本地 Ollama 时会带 X-Acquire-Module。</td></tr>`
                  : ""
              }
            </tbody>
          </table></div>
          <div class="note-box">${escapeHtml(
            gpu.note || gpuLedger.note || ""
          )}</div>
        </div>
        <div class="dash-card">
          <h3>损益（30 日）</h3>
          <div class="bars">
            <div class="bar-row"><span>收入</span><div class="bar-track"><div class="bar-fill" style="width:100%"></div></div><strong>${money(pnl.revenue_cny)}</strong></div>
            <div class="bar-row"><span>平台成本</span><div class="bar-track"><div class="bar-fill" style="width:${Math.min(
              100,
              pnl.revenue_cny > 0
                ? (pnl.api_cost_cny_platform / pnl.revenue_cny) * 100
                : 40
            )}%"></div></div><strong>${money(pnl.api_cost_cny_platform)}</strong></div>
            <div class="bar-row"><span>毛利</span><div class="bar-track"><div class="bar-fill" style="width:${
              pnl.gross_cny >= 0 ? 80 : 20
            }%"></div></div><strong>${money(pnl.gross_cny)}</strong></div>
          </div>
          <div class="note-box">${escapeHtml(pnl.note || "")}</div>
        </div>
        <div class="dash-card">
          <h3>按能力消耗</h3>
          ${barList(
            (summary.by_kind || []).map((k) => ({
              label: k.kind,
              count: Math.round(k.cost_cny * 100) / 100,
            })),
            "label",
            "count"
          )}
        </div>
        <div class="dash-card">
          <h3>按 App 模块消耗</h3>
          ${barList(
            (summary.by_module || []).map((m) => ({
              label: moduleLabel(m.module),
              count: Math.round((m.tokens || 0) * 100) / 100,
            })),
            "label",
            "count"
          )}
        </div>
        <div class="dash-card full">
          <h3>API Key 消耗明细（指纹，无明文）</h3>
          <div class="table-wrap"><table>
            <thead><tr><th>Key</th><th>归属</th><th>Provider</th><th>事件</th><th>Tokens</th><th>成本 CNY</th></tr></thead>
            <tbody>
              ${(summary.by_key || [])
                .map(
                  (k) => `<tr>
                  <td>${escapeHtml(k.key_label || k.key_fingerprint)}</td>
                  <td>${escapeHtml(k.key_owner)}</td>
                  <td>${escapeHtml(k.provider)}</td>
                  <td>${num(k.events)}</td>
                  <td>${num(k.tokens)}</td>
                  <td>${money(k.cost_cny)}</td>
                </tr>`
                )
                .join("") || `<tr><td colspan="6" class="muted">暂无用量。写作批改 / TTS / App 同步后会累计。</td></tr>`}
            </tbody>
          </table></div>
        </div>
        <div class="dash-card full">
          <h3>用户消耗 Top</h3>
          <div class="table-wrap"><table>
            <thead><tr><th>User ID</th><th>事件</th><th>Tokens</th><th>成本 CNY</th></tr></thead>
            <tbody>
              ${(summary.by_user || [])
                .map(
                  (u) =>
                    `<tr><td>${u.user_id}</td><td>${num(u.events)}</td><td>${num(
                      u.tokens
                    )}</td><td>${money(u.cost_cny)}</td></tr>`
                )
                .join("") || `<tr><td colspan="4" class="muted">暂无</td></tr>`}
            </tbody>
          </table></div>
          <div class="note-box">${escapeHtml(summary.note || "")}</div>
        </div>
      </div>`;
  }

  async function loadResources() {
    const data = await api("/analytics/resources");
    const el = $("panel-resources");
    el.innerHTML = `
      <div class="kpi-row">
        <div class="stat"><span class="muted">B 站共享字幕</span><strong>${num(
          data.shared_bilibili?.count
        )}</strong></div>
        <div class="stat"><span class="muted">OCR 书库</span><strong>${num(
          data.shared_ocr?.count
        )}</strong></div>
        <div class="stat"><span class="muted">社区资料包</span><strong>${num(
          data.community_packs
        )}</strong></div>
        <div class="stat"><span class="muted">官方题包</span><strong>${num(
          (data.official_exam_packs || []).length
        )}</strong></div>
      </div>
      <div class="dash-grid">
        <div class="dash-card">
          <h3>共享字幕命中</h3>
          <div class="note-box">英文命中 ${num(data.shared_bilibili?.en_hits)} · 中文命中 ${num(
      data.shared_bilibili?.zh_hits
    )} · 句数 ${num(data.shared_bilibili?.cues)}</div>
          <div class="table-wrap"><table>
            <thead><tr><th>标题</th><th>分P</th><th>中文预览</th><th>英文</th><th>中文</th></tr></thead>
            <tbody>
              ${(data.shared_bilibili?.top || [])
                .map(
                  (t) =>
                    `<tr><td title="${escapeHtml(t.bvid || "")}">${escapeHtml(
                      (t.title || t.bvid || "").slice(0, 28)
                    )}</td><td>${t.page}</td><td class="muted">${escapeHtml(
                      (t.preview_zh || "").slice(0, 36)
                    )}</td><td>${num(t.en_hits)}</td><td>${num(
                      t.zh_hits
                    )}</td></tr>`
                )
                .join("") || `<tr><td colspan="5" class="muted">暂无</td></tr>`}
            </tbody>
          </table></div>
        </div>
        <div class="dash-card">
          <h3>OCR 书库热度</h3>
          <div class="note-box">总命中 ${num(data.shared_ocr?.hits)} · 词量 ${num(
      data.shared_ocr?.words
    )}</div>
          ${barList(
            (data.shared_ocr?.top || []).map((t) => ({
              label: (t.title || "未命名").slice(0, 18),
              count: t.hits,
            })),
            "label",
            "count"
          )}
        </div>
        <div class="dash-card">
          <h3>社区真题资产</h3>
          ${barList(data.exam_assets_by_kind || [], "kind", "count")}
        </div>
        <div class="dash-card">
          <h3>官方 ExamPack</h3>
          <div class="table-wrap"><table>
            <thead><tr><th>包</th><th>CEFR</th><th>技能题量</th></tr></thead>
            <tbody>
              ${(data.official_exam_packs || [])
                .map((p) => {
                  const counts = p.counts || {};
                  const sum = Object.values(counts).reduce((a, b) => a + Number(b || 0), 0);
                  return `<tr><td>${escapeHtml(p.title || p.family_id)}</td><td>${escapeHtml(
                    p.cefr || ""
                  )}</td><td>${num(sum)}</td></tr>`;
                })
                .join("")}
            </tbody>
          </table></div>
        </div>
      </div>`;
  }

  async function loadCommunityPosts() {
    const s = communityState;
    const data = await api(`/community/posts?q=${encodeURIComponent(s.q)}&status=${s.status}&limit=${s.limit}&offset=${s.offset}`);
    s.total = data.total || 0;
    $("communityPostList").innerHTML = (data.items || []).map((p) => `
      <section class="section" data-post-id="${p.id}">
        <div class="muted">#${p.id} · ${escapeHtml(p.author_name)} · 用户 ${p.user_id} · ${escapeHtml(p.kind)} · ${escapeHtml(p.created_at || "")}</div>
        <form class="communityEditForm" data-post-id="${p.id}">
          <label>标题<input class="full" name="title" maxlength="200" value="${escapeAttr(p.title)}" required /></label>
          <label>正文<textarea class="full" name="body" rows="3" maxlength="4000">${escapeHtml(p.body)}</textarea></label>
          <label>链接<input class="full" name="link_url" value="${escapeAttr(p.link_url)}" /></label>
          <label>状态<select name="status"><option value="visible" ${p.status === "visible" ? "selected" : ""}>公开</option><option value="hidden" ${p.status === "hidden" ? "selected" : ""}>隐藏</option></select></label>
          <button class="btn primary" type="submit">保存修改</button>
        </form>
      </section>`).join("") || '<div class="empty">暂无帖子</div>';
    $("communityPageInfo").textContent = `${Math.floor(s.offset / s.limit) + 1} / ${Math.max(1, Math.ceil(s.total / s.limit))} · 共 ${s.total}`;
    $("communityPrev").disabled = s.offset <= 0;
    $("communityNext").disabled = s.offset + s.limit >= s.total;
    document.querySelectorAll(".communityEditForm").forEach((form) => form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const fd = new FormData(form);
      if (!confirm(`确认修改帖子 #${form.dataset.postId}？`)) return;
      try {
        await api(`/community/posts/${form.dataset.postId}`, { method: "PATCH", body: JSON.stringify(Object.fromEntries(fd)) });
        await loadCommunityPosts();
      } catch (e) { alert(e.message); }
    }));
  }

  // ---- users tab (existing) ----
  async function loadStats() {
    const s = await api("/stats");
    $("statsRow").innerHTML = [
      ["用户数", s.users],
      ["有效权益", s.active_entitlements],
      ["已支付订单", s.orders_paid],
      ["钱包积分合计", s.wallet_credits_sum],
      ["分享积分合计", s.points_sum],
    ]
      .map(
        ([label, value]) =>
          `<div class="stat"><span class="muted">${label}</span><strong>${value ?? 0}</strong></div>`
      )
      .join("");
  }

  async function loadSkus() {
    try {
      state.skus = (await api("/skus")).items || [];
    } catch {
      state.skus = [];
    }
  }

  async function loadUsers() {
    const data = await api(
      `/users?q=${encodeURIComponent(state.q)}&limit=${state.limit}&offset=${state.offset}`
    );
    state.total = data.total || 0;
    const list = $("userList");
    if (!data.items.length) {
      list.innerHTML = `<div class="empty" style="min-height:120px">没有匹配用户</div>`;
    } else {
      list.innerHTML = data.items
        .map((u) => {
          const active = u.id === state.selectedId ? "active" : "";
          const name = u.display_name || u.email || `用户 ${u.id}`;
          const assetBits = [
            `资产 ${u.asset_count ?? 0}`,
            `导入 ${u.link_courses ?? 0}`,
            `考试 ${u.exam_assets ?? 0}`,
            `OCR ${u.ocr_books ?? 0}`,
            `字幕 ${u.shared_subtitles ?? 0}`,
          ].join(" · ");
          return `<button class="user-item ${active}" data-id="${u.id}" type="button">
            <div class="title">${escapeHtml(name)}</div>
            <div class="meta">#${u.id} · ${escapeHtml(u.email || "")}${
            u.phone ? " · " + escapeHtml(u.phone) : ""
          }</div>
            <div class="meta">钱包 ${u.wallet_credits ?? "—"} · 积分 ${u.points_balance ?? 0}</div>
            <div class="meta">${escapeHtml(assetBits)}</div>
            <div class="meta">服务器占用 ${formatBytes(u.storage_bytes)}</div>
          </button>`;
        })
        .join("");
      list.querySelectorAll(".user-item").forEach((btn) => {
        btn.addEventListener("click", () => {
          state.selectedId = Number(btn.dataset.id);
          list.querySelectorAll(".user-item").forEach((b) => {
            b.classList.toggle("active", Number(b.dataset.id) === state.selectedId);
          });
          loadDetail(state.selectedId);
        });
      });
    }
    const page = Math.floor(state.offset / state.limit) + 1;
    const pages = Math.max(1, Math.ceil(state.total / state.limit));
    $("pageInfo").textContent = `${page} / ${pages} · 共 ${state.total}`;
    $("prevPage").disabled = state.offset <= 0;
    $("nextPage").disabled = state.offset + state.limit >= state.total;
  }

  let detailSeq = 0;
  async function loadDetail(userId) {
    const seq = ++detailSeq;
    $("emptyDetail").classList.add("hidden");
    const view = $("detailView");
    view.classList.remove("hidden");
    view.innerHTML = `<p class="muted">加载中…</p>`;
    try {
      const data = await api(`/users/${userId}`);
      if (seq !== detailSeq || state.selectedId !== userId) return;
      view.innerHTML = renderDetail(data);
      wireDetail(data);
    } catch (e) {
      if (seq !== detailSeq || state.selectedId !== userId) return;
      view.innerHTML = `<p class="error">${escapeHtml(e.message)}</p>`;
    }
  }

  function renderAssetTables(data) {
    const assets = data.assets || {};
    const storage = data.storage || {};
    const br = storage.breakdown || {};
    const links = (assets.link_courses || [])
      .map(
        (r) => `<tr>
          <td>${r.id}</td>
          <td>${escapeHtml(r.source)}</td>
          <td>${escapeHtml(r.title || r.external_id || "")}</td>
          <td>${r.has_en_sub ? "EN" : "—"}/${r.has_zh_sub ? "ZH" : "—"}</td>
          <td>${formatBytes(r.media_bytes)}</td>
        </tr>`
      )
      .join("");
    const exams = (assets.exam_assets || [])
      .map(
        (r) => `<tr>
          <td>${r.id}</td>
          <td>${escapeHtml(r.kind)} / ${escapeHtml(r.family_id)}</td>
          <td>${escapeHtml(r.title)}</td>
          <td>${escapeHtml(r.status)}</td>
          <td>${formatBytes(r.size_bytes)}</td>
        </tr>`
      )
      .join("");
    const ocr = (assets.ocr_books || [])
      .map(
        (r) => `<tr>
          <td>${r.id}</td>
          <td>${escapeHtml(r.title || "")}</td>
          <td>${num(r.page_count)} 页 · ${num(r.word_count)} 词</td>
          <td>${num(r.hit_count)}</td>
          <td>${formatBytes(r.approx_bytes)}</td>
        </tr>`
      )
      .join("");
    const subs = (assets.shared_subtitles || [])
      .map(
        (r) => `<tr>
          <td>${r.id}</td>
          <td title="${escapeHtml(r.bvid || "")}">${escapeHtml(
            (r.title || `${r.bvid} P${r.page}` || "").slice(0, 32)
          )}</td>
          <td class="muted">${escapeHtml((r.preview_zh || "").slice(0, 40))}</td>
          <td>${num(r.cue_count)} 句</td>
          <td>${num(r.en_hits)} / ${num(r.zh_hits)}</td>
          <td>${formatBytes(r.approx_bytes)}</td>
        </tr>`
      )
      .join("");
    const netdisk = (assets.netdisk || [])
      .map(
        (r) => `<tr>
          <td>${r.id}</td>
          <td>${escapeHtml(r.provider)}</td>
          <td>${escapeHtml(r.mount_path || "")}</td>
          <td>${r.storage_id ?? "—"}</td>
        </tr>`
      )
      .join("");
    return `
      <section class="section">
        <h3>服务器容量占用</h3>
        <div class="chips">
          <span class="chip">合计 ${formatBytes(storage.storage_bytes)}</span>
          <span class="chip">考试文件 ${formatBytes(br.exam_bytes)}</span>
          <span class="chip">导入媒体缓存 ${formatBytes(br.import_media_bytes)}</span>
          <span class="chip">备份 JSON ${formatBytes(br.backup_bytes)}</span>
          <span class="chip">OCR 文本 ${formatBytes(br.ocr_db_bytes)}</span>
          <span class="chip">字幕文本 ${formatBytes(br.subtitle_db_bytes)}</span>
        </div>
        <p class="muted" style="margin-top:8px">媒体目录：${escapeHtml(
          storage.media_cache_dir || "—"
        )}</p>
      </section>
      <section class="section">
        <h3>导入课程 / 网盘课（${(assets.link_courses || []).length}）</h3>
        <div class="table-wrap"><table>
          <thead><tr><th>ID</th><th>来源</th><th>标题</th><th>字幕</th><th>缓存</th></tr></thead>
          <tbody>${links || `<tr><td colspan="5" class="muted">暂无</td></tr>`}</tbody>
        </table></div>
      </section>
      <section class="section">
        <h3>考试资料（${(assets.exam_assets || []).length}）</h3>
        <div class="table-wrap"><table>
          <thead><tr><th>ID</th><th>类型</th><th>标题</th><th>状态</th><th>大小</th></tr></thead>
          <tbody>${exams || `<tr><td colspan="5" class="muted">暂无</td></tr>`}</tbody>
        </table></div>
      </section>
      <section class="section">
        <h3>OCR 书贡献（${(assets.ocr_books || []).length}）</h3>
        <div class="table-wrap"><table>
          <thead><tr><th>ID</th><th>标题</th><th>页/词</th><th>命中</th><th>约占用</th></tr></thead>
          <tbody>${ocr || `<tr><td colspan="5" class="muted">暂无</td></tr>`}</tbody>
        </table></div>
      </section>
      <section class="section">
        <h3>共享字幕贡献（${(assets.shared_subtitles || []).length}）</h3>
        <div class="table-wrap"><table>
          <thead><tr><th>ID</th><th>标题</th><th>中文预览</th><th>句数</th><th>EN/ZH 命中</th><th>约占用</th></tr></thead>
          <tbody>${subs || `<tr><td colspan="6" class="muted">暂无</td></tr>`}</tbody>
        </table></div>
      </section>
      <section class="section">
        <h3>网盘绑定（${(assets.netdisk || []).length}）</h3>
        <div class="table-wrap"><table>
          <thead><tr><th>ID</th><th>厂商</th><th>挂载路径</th><th>Storage</th></tr></thead>
          <tbody>${netdisk || `<tr><td colspan="4" class="muted">暂无</td></tr>`}</tbody>
        </table></div>
      </section>`;
  }

  function renderDetail(data) {
    const u = data.user;
    const c = data.counts || {};
    const skuOptions = state.skus
      .map(
        (s) =>
          `<option value="${escapeHtml(s.sku_code)}" data-kind="${escapeHtml(
            s.kind
          )}" data-ref="${escapeHtml(s.ref_id || s.sku_code)}" data-qty="${
            s.grant_quantity ?? ""
          }" data-days="${s.duration_days ?? ""}">${escapeHtml(s.title)} (${escapeHtml(
            s.sku_code
          )})</option>`
      )
      .join("");
    const moduleOptions = MODULE_DEFS.map(
      (m) =>
        `<option value="${escapeHtml(m.code)}">${escapeHtml(m.title)} (${escapeHtml(
          m.code
        )})</option>`
    ).join("");
    const ents = (data.entitlements || [])
      .map((e) => {
        const revoke =
          e.status === "active"
            ? `<button class="btn danger" data-revoke="${e.id}" type="button">吊销</button>`
            : "";
        const refLabel =
          e.asset_kind === "module"
            ? `${moduleLabel(e.asset_ref)} <span class="muted">(${escapeHtml(
                e.asset_ref
              )})</span>`
            : escapeHtml(e.asset_ref);
        return `<tr>
          <td>${e.id}</td>
          <td>${escapeHtml(e.asset_kind)}<br/>${refLabel}</td>
          <td>${escapeHtml(e.status)}</td>
          <td>${e.quantity ?? "∞"}</td>
          <td>${escapeHtml(e.ends_at || "—")}</td>
          <td>${revoke}</td>
        </tr>`;
      })
      .join("");
    const walletRows = (data.wallet_ledger || [])
      .map(
        (r) => `<tr>
          <td>${r.id}</td><td>${r.delta}</td><td>${escapeHtml(r.reason)}</td>
          <td>${escapeHtml(r.created_at || "")}</td>
        </tr>`
      )
      .join("");
    const pointsRows = (data.points_ledger || [])
      .map(
        (r) => `<tr>
          <td>${r.id}</td><td>${r.delta}</td><td>${escapeHtml(r.reason)}</td>
          <td>${escapeHtml(r.ref || "")}</td>
        </tr>`
      )
      .join("");
    return `
      <div class="detail-head">
        <div>
          <h2>${escapeHtml(u.display_name || u.email)}</h2>
          <p class="muted">#${u.id} · ${escapeHtml(u.email || "")}</p>
          <div class="chips">
            <span class="chip">钱包 ${u.wallet_credits ?? 0}</span>
            <span class="chip">分享积分 ${u.points_balance ?? 0}</span>
            <span class="chip">资产合计 ${c.asset_count ?? 0}</span>
            <span class="chip">服务器占用 ${formatBytes(
              (data.storage && data.storage.storage_bytes) || u.storage_bytes || 0
            )}</span>
            <span class="chip">导入课 ${c.link_courses ?? 0}</span>
            <span class="chip">考试 ${c.exam_assets ?? 0}</span>
            <span class="chip">OCR ${c.ocr_books ?? 0}</span>
            <span class="chip">字幕 ${c.shared_subtitles ?? 0}</span>
            <span class="chip">网盘 ${c.netdisk_bindings ?? 0}</span>
            <span class="chip">生词 ${c.vocab_items ?? 0}</span>
            <span class="chip">有效权益 ${c.active_entitlements ?? 0}</span>
            <span class="chip">学习进度 ${c.lesson_progress ?? 0}</span>
          </div>
        </div>
        <form id="renameForm" class="inline-form" style="width:min(320px,100%)">
          <input class="full" name="display_name" value="${escapeAttr(
            u.display_name || ""
          )}" placeholder="显示名" />
          <input class="full" name="email" type="email" required value="${escapeAttr(u.email || "")}" placeholder="登录邮箱" />
          <input class="full" name="phone" value="${escapeAttr(u.phone || "")}" placeholder="绑定手机号（留空解绑）" />
          <button class="btn primary full" type="submit">保存资料</button>
        </form>
      </div>
      <section class="section">
        <h3>账号安全与会员等级</h3>
        <p class="muted">密码无法查看。重置后只显示一次新密码；修改邮箱会影响原邮箱登录。会员操作会覆盖当前 Pro 权益的有效期。</p>
        <div class="actions">
          <form id="passwordForm" class="inline-form" style="flex:1">
            <input name="new_password" type="password" minlength="12" autocomplete="new-password" placeholder="自定新密码（至少12位，留空则生成）" />
            <button class="btn danger full" type="submit">修改 / 重置密码</button>
          </form>
          <form id="membershipForm" class="inline-form" style="flex:1">
            <select name="level"><option value="free" ${u.membership_level === "free" ? "selected" : ""}>免费</option><option value="pro" ${u.membership_level === "pro" ? "selected" : ""}>Pro 会员</option></select>
            <input name="duration_days" type="number" min="1" max="3650" value="30" aria-label="Pro有效天数" />
            <button class="btn primary full" type="submit">修改会员等级</button>
          </form>
        </div>
      </section>
      ${renderAssetTables(data)}
      <section class="section">
        <h3>发放权益</h3>
        <form id="grantForm" class="grant-grid">
          <label class="full">快捷 SKU
            <select id="skuPick"><option value="">自定义填写</option>${skuOptions}</select>
          </label>
          <label class="full">学习模块（asset_kind=module）
            <select id="modulePick">
              <option value="">不套用模块标题</option>
              ${moduleOptions}
            </select>
          </label>
          <label>asset_kind<input name="asset_kind" required placeholder="membership" /></label>
          <label>asset_ref<input name="asset_ref" required placeholder="pro" /></label>
          <label>quantity<input name="quantity" type="number" placeholder="可空=不限" /></label>
          <label>duration_days<input name="duration_days" type="number" placeholder="可空" /></label>
          <button class="btn primary full" type="submit">发放 / 叠加</button>
        </form>
      </section>
      <section class="section">
        <h3>调整钱包 / 分享积分</h3>
        <div class="actions">
          <form id="walletForm" class="inline-form" style="flex:1">
            <input name="delta" type="number" required placeholder="钱包 delta" />
            <input name="reason" placeholder="admin_adjust" />
            <button class="btn primary full" type="submit">调整钱包</button>
          </form>
          <form id="pointsForm" class="inline-form" style="flex:1">
            <input name="delta" type="number" required placeholder="分享积分 delta" />
            <input name="reason" placeholder="admin_adjust" />
            <button class="btn primary full" type="submit">调整积分</button>
          </form>
        </div>
      </section>
      <section class="section">
        <h3>权益列表</h3>
        <div class="table-wrap"><table>
          <thead><tr><th>ID</th><th>资产</th><th>状态</th><th>数量</th><th>到期</th><th></th></tr></thead>
          <tbody>${ents || `<tr><td colspan="6" class="muted">暂无</td></tr>`}</tbody>
        </table></div>
      </section>
      <section class="section">
        <h3>钱包流水</h3>
        <div class="table-wrap"><table>
          <thead><tr><th>ID</th><th>变动</th><th>原因</th><th>时间</th></tr></thead>
          <tbody>${walletRows || `<tr><td colspan="4" class="muted">暂无</td></tr>`}</tbody>
        </table></div>
      </section>
      <section class="section">
        <h3>分享积分流水</h3>
        <div class="table-wrap"><table>
          <thead><tr><th>ID</th><th>变动</th><th>原因</th><th>备注</th></tr></thead>
          <tbody>${pointsRows || `<tr><td colspan="4" class="muted">暂无</td></tr>`}</tbody>
        </table></div>
      </section>`;
  }

  function wireDetail(data) {
    const userId = data.user.id;
    $("skuPick")?.addEventListener("change", () => {
      const opt = $("skuPick").selectedOptions[0];
      if (!opt || !opt.value) return;
      const form = $("grantForm");
      const rawKind = opt.dataset.kind || "";
      form.asset_kind.value = normalizeGrantKind(rawKind);
      form.asset_ref.value = opt.dataset.ref || opt.value;
      form.quantity.value = opt.dataset.qty || "";
      form.duration_days.value = opt.dataset.days || "";
      if (form.asset_kind.value === "module" && MODULE_TITLE[form.asset_ref.value]) {
        const mp = $("modulePick");
        if (mp) mp.value = form.asset_ref.value;
      }
    });
    $("modulePick")?.addEventListener("change", () => {
      const code = $("modulePick").value;
      if (!code) return;
      const form = $("grantForm");
      form.asset_kind.value = "module";
      form.asset_ref.value = code;
    });
    $("renameForm")?.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const fd = new FormData(ev.target);
      try {
        await api(`/users/${userId}`, {
          method: "PATCH",
          body: JSON.stringify({ display_name: fd.get("display_name"), email: fd.get("email"), phone: fd.get("phone") }),
        });
        await Promise.all([loadUsers(), loadDetail(userId), loadStats()]);
      } catch (e) {
        alert(e.message);
      }
    });
    $("passwordForm")?.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      if (!confirm(`确认重置用户 #${userId} 的登录密码？`)) return;
      const value = String(new FormData(ev.target).get("new_password") || "");
      try {
        const result = await api(`/users/${userId}/password/reset`, { method: "POST", body: JSON.stringify({ new_password: value || null }) });
        ev.target.reset();
        alert(result.temporary_password ? `新密码只显示这一次：${result.temporary_password}` : "密码已修改");
      } catch (e) { alert(e.message); }
    });
    $("membershipForm")?.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const fd = new FormData(ev.target);
      const level = String(fd.get("level"));
      if (!confirm(`确认将用户 #${userId} 的会员设为 ${level}？现有 Pro 有效期会被覆盖。`)) return;
      try {
        await api(`/users/${userId}/membership`, { method: "PUT", body: JSON.stringify({ level, duration_days: Number(fd.get("duration_days")) }) });
        await Promise.all([loadDetail(userId), loadStats()]);
      } catch (e) { alert(e.message); }
    });
    $("grantForm")?.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const fd = new FormData(ev.target);
      const quantityRaw = String(fd.get("quantity") || "").trim();
      const daysRaw = String(fd.get("duration_days") || "").trim();
      try {
        await api(`/users/${userId}/entitlements/grant`, {
          method: "POST",
          body: JSON.stringify({
            asset_kind: String(fd.get("asset_kind") || "").trim(),
            asset_ref: String(fd.get("asset_ref") || "").trim(),
            quantity: quantityRaw === "" ? null : Number(quantityRaw),
            duration_days: daysRaw === "" ? null : Number(daysRaw),
            source: "grant",
            meta: { via: "admin_web" },
          }),
        });
        await Promise.all([loadDetail(userId), loadStats()]);
      } catch (e) {
        alert(e.message);
      }
    });
    $("walletForm")?.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const fd = new FormData(ev.target);
      try {
        await api(`/users/${userId}/wallet/adjust`, {
          method: "POST",
          body: JSON.stringify({
            delta: Number(fd.get("delta")),
            reason: String(fd.get("reason") || "admin_adjust"),
          }),
        });
        await Promise.all([loadUsers(), loadDetail(userId), loadStats()]);
      } catch (e) {
        alert(e.message);
      }
    });
    $("pointsForm")?.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const fd = new FormData(ev.target);
      try {
        await api(`/users/${userId}/points/adjust`, {
          method: "POST",
          body: JSON.stringify({
            delta: Number(fd.get("delta")),
            reason: String(fd.get("reason") || "admin_adjust"),
          }),
        });
        await Promise.all([loadUsers(), loadDetail(userId), loadStats()]);
      } catch (e) {
        alert(e.message);
      }
    });
    document.querySelectorAll("[data-revoke]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        if (!confirm("确认吊销该权益？")) return;
        try {
          await api(`/users/${userId}/entitlements/${btn.dataset.revoke}/revoke`, {
            method: "POST",
            body: "{}",
          });
          await Promise.all([loadDetail(userId), loadStats()]);
        } catch (e) {
          alert(e.message);
        }
      });
    });
  }

  $("loginBtn").addEventListener("click", login);
  ["usernameInput", "passwordInput", "tokenInput"].forEach((id) => {
    $(id).addEventListener("keydown", (e) => {
      if (e.key === "Enter") login();
    });
  });
  $("loadTokenBtn").addEventListener("click", () => $("tokenFileInput").click());
  $("tokenFileInput").addEventListener("change", (e) => {
    const file = e.target.files && e.target.files[0];
    if (file) loadTokenFromFile(file);
    e.target.value = "";
  });
  $("saveTokenBtn").addEventListener("click", saveTokenToLocal);
  $("logoutBtn").addEventListener("click", logout);
  $("refreshBtn").addEventListener("click", () => bootstrap().catch((e) => alert(e.message)));
  $("searchForm").addEventListener("submit", (e) => {
    e.preventDefault();
    state.q = $("searchInput").value.trim();
    state.offset = 0;
    loadUsers().catch((err) => alert(err.message));
  });
  $("prevPage").addEventListener("click", () => {
    state.offset = Math.max(0, state.offset - state.limit);
    loadUsers().catch((err) => alert(err.message));
  });
  $("nextPage").addEventListener("click", () => {
    state.offset += state.limit;
    loadUsers().catch((err) => alert(err.message));
  });
  document.querySelectorAll(".tab").forEach((btn) => {
    btn.addEventListener("click", () => {
      setTab(btn.dataset.tab);
      if (btn.dataset.tab === "dashboard") loadDashboard().catch((e) => alert(e.message));
      if (btn.dataset.tab === "feedback") loadFeedback().catch((e) => alert(e.message));
      if (btn.dataset.tab === "infra") loadInfra().catch((e) => alert(e.message));
      if (btn.dataset.tab === "usage") loadUsage().catch((e) => alert(e.message));
      if (btn.dataset.tab === "resources") loadResources().catch((e) => alert(e.message));
      if (btn.dataset.tab === "fingerprint") loadFingerprint().catch((e) => alert(e.message));
      if (btn.dataset.tab === "community") loadCommunityPosts().catch((e) => alert(e.message));
    });
  });
  $("communitySearchForm").addEventListener("submit", (e) => {
    e.preventDefault();
    communityState.q = $("communitySearchInput").value.trim();
    communityState.status = $("communityStatus").value;
    communityState.offset = 0;
    loadCommunityPosts().catch((err) => alert(err.message));
  });
  $("communityPrev").addEventListener("click", () => {
    communityState.offset = Math.max(0, communityState.offset - communityState.limit);
    loadCommunityPosts().catch((err) => alert(err.message));
  });
  $("communityNext").addEventListener("click", () => {
    communityState.offset += communityState.limit;
    loadCommunityPosts().catch((err) => alert(err.message));
  });
  $("feedbackSearchForm").addEventListener("submit", (e) => {
    e.preventDefault();
    feedbackState.status = $("feedbackStatusFilter").value;
    feedbackState.q = $("feedbackSearchInput").value.trim();
    feedbackState.offset = 0;
    loadFeedback().catch((err) => alert(err.message));
  });
  $("feedbackPrev").addEventListener("click", () => {
    feedbackState.offset = Math.max(0, feedbackState.offset - feedbackState.limit);
    loadFeedback().catch((err) => alert(err.message));
  });
  $("feedbackNext").addEventListener("click", () => {
    feedbackState.offset += feedbackState.limit;
    loadFeedback().catch((err) => alert(err.message));
  });

  // Always show login gate (username + password + token). Prefill account/token only.
  showLogin();
  $("usernameInput").value = state.username || "admin";
  if (state.token) $("tokenInput").value = state.token;
})();
