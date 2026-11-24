# 卡通形象（方案 2）

数字人默认使用本地 **3×3 atlas**（`assets/img/digital_human/{id}-cartoon.webp`）做口型与听/想/鼓励姿态，不依赖 GPU LiveTalking。

## 布局

| 索引 | 含义 |
|------|------|
| 0–4 | 口型：closed / open / wide / rounded / teeth |
| 5 | idle 眨眼 |
| 6 | listening |
| 7 | thinking |
| 8 | encouraging |

说话时由 `CoachAnimationTimeline.estimate(text, duration)` 驱动口型；对话仍是按住说话（半双工）。

## 开关

设置项 `cartoonDigitalHuman`（默认开）。关闭且开启 LiveTalking 映射时，可走真人 WebRTC 唇形（方案 3）。

挑选器仍用肖像 `assets/img/digital_human/{id}.webp`；开聊后舞台切到 cartoon atlas。
