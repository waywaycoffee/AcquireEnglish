import 'package:common_learn_english/features/home/presentation/widgets/level_vocab_book_modules.dart';
import 'package:common_learn_english/features/words/presentation/syllabus_books_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _EmptyBooks extends SyllabusBooksNotifier {
  @override
  SyllabusBooksState build() => const SyllabusBooksState(ready: true);
}

void main() {
  testWidgets('home vocabulary button opens the book picker when needed', (
    WidgetTester tester,
  ) async {
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: SingleChildScrollView(child: LevelVocabBookModules()),
          ),
        ),
        GoRoute(
          path: '/words/syllabus',
          builder: (_, GoRouterState state) => Scaffold(
            body: Text('选书 ${state.uri.queryParameters['selectForStudy']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [syllabusBooksProvider.overrideWith(_EmptyBooks.new)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('开始背单词'));
    await tester.pumpAndSettle();
    expect(find.text('选书 1'), findsOneWidget);
  });
}
