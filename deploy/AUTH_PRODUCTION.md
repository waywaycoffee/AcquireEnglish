# 生产环境：手机验证码 / 微信登录配置

App 与 API 已支持「未注册自动建号」。生产要关掉 mock，填入真实密钥。

## 当前生产探针

```bash
curl -fsS https://acquireenglish.curlhairai.com/api/health
```

目标：

| 字段 | 目标值 |
|------|--------|
| `auth_sms_mock` | `false` |
| `auth_sms_provider` | `aliyun`（或 `webhook`） |
| `auth_email_mock` | `false` |
| `auth_email_provider` | `smtp`（或 `webhook`） |
| `auth_wechat_mock` | `false` |
| `auth_wechat_configured` | `true` |
| `wechat_pay_configured` | `true`（需商户号；见下） |

### 生产状态（2026-11-21）

| 能力 | 状态 | 说明 |
|------|------|------|
| 短信登录 | **就绪** | `auth_sms_mock=false` · Aliyun |
| 邮箱注册 | **就绪** | SMTP 已配 |
| 微信登录 | **就绪** | `auth_wechat_configured=true` · Open Platform AppID/Secret 已写入 ECS `.env` |
| 微信支付 | **未就绪** | `wechat_pay_configured=false` · `WECHAT_MCH_*` 商户凭证为空。**勿编造密钥**；补齐商户号/证书序列号/APIv3 Key/私钥后重启 API。生产下单拒绝 `mock`/`manual`，未配商户时 `provider=wechat` 返回 503 明文提示。 |

> 生产机通过 systemd `PRODUCTION_MODE=true` 禁用 email/wechat mock。  
> 未配置 SMTP/Webhook 时，邮箱注册接口会返回「邮箱注册暂未开放」。

## 1. 阿里云短信

1. 开通 [短信服务](https://dysmsapi.console.aliyun.com/)
2. 申请签名（如「爱快英语」）与验证码模板，模板变量名必须为 `code`
3. 创建 AccessKey（**必须** RAM 子账号，仅 `AliyunDysmsFullAccess`；不要用主账号 AK，也不要用同一把去拉 BSS 账单）
4. 在 API 机 `/opt/acquireenglish/services/api/.env` 写入：

```bash
AUTH_SMS_MOCK=false
ALIYUN_SMS_ACCESS_KEY_ID=...
ALIYUN_SMS_ACCESS_KEY_SECRET=...
ALIYUN_SMS_SIGN_NAME=爱快英语
ALIYUN_SMS_TEMPLATE_CODE=SMS_xxxxxx
ALIYUN_SMS_REGION=cn-hangzhou
# 平台账单另配（可选，BSS 只读 RAM）；默认不查余额：
# ALIYUN_BSS_ACCESS_KEY_ID=...
# ALIYUN_BSS_ACCESS_KEY_SECRET=...
# ALIYUN_BSS_QUERY_BALANCE=0
```

5. 重启 API 服务，再测：

```bash
curl -fsS -X POST https://acquireenglish.curlhairai.com/api/auth/sms/send \
  -H 'Content-Type: application/json' \
  -d '{"phone":"你的手机号"}'
# 应无 debug_code；真机会收到短信
```

## 2. 邮箱注册（阿里云邮件推送 SMTP）

`PRODUCTION_MODE=true` 时不会使用 `AUTH_EMAIL_MOCK`。必须配置真实发信：

```bash
AUTH_EMAIL_MOCK=false
SMTP_HOST=smtpdm.aliyun.com
SMTP_PORT=465
SMTP_USE_SSL=true
SMTP_USE_TLS=false
SMTP_USER=你的发信地址@已验证域名
SMTP_PASSWORD=SMTP密码
SMTP_FROM=你的发信地址@已验证域名
```

当前生产复用与 CurlHair 相同的阿里云邮件推送发信账号（`smtpdm.aliyun.com:465`）。  
发信域名须在阿里云邮件推送控制台完成验证；`SMTP_FROM` 必须是已通过验证的发信地址。

验证：

```bash
curl -fsS https://acquireenglish.curlhairai.com/api/health
# auth_email_provider 应为 smtp

curl -fsS -X POST https://acquireenglish.curlhairai.com/api/auth/email/send \
  -H 'Content-Type: application/json' \
  -d '{"email":"你的邮箱"}'
# 应返回 ok:true 且无 debug_code；邮箱收到验证码后再调 /api/auth/register
```

## 3. 微信开放平台（App 登录 / 自动注册）

1. [微信开放平台](https://open.weixin.qq.com/) 创建移动应用，拿到 **AppID / AppSecret**
2. Android：包名 `com.acquire.english`，应用签名填证书 **MD5**（小写无冒号）  
   当前 debug 签名 MD5：`d5a921c1234aef0b8eb6d4871f80e988`
3. iOS：配置 Bundle ID + Universal Link  
   默认：`https://acquireenglish.curlhairai.com/wechat/`
4. API `.env`：

```bash
AUTH_WECHAT_MOCK=false
WECHAT_APP_ID=wx........
WECHAT_APP_SECRET=...
```

5. App 正式包编译（App 只需要 AppID，Secret 留在服务端）：

```bash
flutter build apk --debug --flavor prod --dart-define-from-file=.env
# 或
flutter build apk --dart-define=WECHAT_APP_ID=wx........ \
  --dart-define=WECHAT_UNIVERSAL_LINK=https://acquireenglish.curlhairai.com/wechat/
```

未配置 AppID 时，App 仍走开发 mock code（仅联调）。  
首次微信授权成功会自动建号并发放试用资产（见下节）。

## 3b. 微信支付（App 支付）

Open Platform 的 AppID/AppSecret **不够**完成收款，还需微信支付商户平台：

```bash
WECHAT_MCH_ID=商户号
WECHAT_MCH_SERIAL_NO=商户API证书序列号
WECHAT_MCH_API_V3_KEY=APIv3密钥(32位)
WECHAT_MCH_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----...  # 或 apiclient_key.pem 绝对路径
WECHAT_PAY_NOTIFY_URL=https://acquireenglish.curlhairai.com/api/assets/wechat/notify
```

API：

- `POST /api/assets/orders`（`provider=wechat`）创建待支付订单
- `POST /api/assets/orders/{id}/wechat-prepay` 返回 App 调起参数
- `POST /api/assets/wechat/notify` 支付结果回调 → 自动履约发权益

健康检查字段：`wechat_pay_configured=true` 表示商户凭证齐全。

## 4. 新用户试用资产

首次邮箱 / 手机 / 微信注册成功后会自动发放：

- Pro 会员试用 **7 天**
- 口语陪练配额 **10 分钟**（30 天有效）
- 钱包积分 **50**

可用 `GET /api/assets` 验证。

## 5. 服务器一键写入示例

在 ECS 上（勿把真实密钥提交进 Git）：

```bash
sudo bash /opt/acquireenglish/deploy/configure_auth_env.sh
# 按提示粘贴密钥后 systemctl restart acquireenglish-api
```

仓库内模板：[`configure_auth_env.sh`](configure_auth_env.sh)。
