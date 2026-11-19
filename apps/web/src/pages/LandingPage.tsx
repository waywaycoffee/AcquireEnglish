import { Link } from "react-router-dom";

const FEATURES = [
  {
    title: "真实视频输入",
    body: "基于可理解性输入，用 B 站 / YouTube / 本地视频学英语，边看边练。",
  },
  {
    title: "跟读 · 配音 · 听写",
    body: "影子跟读评分、配音回放分享、听写纠错，一套流程练听说读写。",
  },
  {
    title: "数字人口语外教",
    body: "围绕字幕预生成口语话题，引导回忆内容、词汇与语法，并及时纠错。",
  },
  {
    title: "账号进度同步",
    body: "支持手机号登录与微信登录（审核中），课程与学习进度云端同步。",
  },
];

const STEPS = [
  "导入或打开一节英语视频课程",
  "观看字幕，用跟读 / 听写巩固句子",
  "用数字人围绕视频内容练口语问答",
  "收藏词卡与短语，多端继续学习",
];

export default function LandingPage() {
  return (
    <div className="landing">
      <header className="landing-nav">
        <div className="brand">爱快英语 · Acquire English</div>
        <div className="landing-nav-actions">
          <Link className="btn ghost" to="/login">
            登录
          </Link>
          <Link className="btn" to="/register">
            注册
          </Link>
        </div>
      </header>

      <main className="landing-main">
        <section className="landing-hero">
          <p className="landing-kicker">视频英语学习 App</p>
          <h1>用真实视频学英语，边看边说</h1>
          <p className="landing-lead">
            Acquire English 基于可理解性输入理论：真实视频 + 跟读配音听写 +
            数字人口语外教。学得更快，也更地道。
          </p>
          <div className="landing-cta">
            <Link className="btn" to="/register">
              开始使用
            </Link>
            <a className="btn ghost" href="#features">
              了解产品
            </a>
          </div>
        </section>

        <section id="features" className="landing-section">
          <h2>产品能力</h2>
          <div className="landing-grid">
            {FEATURES.map((item) => (
              <article key={item.title} className="card landing-card">
                <h3>{item.title}</h3>
                <p className="muted">{item.body}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="landing-section">
          <h2>如何使用</h2>
          <ol className="landing-steps">
            {STEPS.map((step, index) => (
              <li key={step}>
                <span className="landing-step-num">{index + 1}</span>
                <span>{step}</span>
              </li>
            ))}
          </ol>
        </section>

        <section className="landing-section card">
          <h2>应用信息</h2>
          <dl className="landing-meta">
            <div>
              <dt>应用名称</dt>
              <dd>爱快英语（Acquire English）</dd>
            </div>
            <div>
              <dt>产品形态</dt>
              <dd>Android / iOS App + PC 网站</dd>
            </div>
            <div>
              <dt>Android 包名</dt>
              <dd>com.acquire.english</dd>
            </div>
            <div>
              <dt>服务内容</dt>
              <dd>英语视频学习、跟读评测、听写练习、数字人口语陪练、学习进度同步</dd>
            </div>
            <div>
              <dt>官网</dt>
              <dd>https://acquireenglish.curlhairai.com/</dd>
            </div>
            <div>
              <dt>联系方式</dt>
              <dd>support@curlhairai.com</dd>
            </div>
          </dl>
        </section>
      </main>

      <footer className="landing-footer muted">
        <p>© {new Date().getFullYear()} 爱快英语 Acquire English</p>
        <p>本站用于展示应用服务信息；学习功能需登录后使用。</p>
      </footer>
    </div>
  );
}
