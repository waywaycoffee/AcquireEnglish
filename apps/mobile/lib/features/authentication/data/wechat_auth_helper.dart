import 'dart:async';

import 'package:fluwx/fluwx.dart';

/// WeChat OAuth via fluwx. Falls back to mock code when AppID is unset.
class WechatAuthHelper {
  WechatAuthHelper._();

  static const String appId = String.fromEnvironment('WECHAT_APP_ID');
  static const String universalLink = String.fromEnvironment(
    'WECHAT_UNIVERSAL_LINK',
    defaultValue: 'https://acquireenglish.curlhairai.com/wechat/',
  );

  static final Fluwx _fluwx = Fluwx();
  static bool _registered = false;

  static bool get isConfigured => appId.trim().isNotEmpty;

  static Future<void> ensureRegistered() async {
    if (!isConfigured || _registered) {
      return;
    }
    final bool ok = await _fluwx.registerApi(
      appId: appId.trim(),
      universalLink: universalLink.trim().isEmpty ? null : universalLink.trim(),
    );
    if (!ok) {
      throw StateError('微信 SDK 注册失败，请检查 AppID / Universal Link。');
    }
    _registered = true;
  }

  /// Returns WeChat auth `code` for the backend `/api/auth/wechat/login`.
  static Future<String> requestAuthCode({
    Duration timeout = const Duration(minutes: 2),
  }) async {
    await ensureRegistered();
    final bool installed = await _fluwx.isWeChatInstalled;
    if (!installed) {
      throw StateError('未安装微信，无法完成授权登录。');
    }

    final Completer<String> completer = Completer<String>();
    late final FluwxCancelable cancelable;
    cancelable = _fluwx.addSubscriber((WeChatResponse response) {
      if (response is! WeChatAuthResponse) {
        return;
      }
      if (completer.isCompleted) {
        return;
      }
      if (response.errCode == 0 &&
          response.code != null &&
          response.code!.trim().isNotEmpty) {
        completer.complete(response.code!.trim());
      } else if (response.errCode == -2) {
        completer.completeError(StateError('已取消微信授权'));
      } else {
        completer.completeError(
          StateError(
            '微信授权失败（${response.errCode} ${response.errStr ?? ''}）'.trim(),
          ),
        );
      }
    });

    try {
      final bool started = await _fluwx.authBy(
        which: NormalAuth(scope: 'snsapi_userinfo', state: 'acquire_login'),
      );
      if (!started) {
        throw StateError('无法拉起微信授权，请确认已安装微信。');
      }
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw StateError('微信授权超时，请重试。'),
      );
    } finally {
      cancelable.cancel();
    }
  }
}
