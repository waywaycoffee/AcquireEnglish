import 'dart:io';

import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/player_subtitle_loader.dart';
import 'package:common_learn_english/features/player/presentation/subtitle_file_persist.dart';
import 'package:common_learn_english/features/player/presentation/subtitle_sentence_merge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persistAsrSentenceSubtitles writes sentences and asr-sentences origin',
      () async {
    final Directory temp = Directory.systemTemp.createTempSync(
      'ae-asr-sentences-',
    );
    addTearDown(() {
      if (temp.existsSync()) {
        temp.deleteSync(recursive: true);
      }
    });
    final MergedSubtitleBundle bundle = mergeAsrIntoSentences(
      asrLines: const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Hello there',
          chinese: '',
          startMs: 0,
          endMs: 1200,
        ),
      ],
      chineseLines: const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: '',
          chinese: '你好',
          startMs: 0,
          endMs: 1000,
        ),
      ],
    );
    final PersistedBilingualSubtitleFiles? files =
        await persistAsrSentenceSubtitles(
          episodeId: 'ep-asr',
          bundle: bundle,
          appSupportDirectory: () async => temp,
        );
    expect(files, isNotNull);
    expect(await persistedEnglishIsAsrSentences(
      episodeId: 'ep-asr',
      appSupportDirectory: () async => temp,
    ), isTrue);
    final MergedSubtitleBundle? loaded = await loadAsrSentenceSubtitles(
      episodeId: 'ep-asr',
      appSupportDirectory: () async => temp,
    );
    expect(loaded?.sentences.single.english, 'Hello there');
    expect(loaded?.sentences.single.chinese, '你好');

    // Play-time ZH→EN must not clobber ASR sentence files.
    final PersistedBilingualSubtitleFiles? skipped =
        await persistBilingualSubtitleFiles(
          episodeId: 'ep-asr',
          lines: const <PlayerSubtitleLine>[
            PlayerSubtitleLine(
              startTime: '00:01',
              english: 'Machine translation',
              chinese: '机翻',
              startMs: 0,
              endMs: 1000,
            ),
          ],
          translatedFromChinese: true,
          appSupportDirectory: () async => temp,
        );
    expect(skipped, isNotNull);
    expect(await File(files!.englishPath).readAsString(), contains('Hello there'));
    expect(await persistedEnglishIsAsrSentences(
      episodeId: 'ep-asr',
      appSupportDirectory: () async => temp,
    ), isTrue);
  });

  test('linesToSrt writes english and chinese cues separately', () {
    const List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
      PlayerSubtitleLine(
        startTime: '00:01',
        english: 'Hello world',
        chinese: '你好世界',
        startMs: 1000,
        endMs: 2500,
      ),
    ];
    final String en = linesToSrt(lines: lines, english: true);
    final String zh = linesToSrt(lines: lines, english: false);
    expect(en, contains('00:00:01,000 --> 00:00:02,500'));
    expect(en, contains('Hello world'));
    expect(en, isNot(contains('你好世界')));
    expect(zh, contains('你好世界'));
    expect(zh, isNot(contains('Hello world')));
  });

  test('persistBilingualSubtitleFiles writes en.srt and zh.srt', () async {
    final Directory temp = Directory.systemTemp.createTempSync(
      'ae-subtitle-persist-',
    );
    addTearDown(() {
      if (temp.existsSync()) {
        temp.deleteSync(recursive: true);
      }
    });
    final PersistedBilingualSubtitleFiles? files =
        await persistBilingualSubtitleFiles(
          episodeId: 'ep-demo',
          lines: const <PlayerSubtitleLine>[
            PlayerSubtitleLine(
              startTime: '00:01',
              english: 'Hello',
              chinese: '你好',
              startMs: 0,
              endMs: 1000,
            ),
          ],
          appSupportDirectory: () async => temp,
        );
    expect(files, isNotNull);
    expect(File(files!.englishPath).existsSync(), isTrue);
    expect(File(files.chinesePath).existsSync(), isTrue);
    expect(await File(files.englishPath).readAsString(), contains('Hello'));
    expect(await File(files.chinesePath).readAsString(), contains('你好'));

    final PersistedBilingualSubtitleFiles? located =
        await locatePersistedBilingualSubtitleFiles(
          episodeId: 'ep-demo',
          appSupportDirectory: () async => temp,
        );
    expect(located?.englishPath, files.englishPath);
  });

  test('persistBilingualSubtitleFiles writes partial english and reload fills holes only',
      () async {
    final Directory temp = Directory.systemTemp.createTempSync(
      'ae-subtitle-partial-',
    );
    addTearDown(() {
      if (temp.existsSync()) {
        temp.deleteSync(recursive: true);
      }
    });
    const List<PlayerSubtitleLine> partial = <PlayerSubtitleLine>[
      PlayerSubtitleLine(
        startTime: '00:01',
        english: 'Hello',
        chinese: '你好',
        startMs: 0,
        endMs: 1000,
      ),
      PlayerSubtitleLine(
        startTime: '00:02',
        english: '',
        chinese: '世界',
        startMs: 1000,
        endMs: 2000,
      ),
    ];
    final PersistedBilingualSubtitleFiles? files =
        await persistBilingualSubtitleFiles(
          episodeId: 'ep-partial',
          lines: partial,
          appSupportDirectory: () async => temp,
        );
    expect(files, isNotNull);
    final String enRaw = await File(files!.englishPath).readAsString();
    final String zhRaw = await File(files.chinesePath).readAsString();
    expect(enRaw, contains('Hello'));
    expect(enRaw, isNot(contains('世界')));
    expect(zhRaw, contains('你好'));
    expect(zhRaw, contains('世界'));

    final List<PlayerSubtitleLine> reloaded =
        mergePartialEnglishOntoChineseBase(
          chineseLines: parseSubtitleLines(zhRaw),
          englishLines: parseSubtitleLines(enRaw),
        );
    expect(reloaded, hasLength(2));
    expect(reloaded[0].english, 'Hello');
    expect(reloaded[0].chinese, '你好');
    expect(reloaded[1].english, isEmpty);
    expect(reloaded[1].chinese, '世界');
  });

  test('official Chinese timeline is not replaced by OCR cache', () {
    const List<PlayerSubtitleLine> official = <PlayerSubtitleLine>[
      PlayerSubtitleLine(
        startTime: '00:01',
        english: '我要去砍树',
        chinese: '',
        startMs: 1000,
        endMs: 4000,
      ),
      PlayerSubtitleLine(
        startTime: '00:05',
        english: '窗户、云和天空',
        chinese: '',
        startMs: 5000,
        endMs: 8000,
      ),
    ];
    const List<PlayerSubtitleLine> ocrCache = <PlayerSubtitleLine>[
      PlayerSubtitleLine(
        startTime: '06:41',
        english: 'lhave cut past.',
        chinese: '小',
        startMs: 401000,
        endMs: 404000,
      ),
      PlayerSubtitleLine(
        startTime: '00:01',
        english: 'I am going to cut the tree',
        chinese: '小',
        startMs: 1000,
        endMs: 4000,
      ),
    ];
    final List<PlayerSubtitleLine> base = subtitleBaseFromOfficialChinese(
      officialChinese: official,
      cachedLines: ocrCache,
    );
    expect(base, hasLength(2));
    expect(base[0].chinese, '我要去砍树');
    expect(base[0].english, isEmpty);
    expect(base[1].chinese, '窗户、云和天空');
    expect(base[1].english, isEmpty);
  });

  test('saved translation stays on the same Chinese cue', () {
    const List<PlayerSubtitleLine> official = <PlayerSubtitleLine>[
      PlayerSubtitleLine(
        startTime: '00:00',
        english: '',
        chinese: '在这整个视频中，我要你们重点学习的十个单词是冰箱',
        startMs: 0,
        endMs: 8000,
      ),
    ];
    const List<PlayerSubtitleLine> unrelated = <PlayerSubtitleLine>[
      PlayerSubtitleLine(
        startTime: '00:00',
        english: 'And those are calves.',
        chinese: '在这整个视频中，我要你们重点学习的十个单词是冰箱',
        startMs: 0,
        endMs: 8000,
      ),
    ];
    final List<PlayerSubtitleLine> dropped = subtitleBaseFromOfficialChinese(
      officialChinese: official,
      cachedLines: unrelated,
    );
    expect(dropped.single.chinese, contains('冰箱'));
    expect(dropped.single.english, isEmpty);

    const List<PlayerSubtitleLine> translated = <PlayerSubtitleLine>[
      PlayerSubtitleLine(
        startTime: '00:00',
        english: 'In this video, learn these ten words. The first is fridge.',
        chinese: '在这整个视频中，我要你们重点学习的十个单词是冰箱',
        startMs: 0,
        endMs: 8000,
      ),
    ];
    final List<PlayerSubtitleLine> kept = subtitleBaseFromOfficialChinese(
      officialChinese: official,
      cachedLines: translated,
      cachedEnglishIsTranslation: true,
    );
    expect(kept.single.chinese, contains('冰箱'));
    expect(kept.single.english, contains('fridge'));
  });
}
