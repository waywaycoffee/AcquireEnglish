import 'dart:async';

import 'package:fluwx/fluwx.dart';

import 'wechat_auth_helper.dart';

/// Launch WeChat App payment with server-signed prepay parameters.
class WechatPayHelper {
  WechatPayHelper._();

  static final Fluwx _fluwx = Fluwx();

  static Future<bool> pay({
    required String appId,
    required String partnerId,
    required String prepayId,
    required String packageValue,
    required String nonceStr,
    required int timestamp,
    required String sign,
    String signType = 'RSA',
    Duration timeout = const Duration(minutes: 3),
  }) async {
    if (appId.trim().isEmpty) throw StateError('服务端未配置微信支付 AppID');
    final bool registered = await _fluwx.registerApi(
      appId: appId.trim(),
      universalLink: WechatAuthHelper.universalLink,
    );
    if (!registered) throw StateError('微信支付 SDK 注册失败');
    final bool installed = await _fluwx.isWeChatInstalled;
    if (!installed) {
      throw StateError('未安装微信，无法完成支付。');
    }

    final Completer<bool> completer = Completer<bool>();
    late final FluwxCancelable cancelable;
    cancelable = _fluwx.addSubscriber((WeChatResponse response) {
      if (response is! WeChatPaymentResponse) {
        return;
      }
      if (completer.isCompleted) {
        return;
      }
      if (response.errCode == 0) {
        completer.complete(true);
      } else if (response.errCode == -2) {
        completer.completeError(StateError('已取消微信支付'));
      } else {
        completer.completeError(
          StateError(
            '微信支付失败（${response.errCode} ${response.errStr ?? ''}）'.trim(),
          ),
        );
      }
    });

    try {
      final bool started = await _fluwx.pay(
        which: Payment(
          appId: appId,
          partnerId: partnerId,
          prepayId: prepayId,
          packageValue: packageValue,
          nonceStr: nonceStr,
          timestamp: timestamp,
          sign: sign,
          signType: signType,
        ),
      );
      if (!started) {
        throw StateError('无法拉起微信支付，请确认已安装微信。');
      }
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw StateError('微信支付超时，请稍后在订单中确认。'),
      );
    } finally {
      cancelable.cancel();
    }
  }
}
