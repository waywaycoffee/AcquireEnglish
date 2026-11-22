import 'package:common_learn_english/features/navigation/presentation/floating_bottom_nav.dart';
import 'package:common_learn_english/features/navigation/presentation/navigation_destination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('bottom bar order matches product IA', () {
    expect(
      AppNavDestination.bottomBarDestinations.map(
        (AppNavDestination d) => d.label,
      ),
      <String>[
        '学习',
        '视频',
        '阅读',
        '口语',
        '社区',
        '对战',
        '备考',
        '词书',
      ],
    );
    expect(AppNavDestination.bottomBarVisibleCount, 5);
    expect(
      AppNavDestination.moreMenuDestinations.map(
        (AppNavDestination d) => d.label,
      ),
      containsAll(<String>['复习', '成长', '怎么学', '设置']),
    );
  });

  testWidgets('portrait bar shows five primary tabs and scroll affordance', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          bottomNavigationBar: FloatingBottomNav(
            current: AppNavDestination.home,
            forceShowScrollHint: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('学习'), findsOneWidget);
    expect(find.text('视频'), findsOneWidget);
    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('口语'), findsOneWidget);
    expect(find.text('社区'), findsOneWidget);
    // Off-screen items still exist in the scrollable list.
    expect(find.text('单词'), findsNothing);
    expect(find.text('对战', skipOffstage: false), findsOneWidget);
    expect(find.text('备考', skipOffstage: false), findsOneWidget);
    expect(find.text('词书', skipOffstage: false), findsOneWidget);
    expect(find.text('更多', skipOffstage: false), findsOneWidget);
    expect(find.byKey(const Key('bottom-nav-scroll-indicator')), findsOneWidget);
    expect(find.byKey(const Key('bottom-nav-scroll-hint')), findsNothing);
  });

  testWidgets('first-run scroll hint dismisses on tap', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    bool dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: FloatingBottomNav(
            current: AppNavDestination.home,
            forceShowScrollHint: true,
            onScrollHintDismissed: () => dismissed = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bottom-nav-scroll-hint')), findsOneWidget);
    await tester.tap(find.byKey(const Key('bottom-nav-scroll-hint')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bottom-nav-scroll-hint')), findsNothing);
    expect(dismissed, isTrue);
  });

  testWidgets('swiping the bar reveals secondary tabs', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          bottomNavigationBar: FloatingBottomNav(
            current: AppNavDestination.home,
            forceShowScrollHint: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder scrollable = find.byKey(const Key('bottom-nav-scroll'));
    await tester.drag(scrollable, const Offset(-280, 0));
    await tester.pumpAndSettle();

    expect(find.text('社区'), findsOneWidget);
    expect(find.text('对战'), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);
  });

  testWidgets('selecting a far tab centers it in the visible area', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final GlobalKey<FloatingBottomNavState> navKey =
        GlobalKey<FloatingBottomNavState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: FloatingBottomNav(
            key: navKey,
            current: AppNavDestination.exam,
            forceShowScrollHint: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await navKey.currentState!.centerCurrentForTest();
    await tester.pumpAndSettle();

    expect(navKey.currentState!.scrollOffsetForTest, greaterThan(0));

    final Rect viewport = tester.getRect(find.byKey(const Key('bottom-nav-scroll')));
    final Rect selected = tester.getRect(
      find.byKey(const Key('bottom-nav-item-exam')),
    );
    final double selectedCenter = selected.center.dx;
    final double viewportCenter = viewport.center.dx;
    expect((selectedCenter - viewportCenter).abs(), lessThan(selected.width));
  });

  testWidgets('tapping a tab navigates via go_router', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final GoRouter router = GoRouter(
      initialLocation: '/home',
      routes: <GoRoute>[
        GoRoute(
          path: '/home',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(
                body: Text('home page'),
                bottomNavigationBar: FloatingBottomNav(
                  current: AppNavDestination.home,
                  forceShowScrollHint: false,
                ),
              ),
        ),
        GoRoute(
          path: '/library',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(
                body: Text('library page'),
                bottomNavigationBar: FloatingBottomNav(
                  current: AppNavDestination.library,
                  forceShowScrollHint: false,
                ),
              ),
        ),
        GoRoute(
          path: '/battle',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Text('battle page')),
        ),
      ],
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('视频'));
    await tester.pumpAndSettle();
    expect(find.text('library page'), findsOneWidget);
  });
}
