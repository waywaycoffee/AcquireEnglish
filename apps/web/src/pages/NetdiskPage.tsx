import { useEffect, useMemo, useState } from "react";
import { Link, Navigate, useNavigate } from "react-router-dom";
import { api } from "../api";
import { useAuth } from "../auth";

const PROVIDERS: { id: string; label: string; hint: string }[] = [
  { id: "baidu", label: "百度网盘", hint: "优先扫码/账号授权；高级可粘贴 Cookie" },
  { id: "quark", label: "夸克", hint: "登录 pan.quark.cn 后复制 Cookie" },
  { id: "aliyun", label: "阿里云盘", hint: "粘贴 Open refresh_token" },
  { id: "pan115", label: "115", hint: "登录 115 后复制 Cookie" },
];

type Entry = {
  name: string;
  path: string;
  is_dir: boolean;
  size?: number | null;
  is_video?: boolean;
};

export default function NetdiskPage() {
  const { user, token, loading } = useAuth();
  const navigate = useNavigate();
  const [provider, setProvider] = useState("baidu");
  const [credential, setCredential] = useState("");
  const [openlistReady, setOpenlistReady] = useState(false);
  const [baiduOauthReady, setBaiduOauthReady] = useState(false);
  const [bound, setBound] = useState(false);
  const [healthy, setHealthy] = useState(true);
  const [healthError, setHealthError] = useState<string | null>(null);
  const [mountPath, setMountPath] = useState("");
  const [stack, setStack] = useState<string[]>([]);
  const [entries, setEntries] = useState<Entry[]>([]);
  const [hint, setHint] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const relPath = useMemo(() => stack.join("/"), [stack]);
  const videoCount = entries.filter((e) => !e.is_dir).length;

  async function refreshStatus() {
    if (!token) return;
    const status = await api.netdiskStatus(token);
    setOpenlistReady(!!status.openlist_configured);
    setBaiduOauthReady(!!status.baidu_oauth_configured);
    const row = status.providers.find((p) => p.provider === provider);
    setBound(!!row?.bound);
    setMountPath(row?.mount_path ?? "");
    setHealthy(row?.healthy !== false);
    setHealthError(row?.error ?? null);
    return row;
  }

  async function loadDir(nextStack: string[] = stack) {
    if (!token) return;
    setBusy(true);
    setError(null);
    try {
      const data = await api.netdiskList(token, provider, nextStack.join("/"));
      setEntries(data.entries ?? []);
      setHint(data.hint ?? null);
      setStack(nextStack);
    } catch (err) {
      setError(err instanceof Error ? err.message : "列目录失败");
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    if (!token) return;
    void (async () => {
      try {
        const row = await refreshStatus();
        if (row?.bound && row.healthy !== false) {
          await loadDir([]);
        }
      } catch (err) {
        setError(err instanceof Error ? err.message : "加载失败");
      }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token, provider]);

  if (!loading && !user) return <Navigate to="/login" replace />;

  async function onBind() {
    if (!token || credential.trim().length < 8) {
      setError("请粘贴有效 Cookie / token");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await api.netdiskBind(token, provider, credential.trim());
      setCredential("");
      const row = await refreshStatus();
      if (row?.bound) await loadDir([]);
    } catch (err) {
      setError(err instanceof Error ? err.message : "绑定失败");
    } finally {
      setBusy(false);
    }
  }

  async function onBaiduOauth() {
    if (!token) return;
    setBusy(true);
    setError(null);
    try {
      const started = await api.netdiskBaiduOauthStart(token);
      window.open(started.authorize_url, "_blank", "noopener,noreferrer");
      setError("请在新打开的页面扫码或登录授权，完成后刷新本页");
      const timer = window.setInterval(() => {
        void refreshStatus().then((row) => {
          if (row?.bound) {
            window.clearInterval(timer);
            void loadDir([]);
          }
        });
      }, 3000);
      window.setTimeout(() => window.clearInterval(timer), 180_000);
    } catch (err) {
      setError(err instanceof Error ? err.message : "无法启动百度授权");
    } finally {
      setBusy(false);
    }
  }

  async function onImportFolder() {
    if (!token) return;
    const folder = stack.length === 0 ? mountPath : `${mountPath}/${relPath}`;
    if (!folder) {
      setError("请先进入剧季文件夹");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const result = await api.netdiskImportSeries(token, {
        provider,
        folder_path: folder,
      });
      const courseId = result.series_course?.id;
      if (courseId) {
        navigate(`/courses/${courseId}`);
        return;
      }
      setError("导入完成，但未返回合集课程");
    } catch (err) {
      setError(err instanceof Error ? err.message : "导入失败");
    } finally {
      setBusy(false);
    }
  }

  const providerMeta = PROVIDERS.find((p) => p.id === provider)!;

  return (
    <div className="shell">
      <header className="topbar">
        <div>
          <div className="brand">网盘导入</div>
          <div className="muted">文件夹 → 一门多集课 · 看美剧学英语</div>
        </div>
        <Link className="btn ghost" to="/app">
          返回
        </Link>
      </header>

      {error ? <div className="error">{error}</div> : null}

      <section className="card" style={{ marginBottom: 16 }}>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          {PROVIDERS.map((p) => (
            <button
              key={p.id}
              type="button"
              className={`chip ${provider === p.id ? "on" : ""}`}
              onClick={() => {
                setProvider(p.id);
                setStack([]);
                setEntries([]);
              }}
            >
              {p.label}
            </button>
          ))}
        </div>
        {!openlistReady ? (
          <p className="muted">服务端尚未启用 OpenList。</p>
        ) : !bound ? (
          <>
            <p className="muted">{providerMeta.hint}</p>
            {provider === "baidu" && baiduOauthReady ? (
              <button
                className="btn"
                type="button"
                disabled={busy}
                onClick={() => void onBaiduOauth()}
                style={{ marginBottom: 12 }}
              >
                {busy ? "打开授权中…" : "百度扫码 / 账号授权"}
              </button>
            ) : null}
            <textarea
              value={credential}
              onChange={(e) => setCredential(e.target.value)}
              rows={4}
              style={{ width: "100%", marginBottom: 8 }}
              placeholder="Cookie / token（高级）"
            />
            <button className="btn" type="button" disabled={busy} onClick={() => void onBind()}>
              {busy ? "绑定中…" : "用 Cookie / token 绑定"}
            </button>
          </>
        ) : !healthy ? (
          <>
            <div className="error">
              授权可能已失效{healthError ? `：${healthError}` : ""}。请解绑后重新绑定。
            </div>
            <button
              className="btn ghost"
              type="button"
              disabled={busy}
              onClick={() =>
                void api.netdiskUnbind(token!, provider).then(() => refreshStatus())
              }
            >
              解绑并重新授权
            </button>
          </>
        ) : (
          <>
            <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
              <button
                className="btn ghost"
                type="button"
                disabled={busy || stack.length === 0}
                onClick={() => void loadDir(stack.slice(0, -1))}
              >
                上级
              </button>
              <span className="muted" style={{ flex: 1 }}>
                {stack.length === 0 ? mountPath || "根目录" : `${mountPath}/${relPath}`}
              </span>
              <button
                className="btn ghost"
                type="button"
                disabled={busy}
                onClick={() =>
                  void api.netdiskUnbind(token!, provider).then(() => refreshStatus())
                }
              >
                解绑
              </button>
            </div>
            {hint ? <p className="muted">{hint}</p> : null}
            <ul style={{ listStyle: "none", padding: 0, margin: "12px 0" }}>
              {entries.map((e) => (
                <li key={e.path} style={{ padding: "8px 0", borderBottom: "1px solid var(--border)" }}>
                  {e.is_dir ? (
                    <button
                      type="button"
                      className="btn ghost"
                      style={{ padding: 0 }}
                      onClick={() => void loadDir([...stack, e.name])}
                    >
                      📁 {e.name}
                    </button>
                  ) : (
                    <span>🎬 {e.name}</span>
                  )}
                </li>
              ))}
            </ul>
            <button
              className="btn"
              type="button"
              disabled={busy || videoCount === 0}
              onClick={() => void onImportFolder()}
            >
              {busy ? "导入中…" : `导入本文件夹为课程（${videoCount} 集）`}
            </button>
          </>
        )}
      </section>
    </div>
  );
}
