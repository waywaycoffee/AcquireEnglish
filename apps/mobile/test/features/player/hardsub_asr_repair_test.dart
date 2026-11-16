import 'dart:io';

import 'package:common_learn_english/features/player/presentation/hardsub_asr_repair.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/subtitle_sentence_merge.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mergeAsrIntoSentences keeps word timings for karaoke', () {
    final MergedSubtitleBundle bundle = mergeAsrIntoSentences(
      asrLines: const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Hello',
          chinese: '',
          startMs: 0,
          endMs: 500,
          words: <PlayerSubtitleWord>[
            PlayerSubtitleWord(text: 'Hello', startMs: 0, endMs: 500),
          ],
        ),
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'world.',
          chinese: '',
          startMs: 500,
          endMs: 1000,
          words: <PlayerSubtitleWord>[
            PlayerSubtitleWord(text: 'world.', startMs: 500, endMs: 1000),
          ],
        ),
      ],
    );
    expect(bundle.sentences, hasLength(1));
    expect(bundle.sentences.single.words, hasLength(2));
    expect(bundle.sentenceLines.single.words.map((w) => w.text), <String>[
      'Hello',
      'world.',
    ]);
  });

  test(
    'mergeAsrIntoSentences fits mismatched Whisper crumbs to display tokens',
    () {
      // Whisper often emits punctuation as its own timed word; space-split UI
      // does not. After merge those lengths diverge and karaoke goes blank.
      final MergedSubtitleBundle bundle = mergeAsrIntoSentences(
        asrLines: const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '00:01',
            english: 'I grew up',
            chinese: '',
            startMs: 0,
            endMs: 900,
            words: <PlayerSubtitleWord>[
              PlayerSubtitleWord(text: 'I', startMs: 0, endMs: 200),
              PlayerSubtitleWord(text: 'grew', startMs: 200, endMs: 500),
              PlayerSubtitleWord(text: 'up', startMs: 500, endMs: 900),
            ],
          ),
          PlayerSubtitleLine(
            startTime: '00:01',
            english: 'a poor kid.',
            chinese: '',
            startMs: 1000,
            endMs: 2000,
            words: <PlayerSubtitleWord>[
              PlayerSubtitleWord(text: 'a', startMs: 1000, endMs: 1200),
              PlayerSubtitleWord(text: 'poor', startMs: 1200, endMs: 1500),
              PlayerSubtitleWord(text: 'kid', startMs: 1500, endMs: 1800),
              PlayerSubtitleWord(text: '.', startMs: 1800, endMs: 2000),
            ],
          ),
        ],
      );
      expect(bundle.sentences, hasLength(1));
      final String english = bundle.sentences.single.english;
      final List<String> display = english
          .split(RegExp(r'\s+'))
          .where((String t) => t.isNotEmpty)
          .toList(growable: false);
      expect(bundle.sentences.single.words, hasLength(display.length));
      expect(
        bundle.sentences.single.words.map((PlayerSubtitleWord w) => w.text),
        display,
      );
    },
  );

  test(
    'hardsub repair preserves existing Chinese when timings were lost',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'hardsub-repair-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsBytesSync(List<int>.filled(2048, 1));

      final ({List<PlayerSubtitleLine> lines, bool strippedChinese}) repaired =
          await repairHardsubAsrDisplayLines(
            lines: const <PlayerSubtitleLine>[
              PlayerSubtitleLine(
                startTime: '00:01',
                english: 'Hello world',
                chinese: '手机贴膜评测',
                startMs: 0,
                endMs: 1000,
              ),
            ],
            episodeId: 'ep-hardsub',
            videoPath: video.path,
            settings: LearningSettingsState.defaults(),
            hardsub: true,
            appSupportDirectory: () async => root,
          );

      expect(repaired.strippedChinese, isFalse);
      expect(repaired.lines.single.english, 'Hello world');
      expect(repaired.lines.single.chinese, '手机贴膜评测');
    },
  );

  test('hardsub repair keeps Chinese after EN→ZH marker', () async {
    final Directory root = Directory.systemTemp.createTempSync('hardsub-keep-');
    addTearDown(() => root.deleteSync(recursive: true));
    await markHardsubChineseFromTranslation(
      episodeId: 'ep-ok',
      appSupportDirectory: () async => root,
    );

    final ({List<PlayerSubtitleLine> lines, bool strippedChinese}) repaired =
        await repairHardsubAsrDisplayLines(
          lines: const <PlayerSubtitleLine>[
            PlayerSubtitleLine(
              startTime: '00:01',
              english: 'Hello world',
              chinese: '你好世界',
              startMs: 0,
              endMs: 1000,
              words: <PlayerSubtitleWord>[
                PlayerSubtitleWord(text: 'Hello', startMs: 0, endMs: 400),
                PlayerSubtitleWord(text: 'world', startMs: 400, endMs: 1000),
              ],
            ),
          ],
          episodeId: 'ep-ok',
          videoPath: null,
          settings: LearningSettingsState.defaults(),
          hardsub: true,
          appSupportDirectory: () async => root,
        );

    expect(repaired.strippedChinese, isFalse);
    expect(repaired.lines.single.chinese, '你好世界');
    expect(repaired.lines.single.words, hasLength(2));
  });

  test(
    'ASR repair preserves existing Chinese even when hardsub is false',
    () async {
      final Directory root = Directory.systemTemp.createTempSync('asr-strip-');
      addTearDown(() => root.deleteSync(recursive: true));

      final ({List<PlayerSubtitleLine> lines, bool strippedChinese}) repaired =
          await repairHardsubAsrDisplayLines(
            lines: const <PlayerSubtitleLine>[
              PlayerSubtitleLine(
                startTime: '00:01',
                english: 'Hello world',
                chinese: '你是不是很虚啊',
                startMs: 0,
                endMs: 1000,
              ),
            ],
            episodeId: 'ep-asr',
            videoPath: null,
            settings: LearningSettingsState.defaults(),
            hardsub: false,
            stripUntrustedChinese: true,
            appSupportDirectory: () async => root,
          );

      expect(repaired.strippedChinese, isFalse);
      expect(repaired.lines.single.chinese, '你是不是很虚啊');
    },
  );

  test(
    'hardsub repair preserves Chinese even when words exist without marker',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'hardsub-words-',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final ({List<PlayerSubtitleLine> lines, bool strippedChinese}) repaired =
          await repairHardsubAsrDisplayLines(
            lines: const <PlayerSubtitleLine>[
              PlayerSubtitleLine(
                startTime: '00:01',
                english: 'I grew up a poor kid',
                chinese: '你是不是很虚啊 我是凭的感觉',
                startMs: 0,
                endMs: 2000,
                words: <PlayerSubtitleWord>[
                  PlayerSubtitleWord(text: 'I', startMs: 1200, endMs: 1400),
                  PlayerSubtitleWord(text: 'grew', startMs: 1400, endMs: 1600),
                ],
              ),
            ],
            episodeId: 'ep-polluted',
            videoPath: null,
            settings: LearningSettingsState.defaults(),
            hardsub: true,
            appSupportDirectory: () async => root,
          );

      expect(repaired.strippedChinese, isFalse);
      expect(repaired.lines.single.chinese, '你是不是很虚啊 我是凭的感觉');
      // Incomplete crumb words are fitted onto space-split display tokens.
      expect(repaired.lines.single.words, hasLength(6));
      expect(
        repaired.lines.single.words.map((PlayerSubtitleWord w) => w.text),
        <String>['I', 'grew', 'up', 'a', 'poor', 'kid'],
      );
    },
  );
}
