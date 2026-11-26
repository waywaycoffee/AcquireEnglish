import 'package:common_learn_english/features/home/presentation/widgets/today_activity_card.dart';
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

void main() {
  testWidgets('untested journey opens due review before placement', (
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
            body: Text(
              '复习 due=${state.uri.queryParameters['due']} '
              'journey=${state.uri.queryParameters['journeyReview']}',
            ),
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
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // CTA copy is「下一步：…」; Gate1 opens due review.
    final Finder cta = find.textContaining('下一步');
    expect(cta, findsWidgets);
    await tester.tap(cta.first);
    await tester.pumpAndSettle();

    expect(find.text('复习 due=1 journey=1'), findsOneWidget);
    expect(find.text('词汇量测试'), findsNothing);
    expect(find.text('今天想做什么？'), findsNothing);
  });
}
