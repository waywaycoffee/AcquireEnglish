import { useState, type FormEvent } from "react";
import { Link, Navigate, useNavigate } from "react-router-dom";
import { useAuth } from "../auth";

export default function LoginPage() {
  const { login, user, loading } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState("demo@example.com");
  const [password, setPassword] = useState("demo1234");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [showEmail, setShowEmail] = useState(false);

  if (!loading && user) return <Navigate to="/app" replace />;

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      await login(email, password);
      navigate("/app");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Login failed");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="auth-wrap">
      <div className="card auth-card">
        <div className="brand">AcquireEnglish</div>
        <p className="muted">选择登录方式。微信 / 手机号支持模拟页联调。</p>
        {error ? <div className="error">{error}</div> : null}

        <div className="login-method-stack">
          <Link className="login-method wechat" to="/login/wechat">
            <strong>微信登录（模拟）</strong>
            <span>进入授权模拟页，同意后自动登录/注册</span>
          </Link>
          <Link className="login-method phone" to="/login/phone">
            <strong>手机号登录</strong>
            <span>短信验证码；模拟模式下验证码自动填入</span>
          </Link>
          <button
            className="login-method email"
            type="button"
            onClick={() => setShowEmail((v) => !v)}
          >
            <strong>邮箱登录</strong>
            <span>使用邮箱与密码登录已有账号</span>
          </button>
        </div>

        {showEmail ? (
          <form onSubmit={onSubmit} style={{ marginTop: 18 }}>
            <label className="field">
              <span>邮箱</span>
              <input
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                type="email"
                required
              />
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
              {submitting ? "登录中…" : "登录"}
            </button>
          </form>
        ) : null}

        <p className="muted" style={{ marginTop: 16 }}>
          还没有账号？ <Link to="/register">邮箱验证码注册</Link>
        </p>
      </div>
    </div>
  );
}
