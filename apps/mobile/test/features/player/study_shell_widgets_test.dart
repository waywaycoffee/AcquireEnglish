import 'package:common_learn_english/features/player/data/dictation_queue_provider.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/widgets/study_bottom_controls.dart';
import 'package:common_learn_english/features/player/presentation/widgets/study_dictation_tab.dart';
import 'package:common_learn_english/features/player/presentation/widgets/study_mode_tabs.dart';
import 'package:common_learn_english/features/player/domain/episode_word_cards.dart';
import 'package:common_learn_english/features/player/presentation/widgets/study_practice_tab.dart';
import 'package:common_learn_english/features/player/presentation/widgets/study_shadowing_tab.dart';
import 'package:common_learn_english/features/player/presentation/widgets/study_top_bar.dart';
import 'package:common_learn_english/features/player/presentation/widgets/study_word_cards_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('StudyModeTabs switches among study modes', (
    WidgetTester tester,
  ) async {
    StudyModeTab selected = StudyModeTab.subtitles;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Scaffold(
              body: StudyModeTabs(
                value: selected,
                onChanged: (StudyModeTab tab) {
                  setState(() => selected = tab);
                },
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('字幕'), findsOneWidget);
    expect(find.text('跟读'), findsOneWidget);
    expect(find.text('陪练'), findsOneWidget);
    expect(find.text('听写'), findsOneWidget);
    expect(find.text('练习'), findsOneWidget);
    expect(find.text('词卡'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('study-tab-coach')));
    await tester.pumpAndSettle();
    expect(selected, StudyModeTab.coach);

    await tester.tap(find.byKey(const ValueKey<String>('study-tab-dictation')));
    await tester.pumpAndSettle();
    expect(selected, StudyModeTab.dictation);

    await tester.tap(find.byKey(const ValueKey<String>('study-tab-practice')));
    await tester.pumpAndSettle();
    expect(selected, StudyModeTab.practice);

    await tester.tap(find.byKey(const ValueKey<String>('study-tab-wordCards')));
    await tester.pumpAndSettle();
    expect(selected, StudyModeTab.wordCards);
  });

  testWidgets('StudyBottomControls fires subtitle mode loop and word-cards', (
    WidgetTester tester,
  ) async {
    final List<String> selectedModes = <String>[];
    int loopTaps = 0;
    int wordCardTaps = 0;
    int playTaps = 0;
    int speedSelects = 0;
    int qualityTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudyBottomControls(
            subtitleMode: '双语',
            speed: '1.0×',
            isPlaying: false,
            isLooping: false,
            position: const Duration(seconds: 5),
            duration: const Duration(minutes: 1, seconds: 36),
            onSelectSubtitleMode: selectedModes.add,
            onCycleSpeed: () {},
            onSpeedSelected: (_) => speedSelects += 1,
            onOpenQualitySheet: () => qualityTaps += 1,
            onTogglePlaying: () => playTaps += 1,
            onOpenLoopSheet: () => loopTaps += 1,
            onOpenWordCards: () => wordCardTaps += 1,
          ),
        ),
      ),
    );

    expect(find.text('00:05 / 01:36'), findsOneWidget);
    expect(find.text('双语'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey<String>('study-chip-subtitle-label')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('study-chip-loop')));
    await tester.tap(find.byKey(const ValueKey<String>('study-chip-word-cards')));
    await tester.tap(find.byKey(const ValueKey<String>('study-chip-play')));
    await tester.tap(find.text('超清'));
    await tester.pump();

    expect(selectedModes, <String>['英文']);
    expect(loopTaps, 1);
    expect(wordCardTaps, 1);
    expect(playTaps, 1);
    expect(qualityTaps, 1);
    expect(speedSelects, 0);
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

  testWidgets('StudyShadowingTab shows line and unavailable reason', (
    WidgetTester tester,
  ) async {
    const PlayerSubtitleLine line = PlayerSubtitleLine(
      startTime: '01:02',
      english: 'Hello world',
      chinese: '你好世界',
      startMs: 62000,
      endMs: 65000,
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudyShadowingTab(
              line: line,
              hasLine: true,
              unavailableReason: '当前句暂不可录音跟读。',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Hello world'), findsOneWidget);
    expect(find.textContaining('当前句暂不可录音跟读'), findsOneWidget);
  });

  testWidgets('StudyDictationTab can add to queue and mark difficult', (
    WidgetTester tester,
  ) async {
    int addTaps = 0;
    int hardTaps = 0;
    const PlayerSubtitleLine line = PlayerSubtitleLine(
      startTime: '00:10',
      english: 'We checked in',
      chinese: '我们办了入住',
      startMs: 10000,
      endMs: 12000,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudyDictationTab(
            line: line,
            hasLine: true,
            isPlaying: false,
            onReplay: () {},
            onPrevious: () {},
            onNext: () {},
            onAddToQueue: () => addTaps += 1,
            onMarkDifficult: () => hardTaps += 1,
          ),
        ),
      ),
    );

    expect(find.text('显示提示'), findsOneWidget);
    expect(find.text('提交'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('dictation-add-queue')));
    await tester.tap(
      find.byKey(const ValueKey<String>('dictation-mark-difficult')),
    );
    expect(addTaps, 1);
    expect(hardTaps, 1);
  });

  testWidgets('StudyPracticeTab builds a multi-question session', (
    WidgetTester tester,
  ) async {
    final List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:00',
        english: 'We have just checked in and now we need to go',
        chinese: '我们刚办完入住',
        startMs: 0,
        endMs: 4000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:04',
        english: 'So lets take the lift downstairs carefully',
        chinese: '那咱们坐电梯',
        startMs: 4000,
        endMs: 8000,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudyPracticeTab(
            lines: lines,
            activeIndex: 0,
            onCollectWord: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('检查答案'), findsOneWidget);
    expect(find.text('点击播放音频'), findsOneWidget);
  });

  test('DictationQueueItem.buildId is stable', () {
    final String id = DictationQueueItem.buildId(
      episodeId: 'ep1',
      startMs: 1200,
      endMs: 3400,
      english: 'hello',
    );
    expect(id, contains('ep1'));
    expect(id, contains('1200'));
  });

  testWidgets('StudyWordCardsTab filters kinds and jumps', (
    WidgetTester tester,
  ) async {
    EpisodeWordCard? jumped;
    final List<EpisodeWordCard> cards = <EpisodeWordCard>[
      const EpisodeWordCard(
        id: '1',
        text: 'lift',
        kind: EpisodeCardKind.word,
        favorited: true,
        source: 'favorite',
        meaningCn: '电梯',
        exampleEn: 'So this is the lift',
        time: '00:24',
        startMs: 24000,
      ),
      const EpisodeWordCard(
        id: '2',
        text: 'luggage trolley',
        kind: EpisodeCardKind.phrase,
        favorited: false,
        source: 'suggested',
        exampleEn: 'This is a luggage trolley',
        time: '00:06',
        startMs: 6000,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudyWordCardsTab(
              cards: cards,
              onJumpToCard: (EpisodeWordCard card) => jumped = card,
            ),
          ),
        ),
      ),
    );

    expect(find.text('lift'), findsOneWidget);
    expect(find.text('luggage trolley'), findsOneWidget);

    await tester.tap(find.text('短语 1'));
    await tester.pumpAndSettle();
    expect(find.text('lift'), findsNothing);
    expect(find.text('luggage trolley'), findsOneWidget);

    await tester.tap(find.text('luggage trolley'));
    expect(jumped?.text, 'luggage trolley');
  });
}
