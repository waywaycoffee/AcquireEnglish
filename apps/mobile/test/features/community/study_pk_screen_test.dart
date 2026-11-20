import 'package:common_learn_english/features/authentication/presentation/auth_session.dart';
import 'package:common_learn_english/features/community/presentation/study_pk_screen.dart';
import 'package:common_learn_english/features/sync/data/acquire_api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class PkAuth extends AuthSession {
  @override
  AuthSessionState build() =>
      const AuthSessionState(accessToken: 'pk', email: 'pk@test.local');
}

class PkApi extends AcquireApiClient {
  PkApi() : super(Dio());
  int? submitted;
  @override
  Future<Map<String, dynamic>> studyPkRequest(
    String method,
    String path, {
    Map<String, dynamic>? data,
  }) async {
    if (path == '')
      return <String, dynamic>{
        'my_consent': true,
        'peer_consent': true,
        'matches': <dynamic>[
          <String, dynamic>{
            'id': 1,
            'status': 'active',
            'count': 5,
            'days': 7,
            'incoming': false,
          },
        ],
      };
    if (method == 'PUT') {
      submitted = data!['choice'] as int;
      return <String, dynamic>{'status': 'saved'};
    }
    return <String, dynamic>{
      'id': 1,
      'status': 'active',
      'count': 5,
      'result': null,
      'question': submitted == null
          ? <String, dynamic>{
              'index': 0,
              'word': 'apple',
              'choices': <String>['苹果', '香蕉', '橙子', '梨'],
              'seconds_remaining': 20,
            }
          : null,
    };
  }
}

void main() {
  testWidgets(
    'must choose before submission and waits without revealing results',
    (WidgetTester tester) async {
      final PkApi api = PkApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(PkAuth.new),
            acquireApiClientProvider.overrideWithValue(api),
          ],
          child: const MaterialApp(home: StudyPkScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('继续比赛'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('继续比赛'));
      await tester.pumpAndSettle();
      expect(find.text('apple'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '提交本题'))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('苹果'));
      await tester.tap(find.text('苹果'));
      await tester.pump();
      await tester.ensureVisible(find.text('提交本题'));
      await tester.tap(find.text('提交本题'));
      await tester.pumpAndSettle();
      expect(api.submitted, 0);
      expect(find.textContaining('等待同桌作答'), findsOneWidget);
      expect(find.textContaining('你获胜'), findsNothing);
    },
  );
}
