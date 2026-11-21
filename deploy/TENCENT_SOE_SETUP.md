# 腾讯云 SOE（口语打分）接入

项目里有两条路径，密钥**不要**提交到 Git。

| 路径 | 用途 | 配置位置 |
|------|------|----------|
| App 本机密钥 | 播放器跟读、背词本机打分 | App 设置 / `--dart-define` |
| API 服务端密钥 | 学习模块云端评测 `/api/pronunciation/*` | ECS `services/api/.env` |

---

## 1. 在腾讯云开通

1. 开通智聆口语评测（新版）：  
   https://console.cloud.tencent.com/soenew  
2. 创建 API 密钥（SecretId / SecretKey）：  
   https://console.cloud.tencent.com/cam/capi  
3. 账号 AppId：控制台右上角账号信息里的 APPID（App 跟读 SDK 需要）。

---

## 2. App 本机接入（跟读评测）

### 方式 A：设置页填写（个人调试推荐）

1. 打开 App → **设置 → 跟读评测**  
2. 填写 **AppId / SecretId / SecretKey**  
3. 点 **保存密钥**（写入系统安全存储，不进 APK 源码）  
4. 状态应显示「密钥已保存在…」

### 方式 B：构建时注入（CI / 发版机）

```bash
flutter build apk --debug --flavor prod --no-pub \
  --dart-define=TENCENT_SOE_APP_ID=你的AppId \
  --dart-define=TENCENT_SOE_SECRET_ID=你的SecretId \
  --dart-define=TENCENT_SOE_SECRET_KEY=你的SecretKey
```

首次启动若本机尚未保存密钥，会把上述值写入安全存储。

### 验收（App）

1. 设置页显示密钥已保存  
2. 播放器跟读 / 发音评测可出分  
3. 背单词「发音跟读」关卡可云端打分并写入复习

---

## 3. API 服务端接入（学习模块云端评测）

密钥只放在 ECS，App **不要**再塞一套服务端 Secret。

### 写入 `.env`

在 ECS `/opt/acquireenglish/services/api/.env`（或本地 `services/api/.env`）增加：

```bash
TENCENT_SOE_SECRET_ID=你的SecretId
TENCENT_SOE_SECRET_KEY=你的SecretKey
```

本地模板见 `services/api/.env.example`。服务端评测签名不需要把 AppId 写进 `.env`（用 SecretId/Key 调 `soe.tencentcloudapi.com`）。

### 部署并重启

```bash
cd services/api && ./deploy.sh
# 或在 ECS：
systemctl restart acquireenglish-api
```

### 验收（API）

登录后：

```bash
# 是否已配置
curl -sS -H "Authorization: Bearer $TOKEN" \
  https://acquireenglish.curlhairai.com/api/pronunciation/status

# 期望：{"configured":true,"provider":"tencent-soe"}
```

未配置时 `configured` 为 `false`；调用 `/api/pronunciation/evaluate` 会返回 503。

---

## 4. 安全注意

- 真实密钥禁止写入仓库、Issue、聊天记录  
- App 侧用安全存储；服务端只用 ECS `.env` + 文件权限  
- 轮换密钥后：更新设置页或 ECS `.env` 并重启 API  
