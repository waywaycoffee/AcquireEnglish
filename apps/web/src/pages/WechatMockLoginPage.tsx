import { useEffect, useState, type FormEvent } from "react";
import { Link, Navigate, useNavigate } from "react-router-dom";
import { api } from "../api";
import { useAuth } from "../auth";

const STORAGE_KEY = "ae_wechat_mock_code";

function loadOrCreateCode(): string {
  const existing = localStorage.getItem(STORAGE_KEY)?.trim();
  if (existing) return existing;
  const created = `mock_web_${Date.now()}`;
  localStorage.setItem(STORAGE_KEY, created);
  return created;
}

export default function WechatMockLoginPage() {
  const { user, loading, applyToken } = useAuth();
  const navigate = useNavigate();
  const [code, setCode] = useState("");
  const [nickname, setNickname] = useState("Web Mock 用户");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [advanced, setAdvanced] = useState(false);
  const [agreed, setAgreed] = useState(false);

  useEffect(() => {
    setCode(loadOrCreateCode());
  }, []);

  if (!loading && user) return <Navigate to="/app" replace />;

  function resetIdentity() {
    const fresh = `mock_web_${Date.now()}`;
    localStorage.setItem(STORAGE_KEY, fresh);
    setCode(fresh);
  }

  async function onAgree(e?: FormEvent) {
    e?.preventDefault();
    setError(null);
    if (!agreed) {
      setError("请先阅读并勾选同意《用户协议与版权声明》");
      return;
    }
    setSubmitting(true);
    try {
      const trimmed = code.trim();
      if (!trimmed) {
        setError("请填写模拟授权码");
        return;
      }
      localStorage.setItem(STORAGE_KEY, trimmed);
      const res = await api.loginWithWechat(trimmed, nickname.trim() || undefined);
      applyToken(res.access_token, res.user);
      navigate("/app");
    } catch (err) {
      setError(err instanceof Error ? err.message : "微信登录失败");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="auth-wrap">
      <form className="card auth-card wechat-mock-card" onSubmit={(e) => void onAgree(e)}>
        <div className="auth-mock-banner">
          开发模拟页：不会跳转微信 App。同意后使用下方身份码完成服务端登录/自动注册。
        </div>
        <div className="wechat-mock-hero">
          <div className="wechat-mock-badge">微信授权（模拟）</div>
          <h1>爱快英语 申请使用</h1>
          <p className="muted">你的微信头像、昵称与 OpenID（模拟）</p>
          <ul className="wechat-mock-perms">
            <li>获取你的公开信息（昵称、头像）</li>
            <li>用于账号登录与跨设备同步学习进度</li>
          </ul>
        </div>
        {error ? <div className="error">{error}</div> : null}
        <label className="field">
          <span>显示昵称</span>
          <input value={nickname} onChange={(e) => setNickname(e.target.value)} />
        </label>
        <label className="field" style={{ display: "flex", gap: 10, alignItems: "flex-start" }}>
          <input
            type="checkbox"
            checked={agreed}
            onChange={(e) => setAgreed(e.target.checked)}
            style={{ marginTop: 4 }}
          />
          <span>
            我已阅读并同意
            <Link to="/terms">《用户协议与版权声明》</Link>
            。确认所有视频均由本人自行导入、自行学习；本软件不提供视频爬取功能。
          </span>
        </label>
        <button className="btn wechat-btn" type="submit" disabled={submitting || !agreed}>
          {submitting ? "登录中…" : "同意"}
        </button>
        <button
          className="btn ghost"
          type="button"
          disabled={submitting}
          onClick={() => navigate("/login")}
          style={{ marginTop: 10, width: "100%" }}
        >
          拒绝
        </button>
        <button
          className="btn ghost"
          type="button"
          onClick={() => setAdvanced((v) => !v)}
          style={{ marginTop: 10, width: "100%" }}
        >
          {advanced ? "收起开发选项" : "开发选项"}
        </button>
        {advanced ? (
          <div style={{ marginTop: 14 }}>
            <label className="field">
              <span>模拟授权码（同一码 = 同一微信账号）</span>
              <input value={code} onChange={(e) => setCode(e.target.value)} />
            </label>
            <button className="btn ghost" type="button" onClick={resetIdentity}>
              换一个新身份
            </button>
          </div>
        ) : null}
        <p className="muted" style={{ marginTop: 16 }}>
          <Link to="/login/phone">手机号登录</Link>
          {" · "}
          <Link to="/login">返回登录方式</Link>
        </p>
      </form>
    </div>
  );
}
