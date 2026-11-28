(() => {
  const TOKEN_KEY = "ae_admin_token";
  const USER_KEY = "ae_admin_username";
  const LAST_USER_ID_KEY = "ae_admin_last_seen_user_id";
  const TOKEN_FILENAME = "acquireenglish-admin-login.token";
  const NEW_USER_POLL_MS = 30000;
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
    pendingNewUsers: [],
  };
  let userWatchTimer = null;

  const $ = (id) => document.getElementById(id);
  const loginView = $("loginView");
  const appView = $("appView");
  const loginError = $("loginError");
  const titles = {
    dashboard: "可视化看板",
    feedback: "软件优化建议",
    uploads: "上传资料监控",
    "exam-assets": "考试资料审核",
    commerce: "订单 / 会员",
    infra: "ECS / 云盘监控",
    usage: "用量 / 平台账单",
    resources: "公共资源库",
    fingerprint: "指纹缓存",
    users: "用户与资产",
    community: "社区帖子",
  };
  const feedbackState = {
    offset: 0,
    limit: 40,
    total: 0,
    status: "open",
    category: "",
    q: "",
  };
  const examAssetsState = { status: "pending" };
  const uploadsState = {
    offset: 0,
    limit: 40,
    total: 0,
    status: "",
    file_type: "",
    q: "",
    created_from: "",
    created_to: "",
    stuck_only: false,
    auto_refresh: false,
    selectedId: null,
  };
  let uploadsRefreshTimer = null;
  const commerceState = { status: "", kind: "", offset: 0, limit: 40 };
  const communityState = { offset: 0, limit: 40, total: 0, q: "", status: "" };
  const usageState = { days: 30, day: "" };

  function chinaTodayYmd() {
    // Admin ops day follows Asia/Shanghai, independent of browser TZ.
    return new Intl.DateTimeFormat("en-CA", {
      timeZone: "Asia/Shanghai",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(new Date());
  }

  function usageQuery() {
    if (usageState.day) {
      return `day=${encodeURIComponent(usageState.day)}`;
    }
    return `days=${encodeURIComponent(String(usageState.days || 30))}`;
  }

  function usageWindowLabel() {
    if (usageState.day) {
      return `单日 ${usageState.day}（上海时区）`;
    }
    return `近 ${usageState.days || 30} 天（上海时区）`;
  }

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
  function findActiveProEntitlement(data) {
    const rows = data?.entitlements || [];
    return (
      rows.find(
        (e) =>
          e.asset_kind === "membership" &&
          e.asset_ref === "pro" &&
          e.status === "active"
      ) || null
    );
  }

  function proEndsLabel(data) {
    if ((data?.user?.membership_level || "free") !== "pro") {
      return "非 Pro";
    }
    const ent = findActiveProEntitlement(data);
    if (!ent) return "Pro（未找到权益行）";
    if (!ent.ends_at) return "永久";
    try {
      return new Date(ent.ends_at).toLocaleString("zh-CN");
    } catch {
      return String(ent.ends_at);
    }
  }

  function proEndsLocalValue(data) {
    const ent = findActiveProEntitlement(data);
    if (!ent?.ends_at) return "";
    const d = new Date(ent.ends_at);
    if (Number.isNaN(d.getTime())) return "";
    const pad = (n) => String(n).padStart(2, "0");
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(
      d.getHours()
    )}:${pad(d.getMinutes())}`;
  }

  function localInputToIso(localValue) {
    const raw = String(localValue || "").trim();
    if (!raw) return null;
    const d = new Date(raw);
    if (Number.isNaN(d.getTime())) {
      throw new Error("到期时间格式无效");
    }
    return d.toISOString();
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

  function pushToast(title, body, onOpen) {
    const host = $("notifyHost");
    if (!host) return;
    const el = document.createElement("div");
    el.className = "notify-toast";
    el.innerHTML = `<strong>${escapeHtml(title)}</strong><p class="muted">${escapeHtml(body)}</p>`;
    if (typeof onOpen === "function") {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.textContent = "查看";
      btn.addEventListener("click", () => {
        el.remove();
        onOpen();
      });
      el.appendChild(btn);
    }
    host.appendChild(el);
    window.setTimeout(() => {
      if (el.isConnected) el.remove();
    }, 12000);
  }

  function hideNewUserModal() {
    const modal = $("newUserModal");
    if (modal) modal.classList.add("hidden");
    state.pendingNewUsers = [];
  }

  function openPendingNewUsers() {
    const users = state.pendingNewUsers.slice();
    hideNewUserModal();
    if (!users.length) return;
    const newest = users[users.length - 1];
    setTab("users");
    state.q = "";
    state.offset = 0;
    if ($("searchInput")) $("searchInput").value = "";
    state.selectedId = newest.id;
    loadUsers()
      .then(() => loadDetail(newest.id))
      .catch((err) => alert(err.message));
  }

  function showNewUserPopup(users) {
    if (!users || !users.length) return;
    state.pendingNewUsers = users.slice();
    const modal = $("newUserModal");
    const title = $("newUserModalTitle");
    const body = $("newUserModalBody");
    if (!modal || !title || !body) {
      const first = users[0];
      alert(
        users.length === 1
          ? `新用户注册：${first.display_name || first.email || `#${first.id}`}`
          : `有 ${users.length} 位新用户注册`
      );
      return;
    }
    title.textContent =
      users.length === 1 ? "有新用户注册" : `有 ${users.length} 位新用户注册`;
    body.innerHTML = users
      .map((u) => {
        const name = u.display_name || u.email || `用户 #${u.id}`;
        const serial = u.member_no ? ` · ${u.member_no}` : "";
        return `<div class="modal-user">
          <strong>${escapeHtml(name)}${escapeHtml(serial)}</strong>
          <div class="muted">ID ${u.id} · ${escapeHtml(u.email || "—")}</div>
          <div class="muted">注册时间 ${escapeHtml(formatDateTime(u.created_at))}</div>
        </div>`;
      })
      .join("");
    modal.classList.remove("hidden");
    const newest = users[users.length - 1];
    pushToast(
      users.length === 1 ? "新用户注册" : `${users.length} 位新用户`,
      `${newest.display_name || newest.email || `#${newest.id}`}${
        newest.member_no ? ` · ${newest.member_no}` : ""
      }`,
      openPendingNewUsers
    );
    if (window.Notification && Notification.permission === "granted") {
      try {
        new Notification("AcquireEnglish 运营后台", {
          body:
            users.length === 1
              ? `新用户：${newest.display_name || newest.email || `#${newest.id}`}`
              : `有 ${users.length} 位新用户注册`,
        });
      } catch {
        /* ignore */
      }
    }
  }

  async function pollNewRegistrations({ seedOnly = false } = {}) {
    if (!state.token) return;
    try {
      const data = await api("/users?limit=12&offset=0");
      const items = Array.isArray(data.items) ? data.items : [];
      if (!items.length) return;
      const newestId = Math.max(...items.map((u) => Number(u.id) || 0));
      const raw = localStorage.getItem(LAST_USER_ID_KEY);
      const lastSeen = raw ? Number(raw) : 0;
      if (seedOnly || !lastSeen || Number.isNaN(lastSeen)) {
        localStorage.setItem(LAST_USER_ID_KEY, String(newestId));
        return;
      }
      const fresh = items
        .filter((u) => Number(u.id) > lastSeen)
        .sort((a, b) => Number(a.id) - Number(b.id));
      if (!fresh.length) return;
      localStorage.setItem(LAST_USER_ID_KEY, String(newestId));
      showNewUserPopup(fresh);
      if (state.tab === "users") {
        loadUsers().catch(() => {});
      }
    } catch (err) {
      console.warn("pollNewRegistrations", err);
    }
  }

  function startUserRegistrationWatch() {
    stopUserRegistrationWatch();
    pollNewRegistrations({ seedOnly: true }).finally(() => {
      userWatchTimer = window.setInterval(() => {
        pollNewRegistrations({ seedOnly: false });
      }, NEW_USER_POLL_MS);
    });
    if (window.Notification && Notification.permission === "default") {
      Notification.requestPermission().catch(() => {});
    }
  }

  function stopUserRegistrationWatch() {
    if (userWatchTimer) {
      window.clearInterval(userWatchTimer);
      userWatchTimer = null;
    }
  }

  function setTab(tab) {
    state.tab = tab;
    $("pageTitle").textContent = titles[tab] || tab;
    document.querySelectorAll(".tab").forEach((btn) => {
      btn.classList.toggle("active", btn.dataset.tab === tab);
    });
    [
      "dashboard",
      "feedback",
      "uploads",
      "exam-assets",
      "commerce",
      "infra",
      "usage",
      "resources",
      "fingerprint",
      "users",
      "community",
    ].forEach((id) => {
      const panel = $(`panel-${id}`);
      if (panel) panel.classList.toggle("hidden", id !== tab);
    });
    if (tab !== "uploads") stopUploadsAutoRefresh();
  }

  const UPLOAD_STATUS_LABEL = {
    pending: "待处理",
    pending_confirm: "待确认",
    fingerprint_match: "指纹命中",
    queue_gpu: "排队解构",
    processing: "处理中",
    success: "已完成",
    failed: "失败",
  };

  function uploadStatusChip(status, isStuck) {
    const label = UPLOAD_STATUS_LABEL[status] || status || "—";
    let cls = "chip muted-chip";
    if (status === "failed") cls = "chip bad";
    else if (status === "success" || status === "fingerprint_match") cls = "chip ok";
    else if (status === "processing" || status === "queue_gpu") cls = "chip warn";
    const stuck = isStuck ? " · 卡住" : "";
    return `<span class="${cls}">${escapeHtml(label)}${stuck}</span>`;
  }

  function formatAge(seconds) {
    const s = Number(seconds || 0);
    if (!Number.isFinite(s) || s < 0) return "—";
    if (s < 60) return `${s}s`;
    if (s < 3600) return `${Math.floor(s / 60)}m`;
    if (s < 86400) return `${Math.floor(s / 3600)}h`;
    return `${Math.floor(s / 86400)}d`;
  }

  function stopUploadsAutoRefresh() {
    if (uploadsRefreshTimer) {
      clearInterval(uploadsRefreshTimer);
      uploadsRefreshTimer = null;
    }
  }

  function syncUploadsAutoRefresh() {
    stopUploadsAutoRefresh();
    if (!uploadsState.auto_refresh || state.tab !== "uploads") return;
    uploadsRefreshTimer = setInterval(() => {
      loadUploads().catch((e) => console.warn(e));
    }, 30000);
  }

  async function loadUploads() {
    const params = new URLSearchParams({
      limit: String(uploadsState.limit),
      offset: String(uploadsState.offset),
    });
    if (uploadsState.status) params.set("status", uploadsState.status);
    if (uploadsState.file_type) params.set("file_type", uploadsState.file_type);
    if (uploadsState.q) params.set("q", uploadsState.q);
    if (uploadsState.created_from) params.set("created_from", uploadsState.created_from);
    if (uploadsState.created_to) params.set("created_to", uploadsState.created_to);
    if (uploadsState.stuck_only) params.set("stuck_only", "true");

    const data = await api(`/fingerprint-cache/upload-tasks?${params.toString()}`);
    uploadsState.total = Number(data.total || 0);
    const counts = data.status_counts || {};
    const badge = $("uploadsBadge");
    if (badge) {
      badge.textContent = `· ${uploadsState.total} 条 · 卡住 ${num(data.stuck_count)}`;
    }
    const kpis = $("uploadsKpis");
    if (kpis) {
      kpis.innerHTML = `
        <div class="stat"><span class="muted">进行中</span><strong>${num(
          data.in_flight_count
        )}</strong></div>
        <div class="stat"><span class="muted">已完成/命中</span><strong>${num(
          data.ready_count
        )}</strong></div>
        <div class="stat"><span class="muted">失败</span><strong>${num(
          data.failed_count
        )}</strong></div>
        <div class="stat"><span class="muted">卡住(≥${escapeHtml(
          String(data.stuck_after_minutes || 30)
        )}m)</span><strong>${num(data.stuck_count)}</strong></div>
        <div class="stat"><span class="muted">queue_gpu</span><strong>${num(
          counts.queue_gpu
        )}</strong></div>
        <div class="stat"><span class="muted">processing</span><strong>${num(
          counts.processing
        )}</strong></div>`;
    }

    const items = Array.isArray(data.items) ? data.items : [];
    const table = $("uploadsTable");
    if (!items.length) {
      table.innerHTML = `<p class="empty">当前筛选下没有上传任务</p>`;
    } else {
      table.innerHTML = `<table>
        <thead><tr>
          <th>状态</th><th>文件</th><th>类型</th><th>用户</th>
          <th>创建</th><th>更新</th><th>闲置</th><th>失败原因</th>
        </tr></thead>
        <tbody>${items
          .map((item) => {
            const who =
              item.user_display_name ||
              item.user_email ||
              (item.user_id != null ? `用户#${item.user_id}` : "—");
            const created = item.create_at
              ? new Date(item.create_at).toLocaleString("zh-CN")
              : "—";
            const updated = item.update_at
              ? new Date(item.update_at).toLocaleString("zh-CN")
              : "—";
            const reason = item.fail_reason
              ? escapeHtml(String(item.fail_reason).slice(0, 80))
              : "—";
            return `<tr class="uploads-row${item.is_stuck ? " is-stuck" : ""}" data-id="${escapeAttr(
              item.id
            )}">
              <td>${uploadStatusChip(item.status, item.is_stuck)}</td>
              <td><strong>${escapeHtml(item.file_name || item.id)}</strong>
                <div class="muted">${escapeHtml(String(item.id).slice(0, 8))}…</div></td>
              <td>${escapeHtml(item.file_type || "—")}</td>
              <td>${escapeHtml(who)}
                <div class="muted">#${escapeHtml(String(item.user_id ?? ""))}</div></td>
              <td>${escapeHtml(created)}</td>
              <td>${escapeHtml(updated)}</td>
              <td>${escapeHtml(formatAge(item.age_seconds))}</td>
              <td>${reason}</td>
            </tr>`;
          })
          .join("")}</tbody></table>`;
      table.querySelectorAll(".uploads-row").forEach((row) => {
        row.addEventListener("click", () => {
          uploadsState.selectedId = row.dataset.id;
          loadUploadDetail(row.dataset.id).catch((e) => alert(e.message));
        });
      });
    }

    const pageInfo = $("uploadsPageInfo");
    if (pageInfo) {
      const start = uploadsState.total ? uploadsState.offset + 1 : 0;
      const end = Math.min(uploadsState.offset + uploadsState.limit, uploadsState.total);
      pageInfo.textContent = `${start}-${end} / ${uploadsState.total}`;
    }
    if (uploadsState.selectedId) {
      loadUploadDetail(uploadsState.selectedId).catch(() => {});
    } else {
      const detail = $("uploadsDetail");
      if (detail) {
        detail.classList.add("hidden");
        detail.innerHTML = "";
      }
    }
    syncUploadsAutoRefresh();
  }

  async function loadUploadDetail(taskId) {
    const detail = $("uploadsDetail");
    if (!detail) return;
    detail.classList.remove("hidden");
    detail.innerHTML = `<p class="muted">加载任务详情…</p>`;
    const item = await api(`/fingerprint-cache/upload-tasks/${encodeURIComponent(taskId)}`);
    const course = item.user_course || null;
    detail.innerHTML = `
      <h3>任务详情</h3>
      <div class="uploads-detail-grid">
        <div><span class="muted">任务 ID</span><strong>${escapeHtml(item.id)}</strong></div>
        <div><span class="muted">状态</span><strong>${uploadStatusChip(
          item.status,
          item.is_stuck
        )}</strong></div>
        <div><span class="muted">文件</span><strong>${escapeHtml(
          item.file_name || "—"
        )}</strong></div>
        <div><span class="muted">类型</span><strong>${escapeHtml(
          item.file_type || "—"
        )}</strong></div>
        <div><span class="muted">用户</span><strong>${escapeHtml(
          item.user_display_name || item.user_email || `用户#${item.user_id}`
        )}</strong></div>
        <div><span class="muted">指纹</span><strong>${escapeHtml(
          item.fingerprint_id || "—"
        )}</strong></div>
        <div><span class="muted">课程副本</span><strong>${escapeHtml(
          item.user_course_asset_id || "—"
        )}</strong></div>
        <div><span class="muted">raw_file_key</span><strong>${escapeHtml(
          item.raw_file_key || "—"
        )}</strong></div>
        ${
          course
            ? `<div><span class="muted">课程标题</span><strong>${escapeHtml(
                course.asset_title || "—"
              )}</strong></div>
               <div><span class="muted">公共缓存</span><strong>${escapeHtml(
                 course.asset_cache_id || "私人"
               )}</strong></div>`
            : ""
        }
      </div>
      ${
        item.fail_reason
          ? `<p class="fail-reason">${escapeHtml(item.fail_reason)}</p>`
          : ""
      }
      <div class="login-actions" style="margin-top:12px">
        <button type="button" class="btn ghost" id="uploadsOpenUserBtn" data-uid="${escapeAttr(
          String(item.user_id || "")
        )}">打开用户资产</button>
        <button type="button" class="btn ghost" id="uploadsCloseDetailBtn">关闭详情</button>
      </div>`;
    $("uploadsCloseDetailBtn")?.addEventListener("click", () => {
      uploadsState.selectedId = null;
      detail.classList.add("hidden");
      detail.innerHTML = "";
    });
    $("uploadsOpenUserBtn")?.addEventListener("click", () => {
      const uid = Number($("uploadsOpenUserBtn").dataset.uid || 0);
      if (!uid) return;
      setTab("users");
      state.selectedId = uid;
      state.q = String(uid);
      if ($("searchInput")) $("searchInput").value = String(uid);
      state.offset = 0;
      loadUsers()
        .then(() => loadDetail(uid))
        .catch((e) => alert(e.message));
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
    bug: "功能缺陷",
    ux: "界面体验",
    content: "内容与课程",
    performance: "卡顿/性能",
    billing: "会员/支付",
    feature: "软件优化/新功能",
    general: "其他",
  };

  async function loadFeedback() {
    const params = new URLSearchParams({
      limit: String(feedbackState.limit),
      offset: String(feedbackState.offset),
    });
    if (feedbackState.status) params.set("status", feedbackState.status);
    if (feedbackState.category) params.set("category", feedbackState.category);
    if (feedbackState.q) params.set("q", feedbackState.q);
    const data = await api(`/feedback?${params.toString()}`);
    feedbackState.total = data.total || 0;
    const badge = $("feedbackOpenBadge");
    if (badge) badge.textContent = `· 待处理 ${data.open_count || 0}`;
    const list = $("feedbackList");
    const items = data.items || [];
    if (!items.length) {
      list.innerHTML = `<p class="empty">暂无优化建议</p>`;
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
              <strong>${escapeHtml(item.title || "软件优化建议")}</strong>
              <span class="chip">${escapeHtml(item.status)}</span>
            </div>
            <p class="muted">${escapeHtml(FEEDBACK_CAT[item.category] || item.category)} · ${escapeHtml(who)} · ${escapeHtml(when)}</p>
            <p style="white-space:pre-wrap;margin:8px 0">${escapeHtml(item.body)}</p>
            ${item.contact ? `<p class="muted">联系：${escapeHtml(item.contact)}</p>` : ""}
            ${item.app_version ? `<p class="muted">版本：${escapeHtml(item.app_version)}</p>` : ""}
            <label class="field" style="margin-top:8px">
              <span>运营备注（仅后台）</span>
              <textarea class="fb-note" data-id="${item.id}" rows="2" placeholder="处理进度、跟进结论…">${escapeHtml(item.admin_note || "")}</textarea>
            </label>
            <div class="login-actions" style="margin-top:8px">
              <button type="button" class="btn ghost fb-save-note" data-id="${item.id}" data-status="${escapeAttr(item.status)}">保存备注</button>
              <button type="button" class="btn ghost fb-status" data-id="${item.id}" data-status="read">标为已读</button>
              <button type="button" class="btn ghost fb-status" data-id="${item.id}" data-status="done">标为完成</button>
              <button type="button" class="btn ghost fb-status" data-id="${item.id}" data-status="open">重开</button>
            </div>
          </article>`;
        })
        .join("");
      list.querySelectorAll(".fb-status").forEach((btn) => {
        btn.addEventListener("click", async () => {
          try {
            // Omit admin_note so existing notes are preserved.
            await api(`/feedback/${btn.dataset.id}`, {
              method: "PATCH",
              body: JSON.stringify({ status: btn.dataset.status }),
            });
            await loadFeedback();
          } catch (e) {
            alert(e.message);
          }
        });
      });
      list.querySelectorAll(".fb-save-note").forEach((btn) => {
        btn.addEventListener("click", async () => {
          const card = btn.closest("[data-fid]");
          const ta = card && card.querySelector(".fb-note");
          try {
            await api(`/feedback/${btn.dataset.id}`, {
              method: "PATCH",
              body: JSON.stringify({
                status: btn.dataset.status || "open",
                admin_note: ta ? ta.value : "",
              }),
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

  function formatBytes(n) {
    const v = Number(n || 0);
    if (v < 1024) return `${v} B`;
    if (v < 1024 * 1024) return `${(v / 1024).toFixed(1)} KB`;
    return `${(v / (1024 * 1024)).toFixed(1)} MB`;
  }

  async function loadExamAssets() {
    const params = new URLSearchParams({ limit: "80" });
    if (examAssetsState.status) params.set("status", examAssetsState.status);
    const rows = await api(`/exam-assets?${params.toString()}`);
    const items = Array.isArray(rows) ? rows : rows.items || [];
    const badge = $("examAssetsBadge");
    if (badge) {
      badge.textContent =
        examAssetsState.status === "pending"
          ? `· 待审 ${items.length}`
          : `· ${items.length} 条`;
    }
    const list = $("examAssetsList");
    if (!items.length) {
      list.innerHTML = `<p class="empty">当前筛选下没有资料</p>`;
      return;
    }
    list.innerHTML = items
      .map((item) => {
        const when = item.created_at
          ? new Date(item.created_at).toLocaleString("zh-CN")
          : "";
        const meta = item.meta || {};
        return `<article class="user-card" data-aid="${item.id}">
          <div class="user-card-top">
            <strong>${escapeHtml(item.title || `资料 #${item.id}`)}</strong>
            <span class="chip">${escapeHtml(item.status)}</span>
          </div>
          <p class="muted">${escapeHtml(item.family_id || "—")} · ${escapeHtml(
          item.kind || "—"
        )} · ${escapeHtml(item.uploader_name || `用户#${item.uploader_id}`)} · ${escapeHtml(
          when
        )}</p>
          <p class="muted">大小 ${formatBytes(item.size_bytes)} · 举报 ${num(
          item.report_count
        )} · 奖励预览 ${num(item.reward_preview_days || item.reward_days || 0)} 天</p>
          ${
            meta.note
              ? `<p class="muted">说明：${escapeHtml(meta.note)}</p>`
              : ""
          }
          ${
            item.download_url
              ? `<p><a href="${escapeAttr(item.download_url)}" target="_blank" rel="noopener">打开文件</a></p>`
              : ""
          }
          <div class="login-actions" style="margin-top:8px">
            ${
              item.status === "pending" || item.status === "rejected"
                ? `<button type="button" class="btn primary ea-approve" data-id="${item.id}">通过并奖励</button>`
                : ""
            }
            ${
              item.status === "pending" || item.status === "visible"
                ? `<button type="button" class="btn ghost ea-reject" data-id="${item.id}">拒绝</button>`
                : ""
            }
          </div>
        </article>`;
      })
      .join("");
    list.querySelectorAll(".ea-approve").forEach((btn) => {
      btn.addEventListener("click", async () => {
        if (!confirm(`通过资料 #${btn.dataset.id}？将按规则奖励上传者会员天数。`)) return;
        try {
          await api(`/exam-assets/${btn.dataset.id}/review`, {
            method: "POST",
            body: JSON.stringify({ approve: true }),
          });
          await loadExamAssets();
        } catch (e) {
          alert(e.message);
        }
      });
    });
    list.querySelectorAll(".ea-reject").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const note = prompt("拒绝原因（将写入审核记录）", "不符合规范或版权风险");
        if (note == null) return;
        try {
          await api(`/exam-assets/${btn.dataset.id}/review`, {
            method: "POST",
            body: JSON.stringify({ approve: false, note: note.trim() }),
          });
          await loadExamAssets();
        } catch (e) {
          alert(e.message);
        }
      });
    });
  }

  function renderUserRosterTable(rows, emptyText) {
    return `<div class="table-wrap"><table>
      <thead><tr><th>ID</th><th>昵称</th><th>邮箱</th><th>手机</th><th>微信</th><th>注册时间</th></tr></thead>
      <tbody>
        ${
          (rows || [])
            .map(
              (u) => `<tr class="commerce-user-row" data-id="${u.id}" tabindex="0">
            <td>${u.id}</td>
            <td>${escapeHtml(u.display_name || "—")}</td>
            <td>${escapeHtml(u.email || "—")}</td>
            <td>${escapeHtml(u.phone || "—")}</td>
            <td>${u.wechat_bound ? "已绑定" : "—"}</td>
            <td>${escapeHtml(formatDateTime(u.created_at))}</td>
          </tr>`
            )
            .join("") || `<tr><td colspan="6" class="muted">${escapeHtml(emptyText)}</td></tr>`
        }
      </tbody>
    </table></div>`;
  }

  function bindCommerceUserRows(root) {
    if (!root) return;
    root.querySelectorAll(".commerce-user-row").forEach((row) => {
      const openUser = () => {
        const userId = Number(row.dataset.id);
        if (!userId) return;
        state.selectedId = userId;
        setTab("users");
        loadUsers()
          .then(() => loadDetail(userId))
          .catch((e) => alert(e.message));
      };
      row.addEventListener("click", openUser);
      row.addEventListener("keydown", (ev) => {
        if (ev.key === "Enter" || ev.key === " ") {
          ev.preventDefault();
          openUser();
        }
      });
    });
  }

  async function loadCommerce() {
    const [overview, orders] = await Promise.all([
      api("/commerce/overview"),
      api(
        `/commerce/orders?limit=${commerceState.limit}&offset=${commerceState.offset}` +
          (commerceState.status ? `&status=${encodeURIComponent(commerceState.status)}` : "") +
          (commerceState.kind ? `&kind=${encodeURIComponent(commerceState.kind)}` : "")
      ),
    ]);
    const trial = overview.trial || {};
    const users = overview.users || {};
    const orderStats = overview.orders || {};
    const todayRows = users.today || [];
    const allRows = users.all || users.recent || [];
    $("commerceOverview").innerHTML = `
      <div class="stat"><span class="muted">注册用户总数</span><strong>${num(
        users.total
      )}</strong></div>
      <div class="stat"><span class="muted">今日新注册（上海时区）</span><strong>${num(
        users.new_today
      )}</strong></div>
      <div class="stat"><span class="muted">近 7 日新注册</span><strong>${num(
        users.new_7d
      )}</strong></div>
      <div class="stat"><span class="muted">近 30 日新注册</span><strong>${num(
        users.new_30d
      )}</strong></div>
      <div class="stat"><span class="muted">当前 Pro 会员</span><strong>${num(
        users.active_pro
      )}</strong></div>
      <div class="stat"><span class="muted">近 7 日新增 Pro</span><strong>${num(
        users.new_pro_7d
      )}</strong></div>
      <div class="stat"><span class="muted">已支付订单</span><strong>${num(
        orderStats.paid
      )}</strong><span class="muted">近 7 日 ${num(orderStats.paid_7d)}</span></div>
      <div class="stat"><span class="muted">未支付订单</span><strong>${num(
        orderStats.unpaid
      )}</strong><span class="muted">实收 ${money(
        (orderStats.paid_amount_cents || 0) / 100
      )}</span></div>
      <div class="stat"><span class="muted">试用延展券</span><strong>${num(
        trial.extend_coupons
      )} / 已兑 ${num(trial.extend_redeemed)}</strong></div>
      <div class="stat"><span class="muted">SKU / 积分流水</span><strong>${num(
        Object.keys(overview.skus_by_kind || {}).length
      )} / ${num(overview.points_ledger_rows)}</strong></div>`;

    const todayEl = $("commerceTodayUsers");
    if (todayEl) {
      todayEl.innerHTML = `<h3>今日注册用户（${num(todayRows.length)} 人）</h3>
        ${renderUserRosterTable(todayRows, "今天还没有新注册用户")}
        <p class="muted">按 Asia/Shanghai 自然日统计；点击一行可打开该用户资产页。</p>`;
      bindCommerceUserRows(todayEl);
    }

    const allEl = $("commerceAllUsers");
    if (allEl) {
      allEl.innerHTML = `<h3>系统现有用户列表（最近 ${num(allRows.length)} / 共 ${num(
        users.total
      )}）</h3>
        ${renderUserRosterTable(allRows, "暂无注册用户")}
        <p class="muted">完整翻页与搜索也可到顶部「用户资产」页。</p>`;
      bindCommerceUserRows(allEl);
    }

    const items = orders.items || [];
    $("commerceOrdersList").innerHTML = `<h3>订单列表</h3><table>
      <thead><tr><th>ID</th><th>用户</th><th>状态</th><th>渠道</th><th>金额</th><th>SKU</th><th>时间</th></tr></thead>
      <tbody>
        ${
          items
            .map(
              (o) => `<tr>
            <td>${o.id}</td>
            <td>#${o.user_id}</td>
            <td><span class="chip">${escapeHtml(o.status)}</span></td>
            <td>${escapeHtml(o.provider || "—")}</td>
            <td>${money((o.amount_cents || 0) / 100)}</td>
            <td>${escapeHtml((o.sku_codes || []).join(", ") || "—")}</td>
            <td>${escapeHtml(
              o.paid_at || o.created_at
                ? new Date(o.paid_at || o.created_at).toLocaleString("zh-CN")
                : ""
            )}</td>
          </tr>`
            )
            .join("") || `<tr><td colspan="7" class="muted">暂无订单</td></tr>`
        }
      </tbody>
    </table>`;
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
    stopUserRegistrationWatch();
    stopUploadsAutoRefresh();
    hideNewUserModal();
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
    if (state.tab === "uploads") {
      loadUploads().catch((e) => console.warn(e));
    }
    if (state.selectedId) await loadDetail(state.selectedId);
    startUserRegistrationWatch();
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
        <div class="dash-card">
          <h3>后端 HTTP 探测 ${escapeHtml(
            ((data.endpoint_health || {}).overall || "—")
          )}</h3>
          <div class="table-wrap"><table>
            <thead><tr><th>探测</th><th>状态</th><th>延迟</th><th>说明</th></tr></thead>
            <tbody>
              ${((data.endpoint_health || {}).services || [])
                .map((row) => {
                  const st = row.state || (row.ok ? "healthy" : "unhealthy");
                  const chip =
                    st === "healthy" ? "ok" : st === "degraded" ? "warn" : "bad";
                  return `<tr><td>${escapeHtml(row.name || row.id || "")}</td>
                    <td><span class="chip ${chip}">${escapeHtml(st)}</span></td>
                    <td>${num(row.latency_ms)} ms</td>
                    <td>${escapeHtml(row.detail || "")}</td></tr>`;
                })
                .join("") ||
                `<tr><td colspan="4" class="muted">暂无探测数据</td></tr>`}
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
    const [users, learning, pnl, infra, feedbackPeek, pendingAssets, commerce, dailyUsage, uploadsPeek] =
      await Promise.all([
        api("/analytics/users?days=90"),
        api("/analytics/learning"),
        api("/usage/pnl?days=30"),
        api("/analytics/infra").catch(() => null),
        api("/feedback?status=open&limit=1").catch(() => null),
        api("/exam-assets?status=pending&limit=200").catch(() => []),
        api("/commerce/overview").catch(() => null),
        api("/usage/daily").catch(() => null),
        api("/fingerprint-cache/upload-tasks?limit=1&stuck_only=true").catch(() => null),
      ]);
    const host = (infra && infra.host) || {};
    const mem = host.memory || {};
    const root = host.root_disk || {};
    const pendingList = Array.isArray(pendingAssets)
      ? pendingAssets
      : pendingAssets.items || [];
    const openFeedback = (feedbackPeek && feedbackPeek.open_count) || 0;
    const trial = (commerce && commerce.trial) || {};
    const cloudTok = (dailyUsage && dailyUsage.cloud_tokens) || 0;
    const cloudCny = (dailyUsage && dailyUsage.cloud_cost_cny) || 0;
    const cloudAlert = !!(dailyUsage && dailyUsage.alert);
    const stuckUploads = (uploadsPeek && uploadsPeek.stuck_count) || 0;
    const inFlightUploads = (uploadsPeek && uploadsPeek.in_flight_count) || 0;
    const el = $("panel-dashboard");
    el.innerHTML = `
      <div class="kpi-row">
        <div class="stat"><span class="muted">总用户</span><strong>${num(users.total_users)}</strong></div>
        <div class="stat"><span class="muted">近 ${users.days} 日新增</span><strong>${num(users.new_users)}</strong></div>
        <div class="stat"><span class="muted">30 日收入</span><strong>${money(pnl.revenue_cny)}</strong></div>
        <div class="stat"><span class="muted">30 日毛利</span><strong>${money(pnl.gross_cny)}</strong></div>
      </div>
      <div class="kpi-row">
        <div class="stat ${cloudAlert ? "hot" : ""}"><span class="muted">今日云端 Token</span><strong>${num(
          cloudTok
        )}</strong>
          <p class="muted" style="margin:4px 0 0">${
            cloudAlert
              ? escapeHtml((dailyUsage && dailyUsage.alert_reason) || "云端用量偏高")
              : `估算 ${money(cloudCny)} · 政策：默认本机 GPU`
          }</p>
          <button type="button" class="btn ghost dash-jump" data-tab="usage">看明细</button></div>
        <div class="stat"><span class="muted">待处理优化建议</span><strong>${num(openFeedback)}</strong>
          <button type="button" class="btn ghost dash-jump" data-tab="feedback">去处理</button></div>
        <div class="stat"><span class="muted">待审考试资料</span><strong>${num(pendingList.length)}</strong>
          <button type="button" class="btn ghost dash-jump" data-tab="exam-assets">去审核</button></div>
        <div class="stat"><span class="muted">上传卡住 / 进行中</span><strong>${num(
          stuckUploads
        )} / ${num(inFlightUploads)}</strong>
          <button type="button" class="btn ghost dash-jump" data-tab="uploads">去监控</button></div>
        <div class="stat"><span class="muted">试用延展已兑</span><strong>${num(
          trial.extend_redeemed
        )} / ${num(trial.extend_coupons)}</strong>
          <button type="button" class="btn ghost dash-jump" data-tab="commerce">看订单</button></div>
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
    el.querySelectorAll(".dash-jump").forEach((btn) => {
      btn.addEventListener("click", () => {
        const tab = btn.dataset.tab;
        const tabBtn = document.querySelector(`.tab[data-tab="${tab}"]`);
        if (tabBtn) tabBtn.click();
      });
    });
  }

  async function loadUsage() {
    const q = usageQuery();
    const [summary, pnl, platform] = await Promise.all([
      api(`/usage/summary?${q}`),
      api(`/usage/pnl?${q}`),
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
    const byDay = summary.by_day || [];
    const maxDayTokens = Math.max(1, ...byDay.map((d) => Number(d.tokens) || 0));
    const moduleLabel = (m) => labelsZh[m] || (m && m !== "unknown" ? m : "未标注模块");
    const el = $("panel-usage");
    const dayValue = usageState.day || "";
    el.innerHTML = `
      <div class="toolbar usage-toolbar">
        <form id="usageFilterForm" class="search usage-filter">
          <label class="muted">按天查询
            <input id="usageDayInput" type="date" value="${escapeHtml(dayValue)}" />
          </label>
          <div class="usage-presets">
            <button type="button" class="btn ghost usage-preset" data-day="today">今天</button>
            <button type="button" class="btn ghost usage-preset" data-days="7">近7天</button>
            <button type="button" class="btn ghost usage-preset" data-days="30">近30天</button>
            <button type="button" class="btn ghost usage-preset" data-days="90">近90天</button>
          </div>
          <button type="submit" class="btn">查询</button>
        </form>
        <div class="note-box">当前窗口：${escapeHtml(usageWindowLabel())}</div>
      </div>
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
          <h3>阿里云 BSS · 百炼 / 短信 / ECS / CDT（${escapeHtml(
            (platform.billing_cycle || "").toString()
          )}）</h3>
          <div class="table-wrap"><table>
            <thead><tr><th>产品</th><th>明细</th><th>用量</th><th>税前 CNY</th><th>实例/模型</th></tr></thead>
            <tbody>
              ${["sfm", "dysms", "dysms_system", "ecs", "cdt"]
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
              `<tr><td colspan="5" class="muted">本月暂无百炼/短信/ECS/CDT 明细，或 AccessKey 无 BSS 权限。</td></tr>`}
            </tbody>
          </table></div>
          ${
            sfm.pretax_cny
              ? `<div class="note-box">百炼合计税前 ${money(sfm.pretax_cny)} · ${num(
                  sfm.count
                )} 条计费项</div>`
              : ""
          }
          ${
            ((aliyun.products || {}).cdt || {}).count
              ? `<div class="note-box">CDT 流量税前 ${money(
                  ((aliyun.products || {}).cdt || {}).pretax_cny || 0
                )} · ${num(((aliyun.products || {}).cdt || {}).count)} 条 · 版本 ${escapeHtml(
                  ((((aliyun.products || {}).cdt || {}).cdt_versions || []).join("/") || "—")
                )}（兼容 1.0 ECS_Out_Bytes 与 2.0 internet_traffic）</div>`
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
        <div class="dash-card full">
          <h3>按天 Token 消耗（Asia/Shanghai）</h3>
          <div class="table-wrap"><table>
            <thead><tr><th>日期</th><th>事件</th><th>Tokens</th><th>成本 CNY</th><th>占比</th></tr></thead>
            <tbody>
              ${
                byDay
                  .slice()
                  .reverse()
                  .map((d) => {
                    const tokens = Number(d.tokens) || 0;
                    const pct = Math.round((tokens / maxDayTokens) * 100);
                    return `<tr class="usage-day-row" data-day="${escapeHtml(d.day)}" tabindex="0">
                      <td><strong>${escapeHtml(d.day)}</strong></td>
                      <td>${num(d.events)}</td>
                      <td>${num(tokens)}</td>
                      <td>${money(d.cost_cny)}</td>
                      <td><div class="bar-track"><div class="bar-fill" style="width:${pct}%"></div></div></td>
                    </tr>`;
                  })
                  .join("") ||
                `<tr><td colspan="5" class="muted">该时间窗口暂无用量</td></tr>`
              }
            </tbody>
          </table></div>
          <div class="note-box">点击某一天可切换到单日明细。当前合计 Tokens ${num(
            summary.tokens
          )} · 成本 ${money(summary.cost_cny)}</div>
        </div>
        <div class="dash-card">
          <h3>损益（${escapeHtml(usageWindowLabel())}）</h3>
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
          <h3>用户消耗 Top（可点开用户档案）</h3>
          <div class="table-wrap"><table>
            <thead><tr><th>用户</th><th>联系方式</th><th>微信</th><th>事件</th><th>Tokens</th><th>成本 CNY</th></tr></thead>
            <tbody>
              ${(summary.by_user || [])
                .map((u) => {
                  const name = u.display_name || "—";
                  const contact = [u.email, u.phone].filter(Boolean).join(" · ") || "—";
                  return `<tr class="usage-user-row" data-id="${u.user_id}" tabindex="0">
                    <td><strong>#${u.user_id}</strong> ${escapeHtml(name)}</td>
                    <td>${escapeHtml(contact)}</td>
                    <td>${u.wechat_bound ? "已绑定" : "—"}</td>
                    <td>${num(u.events)}</td>
                    <td>${num(u.tokens)}</td>
                    <td>${money(u.cost_cny)}</td>
                  </tr>`;
                })
                .join("") || `<tr><td colspan="6" class="muted">暂无按用户归因的用量</td></tr>`}
              ${
                summary.unattributed && summary.unattributed.events
                  ? `<tr class="muted"><td colspan="3">未归因（服务端/未登录）</td><td>${num(
                      summary.unattributed.events
                    )}</td><td>${num(summary.unattributed.tokens)}</td><td>${money(
                      summary.unattributed.cost_cny
                    )}</td></tr>`
                  : ""
              }
            </tbody>
          </table></div>
          <div class="note-box">${escapeHtml(summary.note || "")}</div>
        </div>
      </div>`;
    const form = $("usageFilterForm");
    if (form) {
      form.addEventListener("submit", (ev) => {
        ev.preventDefault();
        const picked = ($("usageDayInput")?.value || "").trim();
        usageState.day = picked;
        if (picked) usageState.days = 1;
        loadUsage().catch((e) => alert(e.message));
      });
    }
    el.querySelectorAll(".usage-preset").forEach((btn) => {
      btn.addEventListener("click", () => {
        if (btn.dataset.day === "today") {
          usageState.day = chinaTodayYmd();
          usageState.days = 1;
        } else {
          usageState.day = "";
          usageState.days = Number(btn.dataset.days) || 30;
        }
        loadUsage().catch((e) => alert(e.message));
      });
    });
    el.querySelectorAll(".usage-day-row").forEach((row) => {
      const openDay = () => {
        const day = (row.dataset.day || "").trim();
        if (!day) return;
        usageState.day = day;
        usageState.days = 1;
        loadUsage().catch((e) => alert(e.message));
      };
      row.addEventListener("click", openDay);
      row.addEventListener("keydown", (ev) => {
        if (ev.key === "Enter" || ev.key === " ") {
          ev.preventDefault();
          openDay();
        }
      });
    });
    el.querySelectorAll(".usage-user-row").forEach((row) => {
      const openUser = () => {
        const userId = Number(row.dataset.id);
        if (!userId) return;
        state.selectedId = userId;
        setTab("users");
        loadUsers()
          .then(() => loadDetail(userId))
          .catch((e) => alert(e.message));
      };
      row.addEventListener("click", openUser);
      row.addEventListener("keydown", (ev) => {
        if (ev.key === "Enter" || ev.key === " ") {
          ev.preventDefault();
          openUser();
        }
      });
    });
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

  function formatDateTime(value) {
    if (!value) return "—";
    try {
      return new Date(value).toLocaleString("zh-CN", {
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
        hour12: false,
      });
    } catch {
      return String(value);
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
      list.innerHTML = `<div class="table-wrap user-table-wrap"><table class="user-table">
        <thead>
          <tr>
            <th>ID</th>
            <th>昵称</th>
            <th>邮箱</th>
            <th>手机</th>
            <th>微信</th>
            <th>注册时间</th>
            <th>钱包/积分</th>
          </tr>
        </thead>
        <tbody>
          ${data.items
            .map((u) => {
              const active = u.id === state.selectedId ? "active" : "";
              const name = u.display_name || "—";
              return `<tr class="user-row ${active}" data-id="${u.id}" tabindex="0">
                <td>${u.id}</td>
                <td>${escapeHtml(name)}</td>
                <td>${escapeHtml(u.email || "—")}</td>
                <td>${escapeHtml(u.phone || "—")}</td>
                <td>${u.wechat_bound ? "已绑定" : "—"}</td>
                <td>${escapeHtml(formatDateTime(u.created_at))}</td>
                <td>${u.wallet_credits ?? "—"} / ${u.points_balance ?? 0}</td>
              </tr>`;
            })
            .join("")}
        </tbody>
      </table></div>`;
      const selectUser = (userId) => {
        state.selectedId = userId;
        list.querySelectorAll(".user-row").forEach((row) => {
          row.classList.toggle("active", Number(row.dataset.id) === state.selectedId);
        });
        loadDetail(state.selectedId);
      };
      list.querySelectorAll(".user-row").forEach((row) => {
        row.addEventListener("click", () => selectUser(Number(row.dataset.id)));
        row.addEventListener("keydown", (ev) => {
          if (ev.key === "Enter" || ev.key === " ") {
            ev.preventDefault();
            selectUser(Number(row.dataset.id));
          }
        });
      });
    }
    const page = Math.floor(state.offset / state.limit) + 1;
    const pages = Math.max(1, Math.ceil(state.total / state.limit));
    $("pageInfo").textContent = `${page} / ${pages} · 共 ${state.total} 名注册用户`;
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
        <p class="muted">密码无法查看。重置后只显示一次新密码；修改邮箱会影响原邮箱登录。可直接改 Pro 到期时间，或按天数重设 / 叠加。</p>
        <div class="actions">
          <form id="passwordForm" class="inline-form" style="flex:1">
            <input name="new_password" type="password" minlength="12" autocomplete="new-password" placeholder="自定新密码（至少12位，留空则生成）" />
            <button class="btn danger full" type="submit">修改 / 重置密码</button>
          </form>
          <form id="membershipForm" class="grant-grid" style="flex:1.4">
            <label>等级
              <select name="level">
                <option value="free" ${u.membership_level === "free" ? "selected" : ""}>免费</option>
                <option value="pro" ${u.membership_level === "pro" ? "selected" : ""}>Pro 会员</option>
              </select>
            </label>
            <label>当前到期
              <input type="text" readonly value="${escapeAttr(proEndsLabel(data))}" />
            </label>
            <label class="full">调整方式
              <select name="pro_mode" id="proModeSelect">
                <option value="extend" selected>按天数叠加到现有到期</option>
                <option value="set">按天数从今天起算</option>
                <option value="absolute">指定到期时间</option>
                <option value="lifetime">永久 Pro</option>
              </select>
            </label>
            <label id="proDaysField">有效天数
              <input name="duration_days" type="number" min="1" max="3650" value="30" />
            </label>
            <label class="full" id="proEndsField" hidden>
              指定到期时间（本地时区）
              <input name="ends_at_local" type="datetime-local" value="" />
            </label>
            <button class="btn primary full" type="submit">保存会员有效期</button>
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
    const syncProModeFields = () => {
      const mode = String($("proModeSelect")?.value || "extend");
      const daysField = $("proDaysField");
      const endsField = $("proEndsField");
      if (daysField) daysField.hidden = mode === "absolute" || mode === "lifetime";
      if (endsField) endsField.hidden = mode !== "absolute";
    };
    $("proModeSelect")?.addEventListener("change", syncProModeFields);
    syncProModeFields();

    $("membershipForm")?.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const fd = new FormData(ev.target);
      const level = String(fd.get("level") || "free");
      const proMode = String(fd.get("pro_mode") || "extend");
      const daysRaw = String(fd.get("duration_days") || "").trim();
      const durationDays = daysRaw === "" ? null : Number(daysRaw);
      let endsAt = null;
      if (level === "pro" && proMode === "absolute") {
        try {
          endsAt = localInputToIso(fd.get("ends_at_local"));
        } catch (e) {
          alert(e.message);
          return;
        }
        if (!endsAt) {
          alert("请选择到期时间");
          return;
        }
      }
      if (
        level === "pro" &&
        (proMode === "extend" || proMode === "set") &&
        (!durationDays || durationDays < 1)
      ) {
        alert("请填写有效天数");
        return;
      }
      const summary =
        level === "free"
          ? "免费（吊销 Pro）"
          : proMode === "lifetime"
            ? "永久 Pro"
            : proMode === "absolute"
              ? `Pro，到期 ${new Date(endsAt).toLocaleString("zh-CN")}`
              : proMode === "extend"
                ? `Pro，在现有到期上叠加 ${durationDays} 天`
                : `Pro，从今天起 ${durationDays} 天`;
      if (!confirm(`确认将用户 #${userId} 设为：${summary}？`)) return;
      try {
        const body = { level };
        if (level === "pro") {
          if (proMode === "lifetime") {
            body.lifetime = true;
          } else if (proMode === "absolute") {
            body.ends_at = endsAt;
          } else {
            body.duration_days = durationDays;
            body.duration_mode = proMode === "extend" ? "extend" : "set";
          }
        }
        const result = await api(`/users/${userId}/membership`, {
          method: "PUT",
          body: JSON.stringify(body),
        });
        const savedEnds = result?.entitlement?.ends_at;
        alert(
          level === "free"
            ? "已改为免费"
            : savedEnds
              ? `已保存。新到期：${new Date(savedEnds).toLocaleString("zh-CN")}`
              : "已保存为永久 Pro"
        );
        try {
          await loadDetail(userId);
        } catch (_) {}
        try {
          await loadStats();
        } catch (_) {}
      } catch (e) {
        alert(`保存失败：${e.message}`);
      }
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

  function on(id, event, handler) {
    const el = $(id);
    if (!el) return;
    el.addEventListener(event, handler);
  }

  on("loginBtn", "click", login);
  ["usernameInput", "passwordInput", "tokenInput"].forEach((id) => {
    on(id, "keydown", (e) => {
      if (e.key === "Enter") login();
    });
  });
  on("loadTokenBtn", "click", () => $("tokenFileInput")?.click());
  on("tokenFileInput", "change", (e) => {
    const file = e.target.files && e.target.files[0];
    if (file) loadTokenFromFile(file);
    e.target.value = "";
  });
  on("saveTokenBtn", "click", saveTokenToLocal);
  on("logoutBtn", "click", logout);
  on("refreshBtn", "click", () => {
    if (state.tab === "uploads") {
      loadUploads().catch((e) => alert(e.message));
      return;
    }
    bootstrap().catch((e) => alert(e.message));
  });
  on("searchForm", "submit", (e) => {
    e.preventDefault();
    state.q = $("searchInput").value.trim();
    state.offset = 0;
    loadUsers().catch((err) => alert(err.message));
  });
  on("prevPage", "click", () => {
    state.offset = Math.max(0, state.offset - state.limit);
    loadUsers().catch((err) => alert(err.message));
  });
  on("nextPage", "click", () => {
    state.offset += state.limit;
    loadUsers().catch((err) => alert(err.message));
  });
  document.querySelectorAll(".tab").forEach((btn) => {
    btn.addEventListener("click", () => {
      setTab(btn.dataset.tab);
      if (btn.dataset.tab === "dashboard") loadDashboard().catch((e) => alert(e.message));
      if (btn.dataset.tab === "feedback") loadFeedback().catch((e) => alert(e.message));
      if (btn.dataset.tab === "uploads") loadUploads().catch((e) => alert(e.message));
      if (btn.dataset.tab === "exam-assets") loadExamAssets().catch((e) => alert(e.message));
      if (btn.dataset.tab === "commerce") loadCommerce().catch((e) => alert(e.message));
      if (btn.dataset.tab === "infra") loadInfra().catch((e) => alert(e.message));
      if (btn.dataset.tab === "usage") loadUsage().catch((e) => alert(e.message));
      if (btn.dataset.tab === "resources") loadResources().catch((e) => alert(e.message));
      if (btn.dataset.tab === "fingerprint") loadFingerprint().catch((e) => alert(e.message));
      if (btn.dataset.tab === "community") loadCommunityPosts().catch((e) => alert(e.message));
    });
  });
  on("uploadsFilterForm", "submit", (e) => {
    e.preventDefault();
    uploadsState.status = $("uploadsStatusFilter")?.value || "";
    uploadsState.file_type = $("uploadsTypeFilter")?.value || "";
    uploadsState.created_from = $("uploadsFromInput")?.value || "";
    uploadsState.created_to = $("uploadsToInput")?.value || "";
    uploadsState.q = ($("uploadsSearchInput")?.value || "").trim();
    uploadsState.stuck_only = Boolean($("uploadsStuckOnly")?.checked);
    uploadsState.auto_refresh = Boolean($("uploadsAutoRefresh")?.checked);
    uploadsState.offset = 0;
    loadUploads().catch((err) => alert(err.message));
  });
  on("uploadsAutoRefresh", "change", () => {
    uploadsState.auto_refresh = Boolean($("uploadsAutoRefresh")?.checked);
    syncUploadsAutoRefresh();
  });
  on("uploadsStuckOnly", "change", () => {
    uploadsState.stuck_only = Boolean($("uploadsStuckOnly")?.checked);
    uploadsState.offset = 0;
    loadUploads().catch((err) => alert(err.message));
  });
  on("uploadsPrev", "click", () => {
    uploadsState.offset = Math.max(0, uploadsState.offset - uploadsState.limit);
    loadUploads().catch((err) => alert(err.message));
  });
  on("uploadsNext", "click", () => {
    if (uploadsState.offset + uploadsState.limit >= uploadsState.total) return;
    uploadsState.offset += uploadsState.limit;
    loadUploads().catch((err) => alert(err.message));
  });
  on("uploadsDrainBtn", "click", async () => {
    if (!confirm("排空最多 5 条 queue_gpu 上传任务？")) return;
    try {
      const r = await api("/fingerprint-cache/drain-queue?limit=5", { method: "POST" });
      alert(`已处理 ${r.processed || 0} 条`);
      await loadUploads();
    } catch (e) {
      alert(e.message);
    }
  });
  on("communitySearchForm", "submit", (e) => {
    e.preventDefault();
    communityState.q = $("communitySearchInput").value.trim();
    communityState.status = $("communityStatus").value;
    communityState.offset = 0;
    loadCommunityPosts().catch((err) => alert(err.message));
  });
  on("communityPrev", "click", () => {
    communityState.offset = Math.max(0, communityState.offset - communityState.limit);
    loadCommunityPosts().catch((err) => alert(err.message));
  });
  on("communityNext", "click", () => {
    communityState.offset += communityState.limit;
    loadCommunityPosts().catch((err) => alert(err.message));
  });
  on("feedbackSearchForm", "submit", (e) => {
    e.preventDefault();
    feedbackState.status = $("feedbackStatusFilter").value;
    feedbackState.category = $("feedbackCategoryFilter").value;
    feedbackState.q = $("feedbackSearchInput").value.trim();
    feedbackState.offset = 0;
    loadFeedback().catch((err) => alert(err.message));
  });
  on("feedbackPrev", "click", () => {
    feedbackState.offset = Math.max(0, feedbackState.offset - feedbackState.limit);
    loadFeedback().catch((err) => alert(err.message));
  });
  on("feedbackNext", "click", () => {
    feedbackState.offset += feedbackState.limit;
    loadFeedback().catch((err) => alert(err.message));
  });
  on("examAssetsFilterForm", "submit", (e) => {
    e.preventDefault();
    examAssetsState.status = $("examAssetsStatusFilter").value;
    loadExamAssets().catch((err) => alert(err.message));
  });
  on("commerceOrdersForm", "submit", (e) => {
    e.preventDefault();
    commerceState.status = $("commerceOrderStatus").value;
    commerceState.kind = $("commerceOrderKind").value;
    commerceState.offset = 0;
    loadCommerce().catch((err) => alert(err.message));
  });
  on("newUserModalDismiss", "click", () => hideNewUserModal());
  on("newUserModalOpen", "click", () => openPendingNewUsers());
  const newUserModal = $("newUserModal");
  if (newUserModal) {
    newUserModal.addEventListener("click", (ev) => {
      if (ev.target === newUserModal) hideNewUserModal();
    });
  }

  // Always show login gate (username + password + token). Prefill account/token only.
  showLogin();
  if ($("usernameInput")) $("usernameInput").value = state.username || "admin";
  if (state.token && $("tokenInput")) $("tokenInput").value = state.token;
})();
