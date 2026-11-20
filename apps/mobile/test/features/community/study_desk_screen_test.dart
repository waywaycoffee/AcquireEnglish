import 'package:common_learn_english/features/avatar/data/avatar_models.dart';
import 'package:common_learn_english/features/authentication/presentation/auth_session.dart';
import 'package:common_learn_english/features/community/presentation/study_desk_screen.dart';
import 'package:common_learn_english/features/sync/data/acquire_api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuth extends AuthSession {
  @override
  AuthSessionState build() =>
      const AuthSessionState(accessToken: 'test', email: 'test@example.test');
  void logout() => state = const AuthSessionState();
}

class FakeDeskApi extends AcquireApiClient {
  FakeDeskApi() : super(Dio());
  @override
  Future<AvatarMeDto> cosmeticsMe() async => AvatarMeDto.empty;
  final List<({String method, String path, Map<String, dynamic>? data})>
  requests = [];
  bool paired = false;
  bool share = false;
  @override
  Future<Map<String, dynamic>> studyDeskRequest(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
  }) async {
    requests.add((method: method, path: path, data: data));
    if (method == 'PUT' && path == '/sharing')
      share = data!['share_library'] == true;
    if (path == '')
      return <String, dynamic>{
        'my_id': 1,
        'peer': paired ? <String, dynamic>{'id': 2, 'name': 'Mia'} : null,
        'invites': <dynamic>[],
        'sharing': <String, dynamic>{
          'activity': false,
          'videos': false,
          'library': share,
        },
      };
    if (path == '/activity')
      return <String, dynamic>{'summary': null, 'videos': null};
    if (path == '/library' && method == 'GET')
      throw DioException(
        requestOptions: RequestOptions(path: path),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: path),
          statusCode: 403,
          data: <String, dynamic>{'detail': '对方尚未共享收藏词库'},
        ),
      );
    return <String, dynamic>{'status': 'saved'};
  }
}

void main() {
  testWidgets('shows own desk number and does not silently upload favorites', (
    WidgetTester tester,
  ) async {
    final FakeDeskApi api = FakeDeskApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(FakeAuth.new),
          acquireApiClientProvider.overrideWithValue(api),
        ],
        child: const MaterialApp(home: StudyDeskScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('我的同桌编号：1'), findsOneWidget);
    expect(find.text('发送邀请'), findsOneWidget);
    expect(api.requests.any((r) => r.method == 'PUT'), false);
  });

  testWidgets(
    'sharing defaults off and unauthorized library is not shown as empty data',
    (WidgetTester tester) async {
      final FakeDeskApi api = FakeDeskApi()..paired = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(FakeAuth.new),
            acquireApiClientProvider.overrideWithValue(api),
          ],
          child: const MaterialApp(home: StudyDeskScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<SwitchListTile>(find.byType(SwitchListTile))
            .every((s) => !s.value),
        true,
      );
      await tester.scrollUntilVisible(
        find.text('对方尚未共享收藏词库'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('对方尚未共享收藏词库'), findsOneWidget);
      final Finder toggle = find.text('共享收藏单词（不含私有原句）');
      await tester.scrollUntilVisible(
        toggle,
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final request = api.requests.firstWhere((r) => r.path == '/sharing');
      expect(request.data, <String, dynamic>{
        'share_activity': false,
        'share_videos': false,
        'share_library': true,
      });
    },
  );

  testWidgets(
    'logout discards loaded partner and stops showing shared information',
    (WidgetTester tester) async {
      final FakeDeskApi api = FakeDeskApi()..paired = true;
      final ProviderContainer container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(FakeAuth.new),
          acquireApiClientProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: StudyDeskScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('我的同桌 · Mia'), findsOneWidget);
      (container.read(authSessionProvider.notifier) as FakeAuth).logout();
      await tester.pumpAndSettle();
      expect(find.text('我的同桌 · Mia'), findsNothing);
      expect(find.text('请先登录，再建立同桌关系。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
