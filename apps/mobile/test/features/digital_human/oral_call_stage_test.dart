import 'package:common_learn_english/features/digital_human/presentation/widgets/oral_call_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('oral call stage shows coach chrome and call actions', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final AnimationController pulse = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 800),
    );
    addTearDown(pulse.dispose);

    var hungUp = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 420,
            child: OralCallStage(
              pulse: pulse,
              speaking: false,
              listening: true,
              statusLabel: '外教在听…',
              displayName: 'Emma',
              onHangUp: () => hungUp = true,
              onSwapCoach: () {},
              onToggleMic: () {},
              onToggleSelfCam: () {},
              selfCamOn: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Emma'), findsWidgets);
    expect(find.text('挂断'), findsOneWidget);
    expect(find.text('换教练'), findsOneWidget);
    expect(find.text('摄像头关'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await tester.pump();
    expect(hungUp, isTrue);
  });
}
