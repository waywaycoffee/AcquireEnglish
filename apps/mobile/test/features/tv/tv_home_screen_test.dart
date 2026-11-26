import 'package:common_learn_english/features/tv/presentation/tv_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TV home shows launcher chrome', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: TvHomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('电视横屏学习'), findsOneWidget);
    expect(find.textContaining('返回手机版'), findsOneWidget);
  });
}
