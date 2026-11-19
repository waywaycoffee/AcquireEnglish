import { useEffect, useState, type FormEvent } from "react";
import { Link, Navigate, useNavigate } from "react-router-dom";
import { useAuth } from "../auth";

export default function RegisterPage() {
  const { register, sendEmailCode, user, loading } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [code, setCode] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [sendingCode, setSendingCode] = useState(false);
  const [cooldown, setCooldown] = useState(0);
  const [hint, setHint] = useState<string | null>(null);

  useEffect(() => {
    if (cooldown <= 0) return;
    const id = window.setTimeout(() => setCooldown((v) => Math.max(0, v - 1)), 1000);
    return () => window.clearTimeout(id);
  }, [cooldown]);

  if (!loading && user) return <Navigate to="/app" replace />;

  async function onSendCode() {
    setError(null);
    setHint(null);
    if (!email.trim()) {
      setError("请输入邮箱");
      return;
    }
    setSendingCode(true);
    try {
      const sent = await sendEmailCode(email.trim());
      setCooldown(Math.min(120, Math.max(30, sent.expiresIn || 60)));
      if (sent.debugCode && !code) {
        setCode(sent.debugCode);
      }
      setHint(sent.mock ? "已发送（开发模式，验证码已自动填入）" : "验证码已发送到邮箱");
    } catch (err) {
      setError(err instanceof Error ? err.message : "验证码发送失败");
    } finally {
      setSendingCode(false);
    }
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      await register(email, password, code, displayName || undefined);
      navigate("/app");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Register failed");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="auth-wrap">
      <form className="card auth-card" onSubmit={onSubmit}>
        <div className="brand">AcquireEnglish</div>
        <p className="muted">先获取邮箱验证码，再设置密码完成注册</p>
        {error ? <div className="error">{error}</div> : null}
        {hint ? <div className="muted">{hint}</div> : null}
        <label className="field">
          <span>昵称</span>
          <input value={displayName} onChange={(e) => setDisplayName(e.target.value)} />
        </label>
        <label className="field">
          <span>邮箱</span>
          <input value={email} onChange={(e) => setEmail(e.target.value)} type="email" required />
        </label>
        <label className="field">
          <span>邮箱验证码</span>
          <div style={{ display: "flex", gap: 8 }}>
            <input
              value={code}
              onChange={(e) => setCode(e.target.value)}
              inputMode="numeric"
              required
              style={{ flex: 1 }}
            />
            <button
              className="btn"
              type="button"
              disabled={sendingCode || cooldown > 0}
              onClick={() => void onSendCode()}
              style={{ whiteSpace: "nowrap" }}
            >
              {cooldown > 0 ? `${cooldown}s` : sendingCode ? "发送中…" : "获取验证码"}
            </button>
          </div>
        </label>
        <label className="field">
          <span>密码</span>
          <input
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            type="password"
            minLength={6}
            required
          />
        </label>
        <button className="btn" type="submit" disabled={submitting}>
          {submitting ? "注册中…" : "注册并登录"}
        </button>
        <p className="muted" style={{ marginTop: 16 }}>
          已有账号？ <Link to="/login">登录</Link>
        </p>
      </form>
    </div>
  );
}
