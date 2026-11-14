import 'package:common_learn_english/features/player/presentation/player_screen.dart';
import 'package:common_learn_english/features/player/presentation/pad_portrait_player_screen.dart';
import 'package:common_learn_english/features/shared/presentation/app_orientation.dart'
    show
        ensureDefaultPortraitOrientation,
        isFullscreenLandscapeActive,
        lockPortraitOrientation,
        unlockFullscreenLandscapeOrientation;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<MethodCall?> captureOrientationCall(
    Future<void> Function() action,
  ) async {
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          calls.add(call);
          return null;
        });
    await action();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    for (final MethodCall call in calls.reversed) {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        return call;
      }
    }
    return null;
  }

  test('portrait lock clears fullscreen flag', () async {
    await unlockFullscreenLandscapeOrientation();
    expect(isFullscreenLandscapeActive, isTrue);
    await lockPortraitOrientation();
    expect(isFullscreenLandscapeActive, isFalse);
  });

  test('ensureDefaultPortrait skips while fullscreen owns orientation', () async {
    await unlockFullscreenLandscapeOrientation();
    expect(isFullscreenLandscapeActive, isTrue);
    await ensureDefaultPortraitOrientation();
    expect(isFullscreenLandscapeActive, isTrue);
    await lockPortraitOrientation();
    expect(isFullscreenLandscapeActive, isFalse);
  });

  testWidgets('PlayerScreen always builds the portrait study shell', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: PlayerScreen(episodeId: 'intern-ep3')),
      ),
    );
    expect(find.byType(PadPortraitPlayerScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
