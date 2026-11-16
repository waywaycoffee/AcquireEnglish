import 'dart:io';

import 'package:flutter/services.dart';
import 'package:fluwx/fluwx.dart';
import 'package:share_plus/share_plus.dart';

import 'wechat_auth_helper.dart';

enum WechatShareChannel {
  moments,
  systemFallback,
}

class WechatShareOutcome {
  const WechatShareOutcome({
    required this.channel,
    required this.success,
    this.errorMessage,
  });

  final WechatShareChannel channel;
  final bool success;
  final String? errorMessage;

  bool get countsForMomentsPoints =>
      success && channel == WechatShareChannel.moments;
}

/// Share local video/file to WeChat Moments, with system share fallback.
class WechatShareHelper {
  WechatShareHelper._();

  static final Fluwx _fluwx = Fluwx();
  static const MethodChannel _channel = MethodChannel(
    'com.shadowing.english/audio_tools',
  );

  static Future<WechatShareOutcome> shareVideoFile({
    required String filePath,
    String title = '我的配音练习',
    String description = '爱快英语 · 趣配音',
  }) async {
    final File file = File(filePath);
    if (!file.existsSync()) {
      return const WechatShareOutcome(
        channel: WechatShareChannel.systemFallback,
        success: false,
        errorMessage: '分享文件不存在。',
      );
    }

    // Prefer Android Moments intent (fluwx file model does not support timeline).
    if (Platform.isAndroid) {
      try {
        final bool? started = await _channel.invokeMethod<bool>(
          'shareVideoToMoments',
          <String, Object?>{'path': filePath, 'title': title},
        );
        if (started == true) {
          return const WechatShareOutcome(
            channel: WechatShareChannel.moments,
            success: true,
          );
        }
      } catch (_) {}
    }

    if (WechatAuthHelper.isConfigured) {
      try {
        await WechatAuthHelper.ensureRegistered();
        final bool installed = await _fluwx.isWeChatInstalled;
        if (installed) {
          // Session file share as secondary path (not Moments).
          final bool started = await _fluwx.share(
            WeChatShareFileModel(
              WeChatFile.file(file, suffix: '.mp4'),
              title: title,
              description: description,
              scene: WeChatScene.session,
            ),
          );
          if (started) {
            return const WechatShareOutcome(
              channel: WechatShareChannel.systemFallback,
              success: true,
              errorMessage: '已打开微信好友分享（朋友圈需 Android 直达）。不计朋友圈积分。',
            );
          }
        }
      } catch (_) {}
    }

    try {
      final ShareResult result = await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(filePath)],
          text: '$title\n$description',
        ),
      );
      return WechatShareOutcome(
        channel: WechatShareChannel.systemFallback,
        success: result.status != ShareResultStatus.dismissed,
        errorMessage: result.status == ShareResultStatus.dismissed
            ? '已取消分享'
            : '已用系统分享（选择微信朋友圈后可在下次接入直达领取积分）',
      );
    } catch (error) {
      return WechatShareOutcome(
        channel: WechatShareChannel.systemFallback,
        success: false,
        errorMessage: '$error',
      );
    }
  }
}
