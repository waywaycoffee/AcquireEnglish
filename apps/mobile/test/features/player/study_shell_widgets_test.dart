import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/widgets/study_bottom_controls.dart';
import 'package:common_learn_english/features/player/presentation/widgets/study_mode_tabs.dart';
import 'package:common_learn_english/features/player/presentation/widgets/study_shadowing_tab.dart';
import 'package:common_learn_english/features/player/presentation/widgets/study_tab_placeholder.dart';
import 'package:common_learn_english/features/player/presentation/widgets/study_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('StudyModeTabs switches among four modes', (
    WidgetTester tester,
  ) async {
    StudyModeTab selected = StudyModeTab.subtitles;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Scaffold(
              body: Column(
                children: <Widget>[
                  StudyModeTabs(
                    value: selected,
                    onChanged: (StudyModeTab tab) {
                      setState(() => selected = tab);
                    },
                  ),
                  if (selected == StudyModeTab.dictation ||
                      selected == StudyModeTab.practice)
                    StudyTabPlaceholder(tab: selected),
                ],
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('字幕'), findsOneWidget);
    expect(find.text('跟读'), findsOneWidget);
    expect(find.text('听写'), findsOneWidget);
    expect(find.text('练习'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('study-tab-dictation')));
    await tester.pumpAndSettle();
    expect(find.textContaining('听写 模式将在 P2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('study-tab-practice')));
    await tester.pumpAndSettle();
    expect(find.textContaining('练习 模式将在 P2'), findsOneWidget);
  });

  testWidgets('StudyBottomControls fires bilingual loop and close-reading', (
    WidgetTester tester,
  ) async {
    int bilingualTaps = 0;
    int loopTaps = 0;
    int closeReadingTaps = 0;
    int playTaps = 0;
    int speedTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudyBottomControls(
            bilingual: true,
            speed: '1.0×',
            isPlaying: false,
            isLooping: false,
            position: const Duration(seconds: 5),
            duration: const Duration(minutes: 1, seconds: 36),
            onToggleBilingual: () => bilingualTaps += 1,
            onCycleSpeed: () => speedTaps += 1,
            onTogglePlaying: () => playTaps += 1,
            onToggleLoop: () => loopTaps += 1,
            onOpenCloseReading: () => closeReadingTaps += 1,
          ),
        ),
      ),
    );

    expect(find.text('00:05 / 01:36'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('study-chip-bilingual')));
    await tester.tap(find.byKey(const ValueKey<String>('study-chip-loop')));
    await tester.tap(
      find.byKey(const ValueKey<String>('study-chip-close-reading')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('study-chip-play')));
    await tester.tap(find.byKey(const ValueKey<String>('study-chip-speed')));
    await tester.pump();

    expect(bilingualTaps, 1);
    expect(loopTaps, 1);
    expect(closeReadingTaps, 1);
    expect(playTaps, 1);
    expect(speedTaps, 1);
  });

  test('StudyBottomControls.nextSpeed cycles options', () {
    expect(StudyBottomControls.nextSpeed('0.5×'), '0.8×');
    expect(StudyBottomControls.nextSpeed('2.0×'), '0.5×');
    expect(StudyBottomControls.nextSpeed('unknown'), '0.5×');
  });

  testWidgets('StudyTopBar shows title and actions', (WidgetTester tester) async {
    int backTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudyTopBar(
            title: '慢速英语',
            onBack: () => backTaps += 1,
          ),
        ),
      ),
    );
    expect(find.text('慢速英语'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    expect(backTaps, 1);
  });

  testWidgets('StudyShadowingTab shows assess action', (
    WidgetTester tester,
  ) async {
    int assessTaps = 0;
    const PlayerSubtitleLine line = PlayerSubtitleLine(
      startTime: '01:02',
      english: 'Hello world',
      chinese: '你好世界',
      startMs: 62000,
      endMs: 65000,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudyShadowingTab(
            line: line,
            hasLine: true,
            onAssess: () => assessTaps += 1,
          ),
        ),
      ),
    );

    expect(find.text('Hello world'), findsOneWidget);
    expect(find.text('你好世界'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('study-shadowing-assess')),
    );
    expect(assessTaps, 1);
  });
}
