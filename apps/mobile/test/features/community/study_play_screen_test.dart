import 'package:common_learn_english/features/authentication/presentation/auth_session.dart';
import 'package:common_learn_english/features/avatar/data/avatar_models.dart';
import 'package:common_learn_english/features/community/presentation/study_play_screen.dart';
import 'package:common_learn_english/features/sync/data/acquire_api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class PlayAuth extends AuthSession {
  @override
  AuthSessionState build() =>
      const AuthSessionState(accessToken: 'play', email: 'play@test');
}

class PlayApi extends AcquireApiClient {
  PlayApi() : super(Dio());
  bool claimed = false;
  int claims = 0;
  @override
  Future<AvatarMeDto> cosmeticsMe() async => AvatarMeDto.empty;
  @override
  Future<Map<String, dynamic>> studyPlayRequest(
    String method,
    String path, {
    Map<String, dynamic>? data,
  }) async {
    if (path == '/checkin' && method == 'POST') {
      claims++;
      claimed = true;
      return {'awarded': true};
    }
    if (path == '/checkin')
      return {
        'day': '2026-11-20',
        'seconds': 600,
        'review_count': 5,
        'review_target': 5,
        'eligible': true,
        'claimed': claimed,
        'history': <String>[],
        'rule': '完成学习后打卡',
      };
    if (path == '/challenges') return {'challenges': <dynamic>[]};
    if (path == '/battles')
      return {
        'my_id': 1,
        'peer_id': 2,
        'can_battle': true,
        'matches': <dynamic>[
          {'id': 1, 'status': 'completed', 'incoming': false},
        ],
      };
    return {
      'id': 1,
      'my_id': 1,
      'peer_id': 2,
      'status': 'completed',
      'result': {
        'winner': 1,
        'avatars': <String, dynamic>{},
        'stats': {
          '1': {'minutes': 10, 'words': 5, 'days': 1, 'attack': 12, 'armor': 3},
          '2': {'minutes': 8, 'words': 4, 'days': 1, 'attack': 11, 'armor': 3},
        },
        'steps': <dynamic>[
          {
            'round': 1,
            'attacker': 1,
            'target': 2,
            'action': '专注一击',
            'damage': 10,
            'health': {'1': 100, '2': 90},
            'text': '学员1出手，学员2扣血10',
          },
          {
            'round': 1,
            'attacker': 2,
            'target': 1,
            'action': '反击',
            'damage': 8,
            'health': {'1': 92, '2': 90},
            'text': '学员2出手，学员1扣血8',
          },
        ],
      },
    };
  }
}

void main() {
  testWidgets('check-in can only be claimed once through the UI', (
    WidgetTester tester,
  ) async {
    final PlayApi api = PlayApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(PlayAuth.new),
          acquireApiClientProvider.overrideWithValue(api),
        ],
        child: const MaterialApp(home: StudyPlayScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('确认打卡'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('确认打卡'));
    await tester.pumpAndSettle();
    expect(api.claims, 1);
    expect(find.text('今日已打卡'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '今日已打卡'))
          .onPressed,
      isNull,
    );
  });
  testWidgets(
    'battle replays stored damage and skip produces the stored result',
    (WidgetTester tester) async {
      final PlayApi api = PlayApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(PlayAuth.new),
            acquireApiClientProvider.overrideWithValue(api),
          ],
          child: const MaterialApp(home: StudyPlayScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('播放战报'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('播放战报'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('播放战报'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('播放 / 重播动画'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('播放 / 重播动画'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('播放 / 重播动画'));
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('HP 90 / 100'), findsOneWidget);
      await tester.ensureVisible(find.text('跳过动画'));
      await tester.tap(find.text('跳过动画'));
      await tester.pumpAndSettle();
      expect(find.text('HP 92 / 100'), findsOneWidget);
      expect(find.text('本场你获胜'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
