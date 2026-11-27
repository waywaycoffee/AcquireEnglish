import 'package:common_learn_english/features/home/presentation/widgets/today_activity_card.dart';
import 'package:common_learn_english/features/words/domain/syllabus_book.dart';
import 'package:common_learn_english/features/words/presentation/syllabus_books_provider.dart';
import 'package:common_learn_english/features/words/presentation/vocabulary_placement_provider.dart';
import 'package:common_learn_english/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _UntestedPlacement extends VocabularyPlacement {
  @override
  PlacementRow build() => <String, dynamic>{};
}

class _SelectedBooks extends SyllabusBooksNotifier {
  @override
  SyllabusBooksState build() => const SyllabusBooksState(
    ready: true,
    activeBookId: 'test-book',
    imported: <SyllabusBook>[
      SyllabusBook(
        id: 'test-book',
        title: '测试词书',
        examTag: 'TEST',
        words: <SyllabusWord>[SyllabusWord(word: 'apple')],
      ),
    ],
  );
}

void main() {
  testWidgets('今日学习 shows the current book and offers material selection', (
    WidgetTester tester,
  ) async {
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: TodayActivityCard()),
        ),
        GoRoute(
          path: SGRoute.reviewSession.route,
          builder: (context, state) => Scaffold(
            body: Text('复习 due=${state.uri.queryParameters['due']}'),
          ),
        ),
        GoRoute(
          path: SGRoute.vocabularyPlacement.route,
          builder: (_, _) => const Scaffold(body: Text('词汇量测试')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vocabularyPlacementProvider.overrideWith(_UntestedPlacement.new),
          syllabusBooksProvider.overrideWith(_SelectedBooks.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日学习'), findsOneWidget);
    expect(find.text('继续学习'), findsOneWidget);
    expect(find.text('背单词 → 看视频 → 复习单词 → 阅读书籍 → 拍照聊天'), findsOneWidget);
    expect(find.textContaining('第 1'), findsNothing);
    expect(find.text('英语之旅'), findsNothing);

    expect(find.text('测试词书'), findsOneWidget);
    expect(find.text('自由拍照学词'), findsOneWidget);
    await tester.tap(find.text('今日学习'));
    await tester.pumpAndSettle();
    expect(find.text('选择要看的视频'), findsOneWidget);
    expect(find.text('选择要读的书'), findsOneWidget);
    expect(find.text('选择要背的词书'), findsOneWidget);
    expect(find.text('自由拍照学词'), findsWidgets);
  });
}
