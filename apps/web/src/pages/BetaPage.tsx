import { Link } from "react-router-dom";

export default function BetaPage() {
  return (
    <div className="landing">
      <header className="landing-nav">
        <Link className="landing-brand" to="/">
          <img src="/brand/app-icon.png" alt="爱快英语 App 图标" width={40} height={40} />
          <span>爱快英语 · 内测公告</span>
        </Link>
        <nav className="landing-nav-links">
          <Link to="/">官网首页</Link>
          <a href="#notice">公告</a>
          <a href="#guide">内测说明</a>
          <a href="#video">视频功能</a>
          <a href="#duty">社区共建</a>
          <a href="#disclaimer">免责声明</a>
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

      <main className="landing-main beta-page">
        <section id="notice" className="landing-hero">
          <div className="landing-hero-copy">
            <p className="landing-kicker">App 封闭内测进行中</p>
            <h1>爱快英语邀请你一起内测</h1>
            <p className="landing-lead">
              我们正在打磨「用真实视频学英语」的完整闭环：精听、跟读、配音、听写、数字人口语，
              以及社区素材共建。内测阶段功能会持续迭代，欢迎反馈问题与建议。
            </p>
            <div className="landing-cta">
              <a className="btn" href="#guide">
                阅读内测说明
              </a>
              <Link className="btn ghost" to="/register">
                注册参与内测
              </Link>
            </div>
          </div>
          <aside className="landing-hero-visual card beta-hero-card">
            <p className="muted">内测通道</p>
            <h2>侧载 Android 包</h2>
            <ul className="landing-hero-points">
              <li>正式包名 com.acquire.english</li>
              <li>请使用内测群发放的安装包</li>
              <li>覆盖安装可保留本地学习数据</li>
              <li>问题请反馈至 support@curlhairai.com</li>
            </ul>
          </aside>
        </section>

        <section id="guide" className="landing-section card beta-block">
          <h2>内测说明（请完整阅读）</h2>
          <p className="landing-section-lead muted">
            参与内测即表示你已阅读并同意下列产品介绍、社区共建义务与内容免责声明。
          </p>

          <h3 id="video">一、视频学习功能介绍</h3>
          <ol className="beta-list">
            <li>
              <strong>真实视频输入：</strong>
              可导入 B 站、YouTube 公开视频链接，也可导入本地视频；书库支持按
              B站 / 全英可逛 / 美剧 / YouTube 等分区浏览。
            </li>
            <li>
              <strong>双语字幕精听：</strong>
              中英字幕同步、倍速、循环单句；缺字幕时可通过语音识别或社区共享字幕补全。
            </li>
            <li>
              <strong>跟读与评测：</strong>
              影子跟读、看句读、藏句读，录音后给出发音反馈。
            </li>
            <li>
              <strong>配音与分享：</strong>
              将跟读录音做成配音回放，支持连续播放与导出分享草稿。
            </li>
            <li>
              <strong>听写练习：</strong>
              听句写英文、提示核对，难题可加入听写队列。
            </li>
            <li>
              <strong>数字人口语外教：</strong>
              围绕视频字幕生成口语话题，提问、引导回忆并纠正表达。
            </li>
            <li>
              <strong>词卡 / 短语 / 复习：</strong>
              点词查义、收藏与 FSRS 复习，估计词汇量并自适应难度。
            </li>
            <li>
              <strong>社区与素材：</strong>
              可浏览全英可逛、热门分享、网盘资源帖、考试资料等；支持 fork / 导入到个人书库。
            </li>
          </ol>

          <h3 id="disclaimer">二、视频内容来源与免责声明</h3>
          <div className="beta-callout">
            <p>
              爱快英语<strong>不生产、不托管、不出售</strong>第三方影视或博主成片本体。
              App 内可学习的视频内容主要来自：
            </p>
            <ul>
              <li>
                用户自行导入的 <strong>B 站（Bilibili）</strong>、<strong>YouTube</strong>{" "}
                等公开平台上的博主作品链接；
              </li>
              <li>
                社区用户分享的学习向链接、字幕元信息、词表说明与网盘学习资源帖；
              </li>
              <li>用户本人拥有合法使用权的本地文件 / 网盘文件。</li>
            </ul>
            <p>
              平台仅提供学习工具与索引能力。请内测用户确保对所导入、分享内容拥有相应权利或许可；
              禁止上传、分享盗版或未获授权的商业影视全集、未授权有声书、未授权考试真题扫描件等。
              若权利人提出异议，我们将配合下架相关社区条目。因用户擅自分享侵权内容产生的责任，由分享者自行承担。
            </p>
            <p className="muted">
              官方不对第三方平台可用性、字幕准确性、博主内容变更作担保；网络或平台政策变化可能导致部分链接暂时无法导入。
            </p>
          </div>

          <h3 id="duty">三、内测人员的社区共建义务</h3>
          <p>
            内测不只是「试用功能」，更是一起把学习素材池做厚。每位内测人员都有义务在合法合规前提下，
            <strong>持续丰富社区素材</strong>，包括但不限于：
          </p>
          <ul className="beta-list">
            <li>
              <strong>网盘视频资源：</strong>
              在社区发布百度 / 夸克 / 阿里 / 115 等网盘学习资源帖（仅分享你有权分发的链接与说明）。
            </li>
            <li>
              <strong>美剧 / 影视学习片段推荐：</strong>
              推荐适合精听跟读的公开片源或合法网盘学习包，并注明难度与主题。
            </li>
            <li>
              <strong>B 站视频推荐：</strong>
              推荐优质英语原声 / 学习向 UP 主视频，可走全英可逛、热门分享或素材包。
            </li>
            <li>
              <strong>阅读小说电子书上传：</strong>
              向阅读库 / 社区贡献 EPUB 等电子书（须为可合法分发的文本）。
            </li>
            <li>
              <strong>有声书：</strong>
              若贡献有声书，须同时提供对应<strong>音频</strong>与文本（或明确的合法来源说明），便于听读对照。
            </li>
            <li>
              <strong>考试材料：</strong>
              上传可公开或你有权分享的考试向音频、脚本、词表等（社区「考试」页）。
            </li>
            <li>
              <strong>书本 / 教材资料：</strong>
              上传学习用书本资料、讲义或词表；请勿上传受版权保护且未获授权的完整商业教材扫描件。
            </li>
          </ul>
          <p className="muted">
            建议每次内测登录后至少贡献或完善一条社区素材（链接、字幕、词表、电子书或考试资料均可），
            并在产品反馈里记录卡顿、崩溃与导入失败案例。
          </p>

          <h3>四、内测阶段须知</h3>
          <ul className="beta-list">
            <li>功能、界面与配额可能随时调整；数据可能因版本升级发生迁移或重置。</li>
            <li>微信支付等正式商业能力可能未完全开放；请以站内提示为准。</li>
            <li>设置中的「调试 / 演示数据」仅供核对，请勿当作正式学习记录。</li>
            <li>
              反馈渠道：邮箱{" "}
              <a href="mailto:support@curlhairai.com">support@curlhairai.com</a>
              ，或 App / 社区内的产品反馈入口。
            </li>
          </ul>
        </section>

        <section className="landing-section">
          <div className="landing-cta">
            <Link className="btn" to="/register">
              注册并开始内测
            </Link>
            <Link className="btn ghost" to="/">
              返回官网首页
            </Link>
            <a className="btn ghost" href="/beta.html">
              纯静态版本
            </a>
          </div>
        </section>
      </main>

      <footer className="landing-footer muted">
        <p>© {new Date().getFullYear()} 爱快英语 Acquire English · 内测公告</p>
        <p>
          <Link to="/privacy">隐私政策</Link>
          {" · "}
          <Link to="/terms">用户协议</Link>
          {" · "}
          <Link to="/">官网首页</Link>
        </p>
      </footer>
    </div>
  );
}
