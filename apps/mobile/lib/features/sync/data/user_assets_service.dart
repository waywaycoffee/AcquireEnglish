import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final Map<String, dynamic> json =
        await _ref.read(acquireApiClientProvider).getAssets();
    return UserAssetsSnapshot.fromJson(json);
  }

  /// Deduct coach minutes. Returns remaining minutes after consume.
  Future<int> consumeCoachMinutes({
    int minutes = 1,
    String reason = 'oral_coach',
  }) async {
    await _ref.read(acquireApiClientProvider).consumeEntitlement(
      assetKind: 'coach_quota',
      assetRef: 'coach',
      quantity: minutes,
      reason: reason,
    );
    final UserAssetsSnapshot snap = await fetch();
    return snap.coachMinutes;
  }
}
