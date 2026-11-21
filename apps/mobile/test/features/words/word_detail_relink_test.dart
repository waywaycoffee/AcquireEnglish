import 'dart:io';

import 'package:common_learn_english/features/library/presentation/library_catalog_provider.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:common_learn_english/features/words/data/offline_word_dictionary.dart';
import 'package:common_learn_english/features/words/presentation/word_book_provider.dart';
import 'package:common_learn_english/features/words/presentation/word_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'word_video_relink_test.dart' as fixtures;

class _Words extends WordBookNotifier {
  _Words(this.occurrence);
  final WordOccurrence occurrence;
  @override
  List<WordEntry> build() => <WordEntry>[
    WordEntry(
      word: 'antacid',
      favorite: true,
      occurrences: <WordOccurrence>[occurrence],
    ),
  ];
}

class _Catalog extends LibraryCatalogNotifier {
  _Catalog(this.courses);
  final List<LibraryCourseData> courses;
  @override
  List<LibraryCourseData> build() => courses;
}

class _Dictionary extends OfflineWordDictionary {
  @override
  Future<OfflineWordDefinition?> lookup(String rawWord) async => null;
}

void main() {
  testWidgets(
    'historical contexts follow case settings without modifying source',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ProviderContainer container = ProviderContainer(
        // ignore: always_specify_types
        overrides: [
          wordBookProvider.overrideWith(() => _Words(fixtures.occurrence())),
          offlineWordDictionaryProvider.overrideWithValue(_Dictionary()),
        ],
      );
      addTearDown(container.dispose);
      Future<void> pumpDialog() async {
        final String letterCase =
            container.read(learningSettingsProvider).subtitleLetterCase;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: WordDetailDialog(
                  key: ValueKey<String>('antacid-dialog-$letterCase'),
                  word: 'antacid',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> revealOriginalSentences() async {
        await tester.scrollUntilVisible(
          find.textContaining('单词原句 ·'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
      }

      await pumpDialog();
      await revealOriginalSentences();
      expect(find.text("OH, HERE'S SOME ANTACID."), findsWidgets);
      container
          .read(learningSettingsProvider.notifier)
          .setSubtitleLetterCase('句首字母大写');
      await pumpDialog();
      await revealOriginalSentences();
      expect(
        find.textContaining("Oh, here's some antacid"),
        findsWidgets,
      );
      container
          .read(learningSettingsProvider.notifier)
          .setSubtitleLetterCase('全部小写');
      await pumpDialog();
      await revealOriginalSentences();
      expect(
        find.textContaining("oh, here's some antacid"),
        findsWidgets,
      );
      container
          .read(learningSettingsProvider.notifier)
          .setSubtitleLetterCase('保留原样');
      await pumpDialog();
      await revealOriginalSentences();
      expect(
        find.textContaining("OH, HERE'S SOME ANTACID"),
        findsWidgets,
      );
      expect(
        container
            .read(wordBookProvider)
            .single
            .occurrences
            .single
            .contexts
            .single
            .sentence,
        "OH, HERE'S SOME ANTACID.",
      );
    },
  );

  for (final bool ambiguous in <bool>[false, true]) {
    testWidgets('jump to video preserves timestamp; ambiguous=$ambiguous', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final Directory temp = Directory.systemTemp.createTempSync('word-video-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final String path = '${temp.path}/Peppa.S01E01.mp4';
      File(path).writeAsStringSync('video');
      final LibraryCourseData first = fixtures.videoCourse(file: path);
      final List<LibraryCourseData> courses = <LibraryCourseData>[
        first,
        if (ambiguous)
          fixtures.videoCourse(id: 'another-copy', title: '另一份课程', file: path),
      ];
      final WordOccurrence old = fixtures.occurrence(
        id: ambiguous ? 'unknown' : 'a-peppa_s01e01_mp4-ep01',
        file: ambiguous ? 'Peppa.S01E01.mp4' : null,
      );
      final ProviderContainer container = ProviderContainer(
        // ignore: always_specify_types
        overrides: [
          libraryCatalogProvider.overrideWith(() => _Catalog(courses)),
          wordBookProvider.overrideWith(() => _Words(old)),
          offlineWordDictionaryProvider.overrideWithValue(_Dictionary()),
        ],
      );
      addTearDown(container.dispose);
      final GoRouter router = GoRouter(
        routes: <GoRoute>[
          GoRoute(
            path: '/',
            builder: (BuildContext context, GoRouterState state) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (BuildContext context) =>
                      const WordDetailDialog(word: 'antacid'),
                ),
                child: const Text('查看单词'),
              ),
            ),
          ),
          GoRoute(
            path: '/episodes/:episodeId',
            builder: (BuildContext context, GoRouterState state) => Scaffold(
              body: Text(
                'player:${state.pathParameters['episodeId']}:${state.uri.queryParameters['startTime']}:${state.uri.queryParameters['autoplay']}',
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      Future<void> revealJumpControl() async {
        await tester.scrollUntilVisible(
          find.text('跳到影片'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('查看单词'));
      await tester.pumpAndSettle();
      await revealJumpControl();
      await tester.tap(find.text('跳到影片'));
      await tester.pumpAndSettle();
      if (ambiguous) {
        expect(find.text('重新关联影片'), findsOneWidget);
        expect(
          container.read(wordBookProvider).single.occurrences.single.episodeId,
          old.episodeId,
        );
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(
          container.read(wordBookProvider).single.occurrences.single.episodeId,
          old.episodeId,
        );
        await revealJumpControl();
        await tester.tap(find.text('跳到影片'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('B · Peppa.S01E01'));
        await tester.pumpAndSettle();
      }
      expect(
        find.text('player:${first.episodes.single.id}:00:01:1'),
        findsOneWidget,
      );
      expect(
        container.read(wordBookProvider).single.occurrences.single.episodeId,
        first.episodes.single.id,
      );
      expect(
        container
            .read(wordBookProvider)
            .single
            .occurrences
            .single
            .contexts
            .single
            .time,
        '00:01',
      );
    });
  }
}
