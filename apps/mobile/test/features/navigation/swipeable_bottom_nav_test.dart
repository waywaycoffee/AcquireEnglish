import 'package:common_learn_english/features/navigation/presentation/app_nav_rail.dart';
import 'package:common_learn_english/features/navigation/presentation/navigation_destination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sidebar rail order matches feature-entry-map IA', () {
    expect(
      AppNavDestination.sidebarRailDestinations.map(
        (AppNavDestination d) => d.label,
      ),
      <String>[
        '首页',
        '课程',
        '听力',
        '口语',
        '阅读',
        '收藏',
        '历史',
        '社区',
        '对战',
        '应试',
      ],
    );
    expect(AppNavDestination.settings.label, '我的');
    expect(AppNavDestination.reading.title, '我的书架');
  });

  testWidgets('phone icon rail shows primary entries without bottom bar', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppNavRail(current: AppNavDestination.home),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppNavRail), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });
}
