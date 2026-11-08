import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { api, type Course, type Preferences } from "../api";
import { useAuth } from "../auth";

const LEVELS = ["A1", "A2", "B1", "B2", "C1"];
const TAGS = ["slow", "daily", "news", "ted", "travel", "business"];

export default function HomePage() {
  const { user, token, logout } = useAuth();
  const navigate = useNavigate();
  const [courses, setCourses] = useState<Course[]>([]);
  const [feed, setFeed] = useState<Course[]>([]);
  const [prefs, setPrefs] = useState<Preferences>({
    level: "A2",
    tags: ["slow", "daily"],
    daily_quota: 2,
    notify_daily_feed: true,
    has_bilibili_cookie: false,
  });
  const [biliCookieDraft, setBiliCookieDraft] = useState("");
  const [asrKeyDraft, setAsrKeyDraft] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [importUrl, setImportUrl] = useState("");
  const [importing, setImporting] = useState(false);

  async function refreshCourses() {
    if (!token) return;
    setCourses(await api.courses(token));
  }

  useEffect(() => {
    if (!token) return;
    void refreshCourses().catch((err) =>
      setError(err instanceof Error ? err.message : "Failed to load courses"),
    );
  }, [token]);

  useEffect(() => {
    if (!token) return;
    void api
      .getPreferences(token)
      .then(setPrefs)
      .catch(() => undefined);
    void api
      .dailyFeed(token)
      .then(setFeed)
      .catch(() => undefined);
  }, [token]);

  async function savePrefs() {
    if (!token) return;
    setSaving(true);
    try {
      const payload: Preferences = { ...prefs };
      if (biliCookieDraft.trim()) {
        payload.bilibili_cookie = biliCookieDraft.trim();
      }
      if (asrKeyDraft.trim()) {
        payload.asr_api_key = asrKeyDraft.trim();
      }
      const next = await api.putPreferences(token, payload);
      setPrefs(next);
      setBiliCookieDraft("");
      setAsrKeyDraft("");
      setFeed(await api.dailyFeed(token));
    } catch (err) {
      setError(err instanceof Error ? err.message : "保存偏好失败");
    } finally {
      setSaving(false);
    }
  }

  async function importLink() {
    if (!token || !importUrl.trim()) return;
    setImporting(true);
    setError(null);
    try {
      const course = await api.importLink(token, importUrl.trim());
      setImportUrl("");
      await refreshCourses();
      navigate(`/courses/${course.id}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "导入失败");
    } finally {
      setImporting(false);
    }
  }

  return (
    <div className="shell">
      <header className="topbar">
        <div>
          <div className="brand">AcquireEnglish</div>
          <div className="muted">你好，{user?.display_name ?? user?.email}</div>
        </div>
        <button className="btn ghost" type="button" onClick={logout}>
          退出
        </button>
      </header>

      {error ? <div className="error">{error}</div> : null}

      <section className="card" style={{ marginBottom: 24 }}>
        <h2 style={{ fontFamily: "var(--font-display)", marginTop: 0 }}>导入链接学习</h2>
        <p className="muted" style={{ marginTop: 0 }}>
          支持 YouTube / Bilibili（B站）粘贴链接 · 自动拉标题与字幕 · 与 App 共用账号课程
        </p>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          <input
            value={importUrl}
            onChange={(e) => setImportUrl(e.target.value)}
            placeholder="https://www.youtube.com/watch?v=… 或 https://www.bilibili.com/video/BV…"
            style={{
              flex: 1,
              minWidth: 240,
              borderRadius: 12,
              border: "1px solid var(--border)",
              background: "rgba(0,0,0,0.25)",
              color: "var(--text)",
              padding: "12px 14px",
            }}
          />
          <button className="btn" type="button" disabled={importing} onClick={() => void importLink()}>
            {importing ? "导入中…" : "导入并学习"}
          </button>
        </div>
        <div style={{ marginTop: 16 }}>
          <div className="muted" style={{ marginBottom: 8 }}>
            B 站登录 Cookie（部分视频字幕需登录）
            {prefs.has_bilibili_cookie ? " · 已保存" : " · 未配置"}
          </div>
          <textarea
            value={biliCookieDraft}
            onChange={(e) => setBiliCookieDraft(e.target.value)}
            placeholder="B 站 AI 字幕必须登录才能拉取。F12 → Application → Cookies → bilibili.com → 复制 SESSDATA=...; bili_jct=...; buvid3=... 粘贴后点「保存偏好」，再重新导入视频"
            rows={2}
            style={{
              width: "100%",
              borderRadius: 12,
              border: "1px solid var(--border)",
              background: "rgba(0,0,0,0.25)",
              color: "var(--text)",
              padding: "12px 14px",
              resize: "vertical",
            }}
          />
          <div className="muted" style={{ margin: "14px 0 8px" }}>
            阿里云百炼 ASR Key（网页「AI 生成字幕」用）
            {prefs.has_asr_api_key ? " · 已保存" : " · 未配置"}
          </div>
          <input
            type="password"
            value={asrKeyDraft}
            onChange={(e) => setAsrKeyDraft(e.target.value)}
            placeholder="sk-…（DashScope API Key）"
            style={{
              width: "100%",
              borderRadius: 12,
              border: "1px solid var(--border)",
              background: "rgba(0,0,0,0.25)",
              color: "var(--text)",
              padding: "12px 14px",
            }}
          />
        </div>
      </section>

      <section className="card" style={{ marginBottom: 24 }}>
        <h2 style={{ fontFamily: "var(--font-display)", marginTop: 0 }}>学习偏好</h2>
        <div className="muted">级别与标签驱动每日课程 Feed（与 App 同步）</div>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 12 }}>
          {LEVELS.map((level) => (
            <button
              key={level}
              type="button"
              className={`chip ${prefs.level === level ? "on" : ""}`}
              onClick={() => setPrefs((p) => ({ ...p, level }))}
            >
              {level}
            </button>
          ))}
        </div>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 12 }}>
          {TAGS.map((tag) => {
            const on = prefs.tags.includes(tag);
            return (
              <button
                key={tag}
                type="button"
                className={`chip ${on ? "on" : ""}`}
                onClick={() =>
                  setPrefs((p) => ({
                    ...p,
                    tags: on ? p.tags.filter((t) => t !== tag) : [...p.tags, tag],
                  }))
                }
              >
                {tag}
              </button>
            );
          })}
        </div>
        <label className="muted" style={{ display: "block", marginTop: 12 }}>
          每日推荐 {prefs.daily_quota} 课
          <input
            type="range"
            min={1}
            max={5}
            value={prefs.daily_quota}
            onChange={(e) => setPrefs((p) => ({ ...p, daily_quota: Number(e.target.value) }))}
            style={{ display: "block", width: "100%", maxWidth: 320 }}
          />
        </label>
        <button className="btn" type="button" onClick={() => void savePrefs()} disabled={saving}>
          {saving ? "保存中…" : "保存并刷新今日课程"}
        </button>
      </section>

      <section style={{ marginBottom: 28 }}>
        <h2 style={{ fontFamily: "var(--font-display)", marginBottom: 8 }}>今日更新</h2>
        <p className="muted" style={{ marginTop: 0 }}>
          按偏好从课程池筛选，已学课会降权
        </p>
        <div className="grid-courses">
          {feed.length === 0 ? (
            <div className="muted">登录后保存偏好即可看到今日推荐</div>
          ) : (
            feed.map((course) => (
              <Link key={course.id} to={`/courses/${course.id}`} className="card">
                <div className="muted" style={{ fontSize: 12, marginBottom: 8 }}>
                  {course.level} · {course.lessons.length} 课段
                </div>
                <div style={{ fontSize: "1.2rem", fontWeight: 700 }}>{course.titleZh ?? course.title}</div>
                <p className="muted" style={{ marginBottom: 0 }}>
                  {course.description}
                </p>
              </Link>
            ))
          )}
        </div>
      </section>

      <section>
        <h2 style={{ fontFamily: "var(--font-display)", marginBottom: 8 }}>全部课程</h2>
        <p className="muted" style={{ marginTop: 0 }}>
          云端课程包 + 你导入的链接课 · 与手机 App 共用进度
        </p>
        <div className="grid-courses">
          {courses.map((course) => (
            <Link key={course.id} to={`/courses/${course.id}`} className="card">
              <div className="muted" style={{ fontSize: 12, marginBottom: 8 }}>
                {course.level} · {course.tags?.join(" · ")} · {course.lessons.length} 课段
              </div>
              <div style={{ fontSize: "1.2rem", fontWeight: 700 }}>{course.titleZh ?? course.title}</div>
              <p className="muted" style={{ marginBottom: 0 }}>
                {course.description}
              </p>
            </Link>
          ))}
        </div>
      </section>
    </div>
  );
}
