# 百度网盘官方 OAuth（扫码 / 账号授权）

普通用户在 App 点「百度扫码 / 账号授权」，浏览器打开百度授权页（可扫码），回调后服务端用 `code` 换 `refresh_token`，再写入 OpenList 挂载。Cookie 粘贴仍保留为「高级」方式。

## 1. 百度开放平台

1. 打开 [百度网盘开放平台](https://pan.baidu.com/union/console/applist) 创建应用  
2. 拿到 **AppKey** / **SecretKey**  
3. 安全设置里配置授权回调地址（必须完全一致）：

```text
https://acquireenglish.curlhairai.com/api/netdisk/baidu/oauth/callback
```

4. 权限勾选网盘相关 scope（`basic,netdisk`）

## 2. API `.env`

```bash
BAIDU_NETDISK_APP_KEY=你的AppKey
BAIDU_NETDISK_APP_SECRET=你的SecretKey
BAIDU_NETDISK_REDIRECT_URI=https://acquireenglish.curlhairai.com/api/netdisk/baidu/oauth/callback
```

然后：

```bash
systemctl restart acquireenglish-api
```

`GET /api/netdisk/status` 中 `baidu_oauth_configured: true` 时，App 会显示扫码入口。

## 3. 用户流程

1. App 登录爱快账号 → 网盘导入 → 百度  
2. 点「百度扫码 / 账号授权」→ 系统浏览器打开百度页  
3. 用百度 App 扫码或账号密码授权  
4. 看到「授权成功」页后回到爱快 App（自动轮询绑定状态）  
5. 浏览自己网盘目录并导入视频  

未配置 AppKey 时仍可用「高级：粘贴 Cookie」。
