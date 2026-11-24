import { Link } from "react-router-dom";

const FEATURES = [
  {
    title: "真实视频输入",
    body: "导入 B 站、YouTube 或本地视频，基于可理解性输入边看边学。",
  },
  {
    title: "双语字幕精听",
    body: "中英字幕同步、倍速、循环单句；缺字幕时可语音识别生成跟读字幕。",
  },
  {
    title: "跟读评测",
    body: "影子跟读、看句读、藏句读，录音后给出发音反馈，适合逐句打磨。",
  },
  {
    title: "配音与分享",
    body: "把跟读录音做成配音回放，支持连续播放与导出分享。",
  },
  {
    title: "听写练习",
    body: "听句写英文、提示核对，难题可加入听写队列反复巩固。",
  },
  {
    title: "数字人口语外教",
    body: "预读字幕生成口语话题，围绕视频提问、引导回忆并纠正语法。",
  },
  {
    title: "词卡与短语",
    body: "点词查义、收藏词卡与句子，复习成长体系持续跟踪。",
  },
  {
    title: "账号与云同步",
    body: "手机号 / 微信登录后，课程、进度与个人资产可多端同步。",
  },
];

const FLOW = [
  {
    title: "打开课程",
    body: "从首页续学或书库选择视频课，也可一键导入新内容。",
  },
  {
    title: "看字幕精听",
    body: "使用双语字幕、倍速与循环，先听懂再开口。",
  },
  {
    title: "跟读 / 听写",
    body: "切换学习模式录音评分，或听写核对句子。",
  },
  {
    title: "口语陪练",
    body: "数字人围绕视频内容提问，卡住时引导词汇与语法。",
  },
];

const SHOTS = [
  {
    src: "/shots/01-home-learn.png",
    caption: "学习页：视频课程、导入入口与继续学习",
  },
  {
    src: "/shots/03-home.png",
    caption: "首页：今日推荐与学习任务",
  },
  {
    src: "/shots/02-player-modes.png",
    caption: "播放器：字幕 / 跟读 / 陪练 / 听写 / 词卡",
  },
  {
    src: "/shots/04-study.png",
    caption: "学习模式：精听与跟读练习",
  },
];

const FAQ = [
  {
    q: "爱快英语是做什么的？",
    a: "面向英语学习者的视频学习 App，用真实视频完成精听、跟读、听写与口语练习。",
  },
  {
    q: "支持哪些内容来源？",
    a: "支持 B 站、YouTube 以及本地视频导入；也可学习云端课程。",
  },
  {
    q: "需要登录吗？",
    a: "浏览本官网无需登录。使用学习功能、同步进度时需要注册/登录。",
  },
  {
    q: "如何联系我们？",
    a: "邮箱 support@curlhairai.com，我们会尽快回复产品与账号相关问题。",
  },
];

