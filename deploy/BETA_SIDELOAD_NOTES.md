# 侧载内测说明（1A + 2A）· 2026-11-22

## 安装包

- 路径：`apps/mobile/build/app/outputs/flutter-apk/app-prod-debug.apk`
- 包名：`com.acquire.english`（prod flavor）
- 构建：`flutter build apk --debug --flavor prod --no-pub`
- 提交：见当前 `main`（含网盘书籍导入与测试对齐）

覆盖安装需与手机上已装包**签名一致**。不一致时不要卸载清数据，改用同 keystore 重签或备份后重装。

## 已知限制（告知内测用户）

1. **微信支付未开放**：会员页会提示商户未配置；请用欢迎试用（claim-welcome）与免费种子学习。
2. **网盘**：需自备百度/夸克/阿里/115 Cookie 或 token；仅导入自己网盘，不做未授权爬取。
3. **口语/数字人**：Coach 公网可用；评分或口型可能降级为粗评。
4. **设置里的「调试 · 演示数据」**：仅内测核对用，勿当作正式学习数据。
5. **商店上架未就绪**：仍为 debug 签名侧载包。

## 生产冒烟（已跑）

- health：登录真、OpenList 配置、支付未配
- 邮箱登录 + claim-welcome → credits≥50、会员有效
- free-trial-seeds：四模块各 5
- coach `/coach/api/health` ready
- 微信下单 503 明文商户提示

## 真机闭环（2026-11-22 更新）

- 设备 `23127PN0CC` 已覆盖安装成功并冷启动（无 FATAL）。
- 请人手点验：登录 → 领取试用 → 导入/播放 → 收藏复习 → 会员页「商户未配置」提示。
- 详见 [`docs/CORE_ACCEPTANCE.md`](../docs/CORE_ACCEPTANCE.md)。
