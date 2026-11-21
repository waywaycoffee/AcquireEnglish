# 免费体验与产品承诺

首批上架：视频 / 阅读 / 考试各约 **5** 份永久免费入门资源（`FREE_PREVIEW_COUNT = 5`）。  
数据源：`services/api/data/free_trial_seeds.json` · `GET /api/commerce/free-trial-seeds`。

## 产品承诺

| 承诺 | 说明 |
|------|------|
| 足够免费可学 | 每个栏目始终保留不少于约 5 份永久免费入门内容 |
| 书架不改价 | 已加入书架 / 课库的免费资源不会突然变为付费（grandfather） |
| 完整小路径 | 每份免费资源都能走完「选择 → 学习 → 复习 → 进步」，不是裸下载 |
| 个人上传 | 免费用户视频与阅读自建资源均可保留 **≥15** 份（月上传额度 20，日 5） |

会员提供更丰富内容与高级服务；免费用户仍能完整体验上述闭环。

## 学习路径（免费资源）

- **视频**：字幕 → 分句精听 → 跟读 → 复习  
- **阅读**：读一章 → 查词 → 收藏难词 → 复习  
- **考试**：练习 → 解析 → 错题本 → 复习  

音视频一律走 ECS（`/media/{namespace}/…`），不打进 APK。

## 实现要点

- App：`kModuleFreePreviewCount`、`isGrandfatheredFreeReading`、`isFreeTrialBilibiliBvid`  
- API：`FREE_TIER_PROMISES`、`FREE_CAPS.upload_month=20`、`FREE_PERSONAL_LIBRARY_SLOTS=20`  
- 阅读入门文：`GET /api/reading/starter`（5 篇短文，带分句）  
