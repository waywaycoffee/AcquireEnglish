import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/data/wechat_pay_helper.dart';
import 'acquire_api_client.dart';

class UserAssetsSnapshot {
  const UserAssetsSnapshot({
    required this.balanceCredits,
    required this.coachMinutes,
    required this.activeMembership,
    required this.vocabCount,
    required this.linkCourseCount,
  });

  final int balanceCredits;
  final int coachMinutes;
  final String? activeMembership;
  final int vocabCount;
  final int linkCourseCount;

  factory UserAssetsSnapshot.fromJson(Map<String, dynamic> json) {
    int coach = 0;
    final Object? ents = json['entitlements'];
    if (ents is List) {
      for (final Object? row in ents) {
        if (row is! Map) {
          continue;
        }
        if ('${row['asset_kind']}' != 'coach_quota') {
          continue;
        }
        if ('${row['status']}' != 'active') {
          continue;
        }
        coach += (row['quantity'] as num?)?.toInt() ?? 0;
      }
    }
    final Map<String, dynamic> wallet =
        (json['wallet'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return UserAssetsSnapshot(
      balanceCredits: (wallet['balance_credits'] as num?)?.toInt() ?? 0,
      coachMinutes: coach,
      activeMembership: json['active_membership'] as String?,
      vocabCount: (json['vocab_count'] as num?)?.toInt() ?? 0,
      linkCourseCount: (json['link_course_count'] as num?)?.toInt() ?? 0,
    );
  }
}

final Provider<UserAssetsService> userAssetsServiceProvider =
    Provider<UserAssetsService>((Ref ref) => UserAssetsService(ref));

class UserAssetsService {
  UserAssetsService(this._ref);

  final Ref _ref;

  Future<UserAssetsSnapshot> fetch() async {
    final Map<String, dynamic> json = await _ref
        .read(acquireApiClientProvider)
        .getAssets();
    return UserAssetsSnapshot.fromJson(json);
  }

  /// Deduct coach minutes. Returns remaining minutes after consume.
  Future<int> consumeCoachMinutes({
    int minutes = 1,
    String reason = 'oral_coach',
  }) async {
    await _ref
        .read(acquireApiClientProvider)
        .consumeEntitlement(
          assetKind: 'coach_quota',
          assetRef: 'coach',
          quantity: minutes,
          reason: reason,
        );
    final UserAssetsSnapshot snap = await fetch();
    return snap.coachMinutes;
  }

  /// Create an order and launch WeChat App payment.
  ///
  /// Requires server merchant credentials (`wechat_pay_configured=true`).
  Future<Map<String, dynamic>> purchaseWithWechat({
    required String skuCode,
    int quantity = 1,
    int? couponId,
    List<String>? selectedModules,
  }) async {
    final AcquireApiClient api = _ref.read(acquireApiClientProvider);
    final Map<String, dynamic> order = await api.createAssetOrder(
      items: <({String skuCode, int quantity})>[
        (skuCode: skuCode, quantity: quantity),
      ],
      provider: 'wechat',
      couponId: couponId,
      selectedModules: selectedModules,
    );
    final int orderId = (order['id'] as num).toInt();
    final Map<String, dynamic> prepay = await api.createWechatPrepay(
      orderId: orderId,
    );
    await WechatPayHelper.pay(
      appId: '${prepay['app_id']}',
      partnerId: '${prepay['partner_id']}',
      prepayId: '${prepay['prepay_id']}',
      packageValue: '${prepay['package_value']}',
      nonceStr: '${prepay['nonce_str']}',
      timestamp: (prepay['timestamp'] as num).toInt(),
      sign: '${prepay['sign']}',
      signType: '${prepay['sign_type'] ?? 'RSA'}',
    );
    return order;
  }

  /// Non-production mock fulfillment when WeChat MCH is not configured.
  Future<Map<String, dynamic>> purchaseWithMock({
    required String skuCode,
    int quantity = 1,
    int? couponId,
    List<String>? selectedModules,
  }) async {
    final AcquireApiClient api = _ref.read(acquireApiClientProvider);
    final Map<String, dynamic> order = await api.createAssetOrder(
      items: <({String skuCode, int quantity})>[
        (skuCode: skuCode, quantity: quantity),
      ],
      provider: 'mock',
      couponId: couponId,
      selectedModules: selectedModules,
    );
    final int orderId = (order['id'] as num).toInt();
    return api.markAssetOrderPaid(orderId: orderId);
  }
}
