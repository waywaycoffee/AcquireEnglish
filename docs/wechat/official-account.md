# 微信公众号挂官网（公司主体）

前提：公司主体已认证；`acquireenglish.curlhairai.com` 已 **HTTPS + ICP 备案**。

目标：菜单 / 图文把用户带到官网与下载页；不在公众号里强推微信内直接装 APK。

---

## 1. 后台域名（服务号优先）

登录 [微信公众平台](https://mp.weixin.qq.com) → 设置与开发 → 公众号设置 / 开发接口权限：

| 配置项 | 填入 |
|--------|------|
| JS 接口安全域名 | `acquireenglish.curlhairai.com` |
| 网页授权域名（若用 OAuth） | `acquireenglish.curlhairai.com` |
| 业务域名（若开原创 / 文章外链能力） | 按后台提示添加同域 |

下载校验文件放到站点**根目录**可公网访问，例如：

`https://acquireenglish.curlhairai.com/<校验文件名>.txt`

ECS 静态站路径一般为 `/opt/acquireenglish/www/`（与现有 `download.html` 同级）。

---

## 2. 自定义菜单（可直接粘贴）

路径：内容与互动 → 自定义菜单 → 用「菜单编辑」或开发者接口同步。

推荐三栏：

```
了解爱快 | 下载安装 | 联系我们
```

机器可读配置见：`docs/wechat/official-account-menu.json`。

菜单 URL：

| 按钮 | URL |
|------|-----|
| 产品介绍 | `https://acquireenglish.curlhairai.com/` |
| 安卓 / iOS 下载 | `https://acquireenglish.curlhairai.com/download.html` |
| 打开 App 引导 | `https://acquireenglish.curlhairai.com/open-app.html` |
| 加作者微信说明 | 可发图文，文案含 `youyoufairytale` |

---

## 3. 首发图文（复制即用）

**标题**：爱快英语内测：视频精听 + 碎片复习，官网可下载

**摘要**：公司主体正式号导流；Android APK / iOS TestFlight 均从官网获取。

**正文要点**：

1. 爱快英语 = 视频精听 + 复习 + 口语陪练；完整能力在 App。  
2. 官网：https://acquireenglish.curlhairai.com/  
3. 下载：https://acquireenglish.curlhairai.com/download.html  
4. 微信里点下载后，请 **··· → 在浏览器打开** 再安装；iOS 用 Safari 打开 TestFlight。  
5. 作者微信：`youyoufairytale`（注册 ID / 加群）。  
6. （可选）同主体小程序上线后：文末放小程序卡片「碎片复习入口」。

---

## 4. 与小程序 / App 账号打通

1. 公众号、小程序、移动应用都绑到同一 **微信开放平台** 账号。  
2. 用户侧用 **UnionID** 合并（API 已存 `wechat_unionid`）。  
3. 小程序登录走 `POST /api/auth/wechat/mp-login`，勿与 App 的 `sns/oauth2` code 混用。

---

## 5. 验收清单

- [ ] 菜单三项均可打开且为 https  
- [ ] 微信内打开下载页有「请用浏览器打开」提示（已有）  
- [ ] 校验文件外网可访问、无登录墙  
- [ ] 服务号模板消息 / 订阅（二期，字幕完成通知留给小程序）
