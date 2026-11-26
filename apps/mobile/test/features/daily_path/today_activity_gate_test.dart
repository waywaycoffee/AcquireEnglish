import 'dart:io';

import 'package:common_learn_english/features/home/presentation/widgets/today_activity_card.dart';
import 'package:common_learn_english/features/words/presentation/vocabulary_placement_provider.dart';
import 'package:common_learn_english/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';

class _UntestedPlacement extends VocabularyPlacement {
  @override
  PlacementRow build() => <String, dynamic>{};
}

void main() {
  testWidgets('今日学习 asks for quotas before opening content', (
    WidgetTester tester,
  ) async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'today_activity_card',
    );
    addTearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });
    Hive.init(directory.path);
    await Hive.openBox<String>('prefs');

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
              '复习 due=${state.uri.queryParameters['due']}',
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

    expect(find.text('今日学习'), findsOneWidget);
    expect(find.textContaining('设定今日配额'), findsOneWidget);
    expect(find.textContaining('第 1'), findsNothing);
    expect(find.text('英语之旅'), findsNothing);

    await tester.tap(find.textContaining('设定今日配额'));
    await tester.pumpAndSettle();
    expect(find.text('今天学多少？'), findsOneWidget);
    expect(find.text('开始今日学习'), findsOneWidget);
  });
}
