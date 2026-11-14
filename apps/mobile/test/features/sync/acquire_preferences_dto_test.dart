import 'package:common_learn_english/features/sync/data/acquire_api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preferences toJson round-trips has_bilibili_cookie flags', () {
    const AcquirePreferencesDto prefs = AcquirePreferencesDto(
      level: 'B1',
      tags: <String>['slow'],
      dailyQuota: 3,
      notifyDailyFeed: false,
      hasBilibiliCookie: true,
      hasAsrApiKey: true,
    );
    final AcquirePreferencesDto restored = AcquirePreferencesDto.fromJson(
      prefs.toJson(),
    );
    expect(restored.hasBilibiliCookie, isTrue);
    expect(restored.hasAsrApiKey, isTrue);
    expect(restored.dailyQuota, 3);
    expect(restored.notifyDailyFeed, isFalse);
  });

  test('preferences toJson omits write-only secrets unless set', () {
    final Map<String, dynamic> bare = const AcquirePreferencesDto(
      hasBilibiliCookie: true,
    ).toJson();
    expect(bare.containsKey('bilibili_cookie'), isFalse);
    expect(bare['has_bilibili_cookie'], isTrue);

    final Map<String, dynamic> withCookie = const AcquirePreferencesDto(
      bilibiliCookie: 'SESSDATA=x',
    ).toJson();
    expect(withCookie['bilibili_cookie'], 'SESSDATA=x');
  });

  test('preferences fromJson accepts num daily_quota', () {
    final AcquirePreferencesDto prefs = AcquirePreferencesDto.fromJson(
      <String, dynamic>{
        'level': 'A2',
        'tags': <String>['daily'],
        'daily_quota': 2.0,
        'notify_daily_feed': true,
      },
    );
    expect(prefs.dailyQuota, 2);
  });
}
