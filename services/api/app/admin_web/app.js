(() => {
  const TOKEN_KEY = "ae_admin_token";
  const state = {
    token: localStorage.getItem(TOKEN_KEY) || "",
    offset: 0,
    limit: 40,
    total: 0,
    q: "",
    selectedId: null,
    skus: [],
  };

  const $ = (id) => document.getElementById(id);
  const loginView = $("loginView");
  const appView = $("appView");
  const loginError = $("loginError");

  function apiBase() {
    // Same origin when served from nginx /admin or FastAPI /admin
    return "";
  }

  async function api(path, options = {}) {
    const headers = Object.assign(
      { "Content-Type": "application/json", "X-Admin-Token": state.token },
      options.headers || {}
    );
    const res = await fetch(`${apiBase()}/api/admin${path}`, {
      ...options,
      headers,
    });
    let data = null;
    const text = await res.text();
    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      data = { detail: text };
    }
    if (!res.ok) {
      const detail =
        (data && (data.detail || data.message)) || `HTTP ${res.status}`;
      throw new Error(typeof detail === "string" ? detail : JSON.stringify(detail));
    }
    return data;
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

  async function login() {
    state.token = $("tokenInput").value.trim();
    if (!state.token) {
      loginError.textContent = "请输入管理员令牌";
      return;
    }
    try {
      await api("/ping");
      localStorage.setItem(TOKEN_KEY, state.token);
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
    showLogin();
  }

  async function bootstrap() {
    await Promise.all([loadStats(), loadUsers(), loadSkus()]);
    if (state.selectedId) await loadDetail(state.selectedId);
  }

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
      const data = await api("/skus");
      state.skus = data.items || [];
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
          return `<button class="user-item ${active}" data-id="${u.id}" type="button">
            <div class="title">${escapeHtml(name)}</div>
            <div class="meta">#${u.id} · ${escapeHtml(u.email || "")}${
            u.phone ? " · " + escapeHtml(u.phone) : ""
          }</div>
            <div class="meta">钱包 ${u.wallet_credits ?? "—"} · 积分 ${u.points_balance ?? 0}</div>
          </button>`;
        })
        .join("");
      list.querySelectorAll(".user-item").forEach((btn) => {
        btn.addEventListener("click", () => {
          state.selectedId = Number(btn.dataset.id);
          loadUsers();
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

  async function loadDetail(userId) {
    $("emptyDetail").classList.add("hidden");
    const view = $("detailView");
    view.classList.remove("hidden");
    view.innerHTML = `<p class="muted">加载中…</p>`;
    try {
      const data = await api(`/users/${userId}`);
      view.innerHTML = renderDetail(data);
      wireDetail(data);
    } catch (e) {
      view.innerHTML = `<p class="error">${escapeHtml(e.message)}</p>`;
    }
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
          }" data-days="${s.duration_days ?? ""}">${escapeHtml(
            s.title
          )} (${escapeHtml(s.sku_code)})</option>`
      )
      .join("");

    const ents = (data.entitlements || [])
      .map((e) => {
        const revoke =
          e.status === "active"
            ? `<button class="btn danger" data-revoke="${e.id}" type="button">吊销</button>`
            : "";
        return `<tr>
          <td>${e.id}</td>
          <td>${escapeHtml(e.asset_kind)}<br/><span class="muted">${escapeHtml(
          e.asset_ref
        )}</span></td>
          <td>${escapeHtml(e.status)}</td>
          <td>${e.quantity ?? "∞"}</td>
          <td>${escapeHtml(e.ends_at || "—")}</td>
          <td>${revoke}</td>
        </tr>`;
      })
      .join("");

    const orders = (data.orders || [])
      .map(
        (o) => `<tr>
        <td>${o.id}</td>
        <td>${escapeHtml(o.status)}</td>
        <td>${escapeHtml(o.provider)}</td>
        <td>${(o.amount_cents / 100).toFixed(2)} ${escapeHtml(o.currency || "")}</td>
        <td>${escapeHtml(o.created_at || "")}</td>
      </tr>`
      )
      .join("");

    const wledger = (data.wallet_ledger || [])
      .map(
        (r) =>
          `<tr><td>${r.id}</td><td>${r.delta}</td><td>${escapeHtml(
            r.reason
          )}</td><td>${escapeHtml(r.created_at || "")}</td></tr>`
      )
      .join("");

    const pledger = (data.points_ledger || [])
      .map(
        (r) =>
          `<tr><td>${r.id}</td><td>${r.delta}</td><td>${escapeHtml(
            r.reason
          )}</td><td>${escapeHtml(r.created_at || "")}</td></tr>`
      )
      .join("");

    return `
      <div class="detail-head">
        <div>
          <h2>${escapeHtml(u.display_name || u.email)}</h2>
          <p class="muted">#${u.id} · ${escapeHtml(u.email || "")}${
      u.phone ? " · " + escapeHtml(u.phone) : ""
    }</p>
          <div class="chips">
            <span class="chip">钱包 ${u.wallet_credits ?? 0}</span>
            <span class="chip">分享积分 ${u.points_balance ?? 0}</span>
            <span class="chip">导入课 ${c.link_courses ?? 0}</span>
            <span class="chip">生词 ${c.vocab_items ?? 0}</span>
            <span class="chip">微信 ${u.wechat_bound ? "已绑定" : "未绑定"}</span>
          </div>
        </div>
        <form id="renameForm" class="inline-form" style="width:min(320px,100%)">
          <input class="full" name="display_name" value="${escapeAttr(
            u.display_name || ""
          )}" placeholder="显示名" />
          <button class="btn primary full" type="submit">保存资料</button>
        </form>
      </div>

      <section class="section">
        <h3>发放权益</h3>
        <form id="grantForm" class="grant-grid">
          <label class="full">快捷 SKU
            <select id="skuPick"><option value="">自定义填写</option>${skuOptions}</select>
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
            <input name="delta" type="number" required placeholder="钱包 delta，可负" />
            <input name="reason" placeholder="原因 admin_adjust" />
            <button class="btn primary full" type="submit">调整钱包积分</button>
          </form>
          <form id="pointsForm" class="inline-form" style="flex:1">
            <input name="delta" type="number" required placeholder="分享积分 delta" />
            <input name="reason" placeholder="原因 admin_adjust" />
            <button class="btn primary full" type="submit">调整分享积分</button>
          </form>
        </div>
      </section>

      <section class="section">
        <h3>权益列表</h3>
        <div class="table-wrap">
          <table>
            <thead><tr><th>ID</th><th>资产</th><th>状态</th><th>数量</th><th>到期</th><th></th></tr></thead>
            <tbody>${ents || `<tr><td colspan="6" class="muted">暂无</td></tr>`}</tbody>
          </table>
        </div>
      </section>

      <section class="section">
        <h3>订单</h3>
        <div class="table-wrap">
          <table>
            <thead><tr><th>ID</th><th>状态</th><th>渠道</th><th>金额</th><th>创建时间</th></tr></thead>
            <tbody>${orders || `<tr><td colspan="5" class="muted">暂无</td></tr>`}</tbody>
          </table>
        </div>
      </section>

      <section class="section">
        <h3>钱包流水</h3>
        <div class="table-wrap">
          <table>
            <thead><tr><th>ID</th><th>Delta</th><th>原因</th><th>时间</th></tr></thead>
            <tbody>${wledger || `<tr><td colspan="4" class="muted">暂无</td></tr>`}</tbody>
          </table>
        </div>
      </section>

      <section class="section">
        <h3>分享积分流水</h3>
        <div class="table-wrap">
          <table>
            <thead><tr><th>ID</th><th>Delta</th><th>原因</th><th>时间</th></tr></thead>
            <tbody>${pledger || `<tr><td colspan="4" class="muted">暂无</td></tr>`}</tbody>
          </table>
        </div>
      </section>
    `;
  }

  function wireDetail(data) {
    const userId = data.user.id;
    const skuPick = $("skuPick");
    if (skuPick) {
      skuPick.addEventListener("change", () => {
        const opt = skuPick.selectedOptions[0];
        if (!opt || !opt.value) return;
        const form = $("grantForm");
        form.asset_kind.value = opt.dataset.kind || "";
        form.asset_ref.value = opt.dataset.ref || opt.value;
        form.quantity.value = opt.dataset.qty || "";
        form.duration_days.value = opt.dataset.days || "";
      });
    }

    $("renameForm")?.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const fd = new FormData(ev.target);
      try {
        await api(`/users/${userId}`, {
          method: "PATCH",
          body: JSON.stringify({ display_name: fd.get("display_name") }),
        });
        await Promise.all([loadUsers(), loadDetail(userId), loadStats()]);
      } catch (e) {
        alert(e.message);
      }
    });

    $("grantForm")?.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const fd = new FormData(ev.target);
      const quantityRaw = String(fd.get("quantity") || "").trim();
      const daysRaw = String(fd.get("duration_days") || "").trim();
      const body = {
        asset_kind: String(fd.get("asset_kind") || "").trim(),
        asset_ref: String(fd.get("asset_ref") || "").trim(),
        quantity: quantityRaw === "" ? null : Number(quantityRaw),
        duration_days: daysRaw === "" ? null : Number(daysRaw),
        source: "grant",
        meta: { via: "admin_web" },
      };
      try {
        await api(`/users/${userId}/entitlements/grant`, {
          method: "POST",
          body: JSON.stringify(body),
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

  $("loginBtn").addEventListener("click", login);
  $("tokenInput").addEventListener("keydown", (e) => {
    if (e.key === "Enter") login();
  });
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

  if (state.token) {
    showApp();
    bootstrap().catch((e) => showLogin(e.message || "令牌无效，请重新登录"));
  } else {
    showLogin();
  }
})();
