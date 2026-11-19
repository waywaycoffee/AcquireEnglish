# 腾讯云 SOE（跟读打分）配置

跟读评测与背单词「发音跟读」关卡共用同一套腾讯云智聆口语评测（SOE）凭证。

## 方式一：App 内填写（推荐个人调试）

设置 → 跟读评测 → 填写 AppId / SecretId / SecretKey → 保存。  
密钥写入本机安全存储，**不会**打进 APK 源码。

## 方式二：构建时注入（CI / 发版机）

```bash
flutter build apk --debug --flavor prod --no-pub \
  --dart-define=TENCENT_SOE_APP_ID=你的AppId \
  --dart-define=TENCENT_SOE_SECRET_ID=你的SecretId \
  --dart-define=TENCENT_SOE_SECRET_KEY=你的SecretKey
```

首次启动若本机尚未保存密钥，会把上述环境值写入安全存储。  
**切勿**把真实密钥提交到 Git。

## 验收

1. 设置页显示「密钥已保存…」  
2. 播放器跟读 / 发音评测可出分  
3. 背单词开启「发音跟读」关卡后，点「录音并云端打分」可出分并写入 FSRS  
