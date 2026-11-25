/** Official WeChat fan group invite card for the marketing site. */
export default function WechatFanGroupCard() {
  return (
    <section id="community" className="landing-section card wechat-fan-group">
      <div className="wechat-fan-group-copy">
        <p className="landing-kicker">微信社群</p>
        <h2>加入「佑佑爸粉丝交流群」</h2>
        <p className="landing-section-lead muted">
          用微信扫右侧二维码进群，一起报 bug、聊学习、领内测动态。
          作者微信号 <code>youyoufairytale</code>；若二维码过期，加作者微信即可索取新码。
        </p>
        <ul className="landing-hero-points">
          <li>内测 bug 优先在群里响应</li>
          <li>学习资源与使用技巧交流</li>
          <li>注册 ID 也可私信作者开通协助</li>
        </ul>
      </div>
      <figure className="wechat-fan-group-qr">
        <img
          src="/brand/wechat-fan-group-qr.jpg"
          alt="佑佑爸粉丝交流群微信二维码"
          width={280}
          height={426}
          loading="lazy"
        />
        <figcaption className="muted">微信扫一扫加入群聊</figcaption>
      </figure>
    </section>
  );
}