export default function LandingPage() {
  return (
    <div className="landing">
      <header className="landing-nav">
        <a className="landing-brand" href="#top">
          <img src="/brand/app-icon.png" alt="爱快英语 App 图标" width={40} height={40} />
          <span>爱快英语 · Acquire English</span>
        </a>
        <nav className="landing-nav-links">
          <a href="#features">功能</a>
          <a href="#shots">界面</a>
          <a href="#flow">流程</a>
          <a href="#info">应用信息</a>
          <Link to="/beta">内测公告</Link>
          <Link to="/privacy">隐私政策</Link>
          <Link to="/terms">用户协议</Link>
        </nav>
        <div className="landing-nav-actions">
          <Link className="btn ghost" to="/login">
            登录
          </Link>
          <Link className="btn" to="/register">
            注册
          </Link>
        </div>
      </header>

      <main id="top" className="landing-main">
        <Link className="landing-beta-banner" to="/beta">
          <span className="landing-beta-tag">内测进行中</span>
          <span>
            App 封闭内测开放报名：请阅读视频功能介绍、内容来源免责声明与社区素材共建义务 →
          </span>
        </Link>

        <section className="landing-hero">
          <div className="landing-hero-copy">
            <p className="landing-kicker">视频英语学习应用</p>
            <h1>用真实视频学英语，边看边说</h1>
            <p className="landing-lead">
              爱快英语（Acquire English）基于可理解性输入：导入真实视频，完成精听、跟读、配音、听写，
              再用数字人口语外教围绕字幕练习表达。适合想把「看得懂」变成「说得出」的学习者。
            </p>
            <div className="landing-cta">
              <a className="btn" href="#shots">
                查看应用界面
              </a>
              <a className="btn ghost" href="#info">
                应用详情
              </a>
            </div>
          </div>
          <div className="landing-hero-visual card">
            <img src="/brand/app-icon.png" alt="爱快英语图标" className="landing-hero-icon" />
            <h2>爱快英语</h2>
            <p className="muted">Acquire English</p>
            <ul className="landing-hero-points">
              <li>真实视频 + 双语字幕</li>
              <li>跟读评测 / 听写 / 配音</li>
              <li>数字人口语陪练</li>
              <li>账号进度云端同步</li>
            </ul>
          </div>
        </section>

        <section id="features" className="landing-section">
          <h2>核心服务</h2>
          <p className="landing-section-lead muted">
            以下为 App 主要功能，审核与用户均可据此了解服务内容。
          </p>
          <div className="landing-grid">
            {FEATURES.map((item) => (
              <article key={item.title} className="card landing-card">
                <h3>{item.title}</h3>
                <p className="muted">{item.body}</p>
              </article>
            ))}
          </div>
        </section>

        <section id="shots" className="landing-section">
          <h2>应用运行界面</h2>
          <p className="landing-section-lead muted">
            真实 App 截图，展示首页、学习页与播放器学习模式。
          </p>
          <div className="landing-shots">
            {SHOTS.map((shot) => (
              <figure key={shot.src} className="landing-shot card">
                <img src={shot.src} alt={shot.caption} loading="lazy" />
                <figcaption className="muted">{shot.caption}</figcaption>
              </figure>
            ))}
          </div>
        </section>

        <section id="flow" className="landing-section">
          <h2>使用流程</h2>
          <ol className="landing-steps">
            {FLOW.map((step, index) => (
              <li key={step.title}>
                <span className="landing-step-num">{index + 1}</span>
                <div>
                  <strong>{step.title}</strong>
                  <p className="muted">{step.body}</p>
                </div>
              </li>
            ))}
          </ol>
        </section>

        <section id="info" className="landing-section card">
          <h2>应用信息</h2>
          <dl className="landing-meta">
            <div>
              <dt>应用名称</dt>
              <dd>爱快英语（Acquire English）</dd>
            </div>
            <div>
              <dt>应用简介</dt>
              <dd>
                基于可理解性输入的视频英语学习工具，提供跟读、配音、听写与数字人口语陪练。
              </dd>
            </div>
            <div>
              <dt>产品形态</dt>
              <dd>Android / iOS 移动应用 + PC 网站</dd>
            </div>
            <div>
              <dt>Android 包名</dt>
              <dd>com.acquire.english</dd>
            </div>
            <div>
              <dt>服务内容</dt>
              <dd>
                英语视频学习、字幕精听、跟读评测、听写练习、数字人口语陪练、词卡复习、学习进度同步
              </dd>
            </div>
            <div>
              <dt>上架状态</dt>
              <dd>开发中 / 未上架应用市场（可通过官网了解产品详情）</dd>
            </div>
            <div>
              <dt>官网</dt>
              <dd>
                <a href="https://acquireenglish.curlhairai.com/">
                  https://acquireenglish.curlhairai.com/
                </a>
              </dd>
            </div>
            <div>
              <dt>静态产品页</dt>
              <dd>
                <a href="https://acquireenglish.curlhairai.com/product.html">
                  https://acquireenglish.curlhairai.com/product.html
                </a>
              </dd>
            </div>
            <div>
              <dt>联系邮箱</dt>
              <dd>
                <a href="mailto:support@curlhairai.com">support@curlhairai.com</a>
              </dd>
            </div>
          </dl>
        </section>

        <section className="landing-section">
          <h2>常见问题</h2>
          <div className="landing-faq">
            {FAQ.map((item) => (
              <article key={item.q} className="card">
                <h3>{item.q}</h3>
                <p className="muted">{item.a}</p>
              </article>
            ))}
          </div>
        </section>
      </main>

      <footer className="landing-footer muted">
        <p>© {new Date().getFullYear()} 爱快英语 Acquire English</p>
        <p>
          <Link to="/beta">内测公告</Link>
          {" · "}
          <Link to="/privacy">隐私政策</Link>
          {" · "}
          <Link to="/terms">用户协议</Link>
          {" · "}
          <a href="/product.html">纯静态介绍页</a>
        </p>
        <p>本站展示应用服务信息；学习功能登录后使用。</p>
      </footer>
    </div>
  );
}
