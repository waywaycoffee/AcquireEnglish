import { useEffect, useState, type FormEvent } from "react";
import { Link, Navigate, useNavigate } from "react-router-dom";
import { api } from "../api";
import { useAuth } from "../auth";

export default function PhoneLoginPage() {
  const { user, loading, applyToken } = useAuth();
  const navigate = useNavigate();
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [hint, setHint] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [sending, setSending] = useState(false);
  const [cooldown, setCooldown] = useState(0);
  const [mock, setMock] = useState(false);
  const [agreed, setAgreed] = useState(false);

  useEffect(() => {
    if (cooldown <= 0) return;
    const id = window.setTimeout(() => setCooldown((v) => Math.max(0, v - 1)), 1000);
    return () => window.clearTimeout(id);
  }, [cooldown]);

  if (!loading && user) return <Navigate to="/app" replace />;

  async function onSend() {
    setError(null);
    setHint(null);
    if (!phone.trim()) {
      setError("请输入手机号");
      return;
    }
    setSending(true);
    try {
      const sent = await api.sendSmsCode(phone.trim());
      setMock(sent.mock);
      setCooldown(Math.min(120, Math.max(30, sent.expires_in || 60)));
      if (sent.debug_code && !code) setCode(sent.debug_code);
      setHint(
        sent.mock
          ? `模拟短信模式：验证码 ${sent.debug_code ?? ""} 已填入`
          : "验证码已发送到手机",
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : "验证码发送失败");
    } finally {
      setSending(false);
    }
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    if (!agreed) {
      setError("请先阅读并勾选同意《用户协议与版权声明》");
      return;
    }
    setSubmitting(true);
    try {
      const res = await api.loginWithSms(phone.trim(), code.trim());
      applyToken(res.access_token, res.user);
      navigate("/app");
    } catch (err) {
      setError(err instanceof Error ? err.message : "登录失败");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="auth-wrap">
      <form className="card auth-card" onSubmit={onSubmit}>
        <div className="brand">手机号登录</div>
        <p className="muted">短信验证码登录；未注册将自动创建账号</p>
        {mock ? (
          <div className="auth-mock-banner">当前为短信模拟模式（AUTH_SMS_MOCK）</div>
        ) : null}
        {error ? <div className="error">{error}</div> : null}
        {hint ? <div className="muted">{hint}</div> : null}
        <label className="field">
          <span>手机号</span>
          <input
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            inputMode="tel"
            placeholder="11 位手机号"
            required
          />
        </label>
        <label className="field">
          <span>验证码</span>
          <div style={{ display: "flex", gap: 8 }}>
            <input
              value={code}
              onChange={(e) => setCode(e.target.value)}
              inputMode="numeric"
              required
              style={{ flex: 1 }}
            />
            <button
              className="btn ghost"
              type="button"
              disabled={sending || cooldown > 0}
              onClick={() => void onSend()}
              style={{ whiteSpace: "nowrap" }}
            >
              {cooldown > 0 ? `${cooldown}s` : sending ? "发送中…" : "获取验证码"}
            </button>
          </div>
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
        <button className="btn" type="submit" disabled={submitting || !agreed}>
          {submitting ? "登录中…" : "登录 / 自动注册"}
        </button>
        <p className="muted" style={{ marginTop: 16 }}>
          <Link to="/login/wechat">微信登录（模拟）</Link>
          {" · "}
          <Link to="/login">返回登录方式</Link>
        </p>
      </form>
    </div>
  );
}
