# 电视横屏学习 v1（A 档）

对照设计：`apps/mobile/design/tv_study_landscape.pen`（美剧精听 · 横屏 · 双语字幕）。

## 范围

- 入口：设置 → **电视横屏学习**，或路由 `/tv`
- 播放：`/episodes/:id?tv=1` → `PadLandscapePlayerScreen(tvMode: true)`
- 锁定横屏；底部上一句 / 播放暂停 / 下一句 / 倍速 / 单句循环 / 跟读（D-pad 焦点）
- 右侧字幕区深色底，匹配 TV 稿

## 非目标（本版不做）

- Android TV Leanback 桌面 / 应用商店上架
- 数字人 / 听写 / 背单词 TV 专用页（仍引导用手机）

## 验收

1. 手机横放或平板进入 `/tv`，大卡片可方向键聚焦（外接键盘）  
2. 点「继续学习」进入横屏精听，返回后回竖屏壳  
3. 与设计稿同构：左视频 + 底控件 + 右字幕  

## 后续

B 档：`LEANBACK_LAUNCHER`、原生遥控器焦点测试矩阵、可选独立 `tv` flavor。
