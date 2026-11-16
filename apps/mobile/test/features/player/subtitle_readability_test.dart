import 'dart:io';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:common_learn_english/features/player/presentation/episode_subtitle_editor_screen.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/widgets/player_subtitle_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('active words stay centered including first and last cues', (
    tester,
  ) async {
    final word = ValueNotifier<int>(0);
    addTearDown(word.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 400,
            child: ValueListenableBuilder<int>(
              valueListenable: word,
              builder: (_, index, __) => PlayerSubtitleList(
                lines: const [
                  PlayerSubtitleLine(
                    startMs: 0,
                    endMs: 10000,
                    startTime: '00:00',
                    english:
                        'one two three four five six seven eight nine ten eleven twelve',
                    chinese: '',
                  ),
                ],
                activeIndex: 0,
                currentWordIndex: index,
                subtitleMode: '英文',
                fontScale: 1,
                highlightWords: true,
                isPlaying: true,
                onTapLine: (_) {},
                onCollectWord: (_) {},
                onBookmarkLine: (_) {},
                onLoopFromLine: (_) {},
                onDictationLine: (_) {},
                onAiExplain: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    for (final index in [0, 6, 11]) {
      word.value = index;
      await tester.pumpAndSettle();
      final active = find.byWidgetPredicate(
        (widget) =>
            widget.key is GlobalKey &&
            widget.key.toString().contains('active-subtitle-word'),
      );
      expect(active, findsOneWidget);
      expect(
        tester.getCenter(active).dy,
        closeTo(tester.getCenter(find.byType(ListView)).dy, 3),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('subtitle editor keeps focused input above keyboard', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('subtitle-keyboard-');
    final paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
    addTearDown(() {
      PathProviderPlatform.instance = paths;
      root.deleteSync(recursive: true);
    });
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: EpisodeSubtitleEditorScreen(
            episodeId: 'keyboard-test',
            title: 'Edit',
            initialLines: List.generate(
              8,
              (index) => PlayerSubtitleLine(
                startMs: index * 1000,
                endMs: (index + 1) * 1000,
                startTime: '00:0$index',
                english: 'Hello',
                chinese: '你好',
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    final input = find.byType(TextField).first;
    await tester.tap(input);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    await tester.enterText(input, 'Visible typing');
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(input).dy, lessThanOrEqualTo(500));
    expect(tester.takeException(), isNull);
  });
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}
