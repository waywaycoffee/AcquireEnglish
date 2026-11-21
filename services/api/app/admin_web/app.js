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
    tab: "dashboard",
  };

  const $ = (id) => document.getElementById(id);
  const loginView = $("loginView");
  const appView = $("appView");
  const loginError = $("loginError");
  const titles = {
    dashboard: "可视化看板",
    usage: "Token 消耗与损益",
    resources: "公共资源库",
    users: "用户与资产",
  };

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
    ["dashboard", "usage", "resources", "users"].forEach((id) => {
      $(`panel-${id}`).classList.toggle("hidden", id !== tab);
    });
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
    setTab(state.tab);
    await Promise.all([
      loadDashboard().catch((e) => console.warn(e)),
      loadUsage().catch((e) => console.warn(e)),
      loadResources().catch((e) => console.warn(e)),
      loadStats(),
      loadUsers(),
      loadSkus(),
    ]);
    if (state.selectedId) await loadDetail(state.selectedId);
  }

  async function loadDashboard() {
    const [users, learning, pnl] = await Promise.all([
      api("/analytics/users?days=90"),
      api("/analytics/learning"),
      api("/usage/pnl?days=30"),
    ]);
    const el = $("panel-dashboard");
    el.innerHTML = `
      <div class="kpi-row">
        <div class="stat"><span class="muted">总用户</span><strong>${num(users.total_users)}</strong></div>
        <div class="stat"><span class="muted">近 ${users.days} 日新增</span><strong>${num(users.new_users)}</strong></div>
        <div class="stat"><span class="muted">30 日收入</span><strong>${money(pnl.revenue_cny)}</strong></div>
        <div class="stat"><span class="muted">30 日毛利</span><strong>${money(pnl.gross_cny)}</strong></div>
      </div>
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
    const [summary, pnl] = await Promise.all([
      api("/usage/summary?days=30"),
      api("/usage/pnl?days=30"),
    ]);
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
      <div class="dash-grid">
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
          <div class="note-box">EN hits ${num(data.shared_bilibili?.en_hits)} · ZH hits ${num(
      data.shared_bilibili?.zh_hits
    )} · cues ${num(data.shared_bilibili?.cues)}</div>
          <div class="table-wrap"><table>
            <thead><tr><th>BVID</th><th>P</th><th>EN</th><th>ZH</th></tr></thead>
            <tbody>
              ${(data.shared_bilibili?.top || [])
                .map(
                  (t) =>
                    `<tr><td>${escapeHtml(t.bvid)}</td><td>${t.page}</td><td>${num(
                      t.en_hits
                    )}</td><td>${num(t.zh_hits)}</td></tr>`
                )
                .join("") || `<tr><td colspan="4" class="muted">暂无</td></tr>`}
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
          }" data-days="${s.duration_days ?? ""}">${escapeHtml(s.title)} (${escapeHtml(
            s.sku_code
          )})</option>`
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
          <td>${escapeHtml(e.asset_kind)}<br/><span class="muted">${escapeHtml(e.asset_ref)}</span></td>
          <td>${escapeHtml(e.status)}</td>
          <td>${e.quantity ?? "∞"}</td>
          <td>${escapeHtml(e.ends_at || "—")}</td>
          <td>${revoke}</td>
        </tr>`;
      })
      .join("");
    return `
      <div class="detail-head">
        <div>
          <h2>${escapeHtml(u.display_name || u.email)}</h2>
          <p class="muted">#${u.id} · ${escapeHtml(u.email || "")}</p>
          <div class="chips">
            <span class="chip">钱包 ${u.wallet_credits ?? 0}</span>
            <span class="chip">分享积分 ${u.points_balance ?? 0}</span>
            <span class="chip">导入课 ${c.link_courses ?? 0}</span>
            <span class="chip">生词 ${c.vocab_items ?? 0}</span>
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
      </section>`;
  }

  function wireDetail(data) {
    const userId = data.user.id;
    $("skuPick")?.addEventListener("change", () => {
      const opt = $("skuPick").selectedOptions[0];
      if (!opt || !opt.value) return;
      const form = $("grantForm");
      form.asset_kind.value = opt.dataset.kind || "";
      form.asset_ref.value = opt.dataset.ref || opt.value;
      form.quantity.value = opt.dataset.qty || "";
      form.duration_days.value = opt.dataset.days || "";
    });
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
  document.querySelectorAll(".tab").forEach((btn) => {
    btn.addEventListener("click", () => {
      setTab(btn.dataset.tab);
      if (btn.dataset.tab === "dashboard") loadDashboard().catch((e) => alert(e.message));
      if (btn.dataset.tab === "usage") loadUsage().catch((e) => alert(e.message));
      if (btn.dataset.tab === "resources") loadResources().catch((e) => alert(e.message));
    });
  });

  if (state.token) {
    showApp();
    bootstrap().catch((e) => showLogin(e.message || "令牌无效，请重新登录"));
  } else {
    showLogin();
  }
})();
