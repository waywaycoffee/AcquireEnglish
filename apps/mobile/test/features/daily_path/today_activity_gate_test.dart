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
  testWidgets('leaving the placement test cannot open the daily chooser', (
    WidgetTester tester,
  ) async {
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: TodayActivityCard()),
        ),
        GoRoute(
          path: SGRoute.vocabularyPlacement.route,
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: context.pop,
              child: Text('测试 ${state.uri.queryParameters['journey']}'),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [vocabularyPlacementProvider.overrideWith(_UntestedPlacement.new)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.tap(find.text('今天的英语之旅'));
    await tester.pumpAndSettle();
    expect(find.text('测试 1'), findsOneWidget);
    await tester.tap(find.text('测试 1'));
    await tester.pumpAndSettle();
    expect(find.text('今天的英语之旅'), findsOneWidget);
    expect(find.text('今天想做什么？'), findsNothing);
  });
}
