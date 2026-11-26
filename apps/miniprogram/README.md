# AcquireEnglish 微信小程序 v1

产品说明见 `docs/product/miniprogram-v1.md`。  
公众号挂官网见 `docs/wechat/official-account.md`。

## 本仓库进度（落地顺序 §4.1）

- [x] 工程骨架：首页 / 复习 / 预约 / 阅读 / 我的 + 口语子页  
- [x] 微信登录客户端（`POST /api/auth/wechat/mp-login`）  
- [x] 打开 App 引导（复制官网 `open-app.html` / 下载页）  
- [ ] 微信开发者工具填入正式 AppID，配置服务器域名  
- [ ] 预约列表 API、云端 FSRS、订阅消息  

## 本地打开

1. 安装[微信开发者工具](https://developers.weixin.qq.com/miniprogram/dev/devtools/download.html)  
2. 导入目录：`apps/miniprogram`  
3. 将 `project.config.json` 里 `appid` 换成公司主体小程序 AppID  
4. 小程序后台 → 开发设置 → **服务器域名** 加入：  
   - `request` 合法域名：`https://acquireenglish.curlhairai.com`  
5. 与 App / 公众号一并绑定到同一**微信开放平台**，以便 UnionID 打通账号  

开发阶段可在详情里勾选「不校验合法域名」。

## 环境变量（API）

ECS / `.env`：

```
WECHAT_MP_APP_ID=小程序AppID
WECHAT_MP_APP_SECRET=小程序AppSecret
```

未配置时，非生产环境可走 mock（`code` 当作稳定 openid）。
