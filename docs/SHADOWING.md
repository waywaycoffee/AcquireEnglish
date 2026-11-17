# 跟读与配音

字幕句子显示已保存的「我的录音」；字幕时间和文本必须与录音一致。
录音先保存，再评分。配置设置里的腾讯云跟读评测密钥后，自动请求发音评测，显示总分、准确度、流利度、完整度、逐词反馈。未配置或评测失败时尝试本地 Whisper 和 Voice 服务的内容匹配反馈；所有识别均失败则保留录音并显示暂未评分。

配音回放需要本地视频、人声分离服务，以及设备原生混音或桌面 FFmpeg。

启动 tools/stem_separation 的服务（安装 Demucs），构建应用时指定：

```
--dart-define=STEM_SEPARATION_URL=http://你的服务器:8790
```

服务分离失败返回 503，不再用中置声道衰减伪装去人声。新缓存名为 separated_background_v2.wav，避免复用旧衰减缓存。

配音回放先合成环境音与句子录音，再播放视频并静音其原轨。视频暂停同步暂停配音；进度偏差超过 180ms 时纠正；倍速随视频设置更新；离开合成范围恢复原轨。未录制的区间只有环境音。环境音保留效果取决于分离模型与素材。

验证：运行 pronunciation_assessment_test、tencent_pronunciation_service_test、shadow_word_overlap_test、dub_take_test。真实云评测、Demucs 分离质量和移动端同步效果需要配置服务后在设备上验收。

重录会保留历史版本；字幕句子旁的历史按钮可选择用于配音的版本，评分更新保持同一录音版本。新增 dub_store_test 验证持久化与版本选择。

## 2026-11-17 自动化验收

- 评分、内容匹配、录音模型、版本持久化、字幕列表界面测试通过。
- `flutter build apk --debug --flavor dev --no-pub` 成功。
- 安装包：apps/mobile/build/app/outputs/flutter-apk/app-dev-debug.apk。
- 静态检查无 error/warning（本轮检查的存储、导出、跟读、录音按钮文件），仍有 info 级规范提示。
- 本机检测到 Android 真机、iOS 模拟器和 FFmpeg；未安装 Demucs。尚未完成真实云评测、人声分离音质、设备录音与同步回放验收。
