import 'package:common_learn_english/features/authentication/presentation/auth_session.dart';
import 'package:common_learn_english/features/community/data/community_models.dart';
import 'package:common_learn_english/features/community/presentation/public_learning_card_screen.dart';
import 'package:common_learn_english/features/community/presentation/publish_learning_result_screen.dart';
import 'package:common_learn_english/features/sync/data/acquire_api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class ShareAuth extends AuthSession {
  @override
  AuthSessionState build() =>
      const AuthSessionState(accessToken: 'share', email: 'share@test');
}

class ShareApi extends AcquireApiClient {
  ShareApi() : super(Dio());
  int published = 0;
  @override
  Future<Map<String, dynamic>> learningCardRequest(
    String method,
    String path, {
    Map<String, dynamic>? data,
  }) async => {
    'token': 'test',
    'title': '公开课程',
    'author': 'Mia',
    'expression': 'Take your time.',
    'meaning': '慢慢来',
    'watch_url': 'https://www.bilibili.com/video/BV1GJ411x7h7',
  };
  @override
  Future<CommunityPostDto> createCommunityPost({
    required String kind,
    String title = '',
    String body = '',
    String? linkUrl,
    String? linkTitle,
    String? linkCover,
    String? embedWord,
    double? embedTimestampSec,
    String? oralAudioUrl,
    String? oralBookId,
    String? oralKey,
    String? transcript,
    String? referenceLine,
    Map<String, dynamic>? meta,
  }) async {
    published++;
    return CommunityPostDto(
      id: 1,
      kind: kind,
      title: title,
      body: body,
      likeCount: 0,
      likedByMe: false,
      authorName: '我',
      authorId: 1,
      createdAt: DateTime.now(),
    );
  }
}

void main() {
  testWidgets(
    'public card can be practiced before login and does not reveal meaning early',
    (WidgetTester tester) async {
      final ShareApi api = ShareApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [acquireApiClientProvider.overrideWithValue(api)],
          child: const MaterialApp(
            home: PublicLearningCardScreen(token: 'test'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Take your time.'), findsOneWidget);
      expect(find.text('慢慢来'), findsNothing);
      await tester.tap(find.text('我想好了，核对释义'));
      await tester.pump();
      expect(find.text('慢慢来'), findsOneWidget);
      expect(api.published, 0);
    },
  );
  testWidgets(
    'result defaults private and publishing requires explicit final confirmation',
    (WidgetTester tester) async {
      final ShareApi api = ShareApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(ShareAuth.new),
            acquireApiClientProvider.overrideWithValue(api),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (BuildContext context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const PublishLearningResultScreen(
                        initialText: '完成5条复习',
                      ),
                    ),
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
      expect(api.published, 0);
      await tester.tap(find.text('公开发布到社区'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        true,
      );
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();
      expect(api.published, 0);
      expect(find.text('确认公开发布'), findsOneWidget);
      await tester.tap(find.text('确认发布'));
      await tester.pumpAndSettle();
      expect(api.published, 1);
    },
  );
}
