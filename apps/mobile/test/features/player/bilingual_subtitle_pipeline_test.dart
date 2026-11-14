import 'dart:async';

import 'package:common_learn_english/features/player/presentation/bilingual_subtitle_helpers.dart';
import 'package:common_learn_english/features/player/presentation/bilingual_subtitle_pipeline.dart';
import 'package:common_learn_english/features/player/presentation/ocr_subtitle_sampler.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:common_learn_english/features/shared/data/word_lookup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bilingual subtitle helpers', () {
    test('splitOcrTextBlocks separates EN and ZH lines', () {
      final OcrCueText cue = splitOcrTextBlocks(const <String>[
        'Hello world',
        '你好世界',
        'Good morning 早上好',
      ]);
      expect(cue.english.toLowerCase().contains('hello'), isTrue);
      expect(cue.english.toLowerCase().contains('good'), isTrue);
      expect(cue.chinese.contains('你好'), isTrue);
      expect(cue.chinese.contains('早上'), isTrue);
    });

    test('proofreadOnly keeps translation when OCR is junk or a fragment', () {
      final List<PlayerSubtitleLine> seed = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '06:30',
          english: 'I am going to cut the tree',
          chinese: '我要去砍树',
          startMs: 390000,
          endMs: 394000,
        ),
      ];
      final List<PlayerSubtitleLine> junk = mergeOcrCueIntoLines(
        lines: seed,
        positionMs: 391000,
        cue: const OcrCueText(english: 'Uam going to cut the'),
        proofreadOnly: true,
      );
      expect(junk.single.english, 'I am going to cut the tree');
      final List<PlayerSubtitleLine> empty = mergeOcrCueIntoLines(
        lines: <PlayerSubtitleLine>[
          const PlayerSubtitleLine(
            startTime: '06:30',
            english: '我要去砍树',
            chinese: '我要去砍树',
            startMs: 390000,
            endMs: 394000,
          ),
        ],
        positionMs: 391000,
        cue: const OcrCueText(english: 'I am going to cut the'),
        proofreadOnly: true,
      );
      expect(empty.single.english.toLowerCase(), isNot(contains('going')));
      expect(empty.single.chinese, contains('砍'));
    });

    test('repairOcrEnglishSpacing splits glued hardsub words', () {
      expect(
        repairOcrEnglishSpacing('agate, andright now'),
        'a gate, and right now',
      );
      expect(repairOcrEnglishSpacing('Trees haveleafs,'), 'Trees have leafs,');
      expect(ocrEnglishLooksGlued('agate, andright now'), isTrue);
      expect(ocrEnglishLooksGlued('a gate, and right now'), isFalse);
    });

    test('fuseOcrWithAsrLines prefers ASR for glued OCR English', () {
      final List<PlayerSubtitleLine> working = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '05:31',
          english: 'agate, andright now',
          chinese: '一扇门，现在',
          startMs: 331000,
          endMs: 334000,
        ),
      ];
      final List<PlayerSubtitleLine> asr = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '05:30',
          english: 'a gate, and right now',
          chinese: '',
          startMs: 330500,
          endMs: 334500,
        ),
      ];
      final List<PlayerSubtitleLine> fused = fuseOcrWithAsrLines(
        working: working,
        asrLines: asr,
      );
      expect(fused.single.english, 'a gate, and right now');
      expect(fused.single.chinese, '一扇门，现在');
    });

    test('detectMissingSubtitleSide finds chinese-only and english-only', () {
      final List<PlayerSubtitleLine> zhOnly = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '00:01',
          english: '这是中文',
          chinese: '这是中文',
          startMs: 1000,
          endMs: 2000,
        ),
      ];
      expect(detectMissingSubtitleSide(zhOnly), MissingSubtitleSide.english);

      final List<PlayerSubtitleLine> enOnly = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '00:01',
          english: 'This is English',
          chinese: '',
          startMs: 1000,
          endMs: 2000,
        ),
      ];
      expect(detectMissingSubtitleSide(enOnly), MissingSubtitleSide.chinese);
      expect(isReliableOcrEnglish('This is English'), isTrue);
      expect(isReliableOcrEnglish('Uam going to cut the'), isFalse);
      final List<PlayerSubtitleLine> junkOcr = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '06:30',
          english: 'Uam going to cut the',
          chinese: '我要去砍树',
          startMs: 390000,
          endMs: 393000,
        ),
      ];
      expect(detectMissingSubtitleSide(junkOcr), MissingSubtitleSide.english);

      final List<PlayerSubtitleLine> both = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '00:01',
          english: 'This is English',
          chinese: '这是中文',
          startMs: 1000,
          endMs: 2000,
        ),
      ];
      expect(detectMissingSubtitleSide(both), MissingSubtitleSide.none);
      expect(needsBilingualFill(zhOnly), isTrue);
      expect(needsBilingualFill(both), isFalse);

      // Even one missing English line must keep fill running.
      final List<PlayerSubtitleLine> mostlyZh = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Hello',
          chinese: '你好',
          startMs: 1000,
          endMs: 2000,
        ),
        const PlayerSubtitleLine(
          startTime: '00:02',
          english: '',
          chinese: '只有中文一',
          startMs: 2000,
          endMs: 3000,
        ),
        const PlayerSubtitleLine(
          startTime: '00:03',
          english: 'World',
          chinese: '世界',
          startMs: 3000,
          endMs: 4000,
        ),
      ];
      expect(detectMissingSubtitleSide(mostlyZh), MissingSubtitleSide.english);
      expect(needsBilingualFill(mostlyZh), isTrue);
    });

    test('mergeOcrCueIntoLines aligns within tolerance', () {
      final List<PlayerSubtitleLine> seed = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '00:10',
          english: '这是中文',
          chinese: '这是中文',
          startMs: 10000,
          endMs: 12000,
        ),
      ];
      final List<PlayerSubtitleLine> merged = mergeOcrCueIntoLines(
        lines: seed,
        positionMs: 10500,
        cue: const OcrCueText(english: 'Hello there'),
      );
      expect(merged, hasLength(1));
      expect(merged.first.english, 'Hello there');
      expect(merged.first.chinese, '这是中文');
    });

    test('mergeOcrCueIntoLines ignores non-English OCR latin noise', () {
      final List<PlayerSubtitleLine> seed = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '00:10',
          english: 'Hello world',
          chinese: '你好世界',
          startMs: 10000,
          endMs: 12000,
        ),
      ];
      final List<PlayerSubtitleLine> merged = mergeOcrCueIntoLines(
        lines: seed,
        positionMs: 10500,
        cue: const OcrCueText(english: '你好世界'),
      );
      expect(merged.single.english, 'Hello world');
      expect(merged.single.chinese, '你好世界');
    });

    test(
      'mergeOcrCueIntoLines keeps a translation that matches the hardsub',
      () {
        final List<PlayerSubtitleLine> seed = <PlayerSubtitleLine>[
          const PlayerSubtitleLine(
            startTime: '00:10',
            english: 'So I did not bring water to drink',
            chinese: '所以没带水喝',
            startMs: 10000,
            endMs: 12000,
          ),
        ];
        final List<PlayerSubtitleLine> merged = mergeOcrCueIntoLines(
          lines: seed,
          positionMs: 10500,
          cue: const OcrCueText(english: 'I did not bring any water'),
        );
        expect(merged.single.english, 'So I did not bring water to drink');
        expect(merged.single.chinese, '所以没带水喝');
      },
    );

    test('unrelated translation loses to a real hardsub', () {
      final List<PlayerSubtitleLine> seed = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '06:30',
          english: 'The weather is beautiful today',
          chinese: '我要去砍树',
          startMs: 390000,
          endMs: 394000,
        ),
      ];
      final List<PlayerSubtitleLine> proved = mergeOcrCueIntoLines(
        lines: seed,
        positionMs: 391000,
        cue: const OcrCueText(english: 'I am going to cut the'),
        proofreadOnly: true,
      );
      expect(proved.single.english, 'I am going to cut the');
      final List<PlayerSubtitleLine> fragment = mergeOcrCueIntoLines(
        lines: <PlayerSubtitleLine>[
          const PlayerSubtitleLine(
            startTime: '06:30',
            english: 'I am going to cut the tree',
            chinese: '我要去砍树',
            startMs: 390000,
            endMs: 394000,
          ),
        ],
        positionMs: 391000,
        cue: const OcrCueText(english: 'I am going'),
        proofreadOnly: true,
      );
      expect(fragment.single.english, 'I am going to cut the tree');
    });

    test('fuseOcrWithAsrLines replaces an unrelated translation', () {
      final List<PlayerSubtitleLine> working = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '06:30',
          english: 'The weather is beautiful today',
          chinese: '我要去砍树',
          startMs: 390000,
          endMs: 394000,
        ),
      ];
      final List<PlayerSubtitleLine> asr = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '06:30',
          english: 'I am going to cut the tree',
          chinese: '',
          startMs: 390200,
          endMs: 393800,
        ),
      ];
      final List<PlayerSubtitleLine> fused = fuseOcrWithAsrLines(
        working: working,
        asrLines: asr,
      );
      expect(fused.single.english, 'I am going to cut the tree');
      expect(fused.single.chinese, contains('砍'));
    });

    test('fuseOcrWithAsrLines prefers spoken wording over a paraphrase', () {
      final List<PlayerSubtitleLine> working = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '17:20',
          english: "There's water all over the floor.",
          chinese: '地上到处都是水',
          startMs: 1040000,
          endMs: 1044000,
        ),
      ];
      final List<PlayerSubtitleLine> asr = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '17:20',
          english: 'There is a lot of water',
          chinese: '',
          startMs: 1040100,
          endMs: 1043800,
        ),
      ];
      final List<PlayerSubtitleLine> fused = fuseOcrWithAsrLines(
        working: working,
        asrLines: asr,
      );
      expect(fused.single.english, 'There is a lot of water');
      expect(fused.single.chinese, contains('水'));
    });

    test('fuseOcrWithAsrLines keeps a fuller line over a clipped ASR fragment', () {
      final List<PlayerSubtitleLine> working = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '06:30',
          english: 'I am going to cut the tree',
          chinese: '我要去砍树',
          startMs: 390000,
          endMs: 394000,
        ),
      ];
      final List<PlayerSubtitleLine> asr = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '06:30',
          english: 'I am going',
          chinese: '',
          startMs: 390200,
          endMs: 391000,
        ),
      ];
      final List<PlayerSubtitleLine> fused = fuseOcrWithAsrLines(
        working: working,
        asrLines: asr,
      );
      expect(fused.single.english, 'I am going to cut the tree');
    });

    test('keepManualEnglish survives a later proofread', () {
      final List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '06:30',
          english: 'The weather is beautiful today',
          chinese: '我要去砍树',
          startMs: 390000,
          endMs: 394000,
        ),
      ];
      final List<PlayerSubtitleLine> kept = keepManualEnglish(
        lines: lines,
        manualEnglishByStartMs: const <int, String>{
          390000: 'I am going to cut the tree',
        },
      );
      expect(kept.single.english, 'I am going to cut the tree');
      expect(kept.single.chinese, contains('砍'));
    });

    test('mergeOcrCueIntoLines appends when no cue nearby', () {
      final List<PlayerSubtitleLine> seed = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Old',
          chinese: '旧',
          startMs: 1000,
          endMs: 2000,
        ),
      ];
      final List<PlayerSubtitleLine> merged = mergeOcrCueIntoLines(
        lines: seed,
        positionMs: 60000,
        cue: const OcrCueText(english: 'New line', chinese: '新句子'),
        toleranceMs: 500,
      );
      expect(merged, hasLength(2));
      expect(merged.last.english, 'New line');
      expect(merged.last.chinese, '新句子');
      expect(merged.last.startMs, lessThanOrEqualTo(60000));
      expect(merged.last.endMs, greaterThan(60000));
    });

    test('mergeOcrCueIntoLines extends same hardsub along the video clock', () {
      List<PlayerSubtitleLine> lines = mergeOcrCueIntoLines(
        lines: const <PlayerSubtitleLine>[],
        positionMs: 10000,
        cue: const OcrCueText(english: 'Hello there'),
        holdMs: 1800,
        leadMs: 200,
      );
      expect(lines, hasLength(1));
      expect(lines.single.startMs, 9800);
      expect(lines.single.endMs, 11800);

      lines = mergeOcrCueIntoLines(
        lines: lines,
        positionMs: 11200,
        cue: const OcrCueText(english: 'Hello there'),
        holdMs: 1800,
        leadMs: 200,
      );
      expect(lines, hasLength(1));
      expect(lines.single.english, 'Hello there');
      expect(lines.single.endMs, 13000);
    });

    test('fillMissingSideByTranslation fills chinese', () {
      final List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Hello',
          chinese: '',
          startMs: 1000,
          endMs: 2000,
        ),
      ];
      final List<PlayerSubtitleLine> filled = fillMissingSideByTranslation(
        lines: lines,
        missing: MissingSubtitleSide.chinese,
        translations: const <String>['你好'],
      );
      expect(filled.single.chinese, '你好');
      expect(filled.single.english, 'Hello');
    });

    test('fillMissingSideByTranslation fills english from chinese', () {
      final List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '00:01',
          english: '',
          chinese: '所以没带水喝',
          startMs: 1000,
          endMs: 2000,
        ),
      ];
      final List<PlayerSubtitleLine> filled = fillMissingSideByTranslation(
        lines: lines,
        missing: MissingSubtitleSide.english,
        translations: const <String>['So I did not bring water to drink'],
      );
      expect(filled.single.english, 'So I did not bring water to drink');
      expect(filled.single.chinese, '所以没带水喝');
    });

    test('both-missing fill keeps chinese and writes english only', () {
      final List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '00:01',
          english: '只有中文',
          chinese: '',
          startMs: 1000,
          endMs: 2000,
        ),
      ];
      final List<PlayerSubtitleLine> filled = fillMissingSideByTranslation(
        lines: lines,
        missing: MissingSubtitleSide.both,
        translations: const <String>['Only Chinese before'],
      );
      expect(filled.single.english, 'Only Chinese before');
      expect(filled.single.chinese, '只有中文');
    });

    test('fillMissingEnglishByTranslation prioritizes playhead window', () async {
      final List<PlayerSubtitleLine> lines = List<PlayerSubtitleLine>.generate(
        12,
        (int i) => PlayerSubtitleLine(
          startTime: '00:${(i + 1).toString().padLeft(2, '0')}',
          english: '',
          chinese: '中文$i',
          startMs: i * 1000,
          endMs: i * 1000 + 900,
        ),
      );
      final List<int> firstEnglishIndexes = <int>[];
      final List<PlayerSubtitleLine> filled =
          await BilingualSubtitlePipeline.fillMissingEnglishByTranslation(
            lines: lines,
            settings: LearningSettingsState.defaults(),
            wordLookup: _RecordingFreeTranslateLookup(),
            prioritizeAroundMs: 8500,
            onLinesUpdated: (List<PlayerSubtitleLine> partial) {
              for (int i = 0; i < partial.length; i++) {
                if (partial[i].english.trim().isNotEmpty &&
                    !firstEnglishIndexes.contains(i)) {
                  firstEnglishIndexes.add(i);
                }
              }
            },
          );
      expect(
        filled.every((PlayerSubtitleLine l) => l.english.isNotEmpty),
        isTrue,
      );
      // Playhead ~8.5s → index 8; first applied window should cover nearby cues.
      expect(
        firstEnglishIndexes.take(6),
        containsAll(<int>[6, 7, 8, 9, 10, 11]),
      );
    });

    test(
      'fillMissingEnglishByTranslation replaces unrelated English on a Chinese cue',
      () async {
        final List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
          const PlayerSubtitleLine(
            startTime: '00:01',
            english: '',
            chinese: '第一句',
            startMs: 0,
            endMs: 900,
          ),
          const PlayerSubtitleLine(
            startTime: '00:02',
            english: '',
            chinese: '第二句',
            startMs: 1000,
            endMs: 1900,
          ),
        ];
        List<PlayerSubtitleLine> live = List<PlayerSubtitleLine>.of(lines);
        // Simulate OCR upgrading cue 0 while translation is in flight.
        live = <PlayerSubtitleLine>[
          const PlayerSubtitleLine(
            startTime: '00:01',
            english: 'I am going to cut the tree',
            chinese: '第一句',
            startMs: 0,
            endMs: 900,
          ),
          lines[1],
        ];
        final List<PlayerSubtitleLine> filled =
            await BilingualSubtitlePipeline.fillMissingEnglishByTranslation(
              lines: lines,
              settings: LearningSettingsState.defaults(),
              wordLookup: _RecordingFreeTranslateLookup(),
              currentLines: () => live,
              onLinesUpdated: (List<PlayerSubtitleLine> partial) {
                live = partial;
              },
            );
        expect(filled[0].english, contains('Translated'));
        expect(filled[0].english, isNot(contains('cut the tree')));
        expect(filled[0].chinese, '第一句');
        expect(filled[1].english.trim().isNotEmpty, isTrue);
        expect(filled[1].english, isNot(contains('cut the tree')));
        expect(filled[1].chinese, '第二句');
      },
    );

    test(
      'fillMissingEnglishByTranslation replaces junk OCR with Chinese translation',
      () async {
        final List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
          const PlayerSubtitleLine(
            startTime: '06:30',
            english: 'Uam going to cut the',
            chinese: '我要去砍树',
            startMs: 390000,
            endMs: 393000,
          ),
        ];
        final List<PlayerSubtitleLine> filled =
            await BilingualSubtitlePipeline.fillMissingEnglishByTranslation(
              lines: lines,
              settings: LearningSettingsState.defaults(),
              wordLookup: _RecordingFreeTranslateLookup(),
              currentLines: () => lines,
            );
        expect(filled.single.english.toLowerCase(), isNot(contains('uam')));
        expect(filled.single.english, contains('Translated'));
        expect(filled.single.chinese, contains('砍'));
      },
    );
  });

  group('bilingual pipeline timeout', () {
    test('chinese timeline skips OCR and prefers speech when possible', () async {
      final List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '00:01',
          english: '只有中文',
          chinese: '只有中文',
          startMs: 1000,
          endMs: 2000,
        ),
      ];
      BilingualPipelinePhase phase = BilingualPipelinePhase.idle;
      bool askedTranslation = false;
      final BilingualSubtitlePipeline pipeline = BilingualSubtitlePipeline(
        episodeId: 'ep-test',
        videoPath: '/tmp/missing-video-for-pipeline-test.mp4',
        settings: LearningSettingsState.defaults(),
        getLines: () => lines,
        setLines: (List<PlayerSubtitleLine> next) {
          lines
            ..clear()
            ..addAll(next);
        },
        slowTimeout: const Duration(milliseconds: 40),
        minFilledCues: 2,
        sampler: OcrSubtitleSampler(
          interval: const Duration(hours: 1),
          captureFrame:
              ({
                required player,
                required videoPath,
                required positionMs,
              }) async => null,
          recognizeText: (bytes) async => const <String>[],
        ),
        onNeedTranslationFallback: () {
          askedTranslation = true;
        },
        onPhaseChanged: (BilingualPipelinePhase next) {
          phase = next;
        },
      );

      await pipeline.startOcr(isPlaying: () => true, positionMs: () => 1500);
      // No local MP4 → cannot ASR; fall back to ZH→EN only (never OCR).
      expect(phase, BilingualPipelinePhase.translating);
      expect(askedTranslation, isTrue);
      await pipeline.dispose();
    });
  });

  group('replaceLines subtitle clock', () {
    test('replaceLines rebinds active cue with subtitleDelayMs', () {
      final PlayerMockState state = PlayerMockState()
        ..loadLines(const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '00:01',
            english: 'One',
            chinese: '一',
            startMs: 0,
            endMs: 1000,
          ),
          PlayerSubtitleLine(
            startTime: '00:02',
            english: 'Two',
            chinese: '二',
            startMs: 1000,
            endMs: 2000,
          ),
          PlayerSubtitleLine(
            startTime: '00:03',
            english: 'Three',
            chinese: '三',
            startMs: 2000,
            endMs: 3000,
          ),
        ])
        ..subtitleDelayMs = 500
        ..seekToMilliseconds(1600);
      // Wall clock 1600 with delay 500 → subtitle clock 1100 → cue "Two".
      expect(state.activeLineIndex, 1);
      state.replaceLines(const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'One updated',
          chinese: '一',
          startMs: 0,
          endMs: 1000,
        ),
        PlayerSubtitleLine(
          startTime: '00:02',
          english: 'Two updated',
          chinese: '二',
          startMs: 1000,
          endMs: 2000,
        ),
        PlayerSubtitleLine(
          startTime: '00:03',
          english: 'Three updated',
          chinese: '三',
          startMs: 2000,
          endMs: 3000,
        ),
      ]);
      expect(state.positionMs, 1600);
      expect(state.activeLineIndex, 1);
    });
  });
}

class _RecordingFreeTranslateLookup extends WordLookupService {
  int _seq = 0;

  String _englishFor(String source) {
    _seq += 1;
    return 'Translated sentence number $_seq about ${source.hashCode.abs()}';
  }

  @override
  Future<List<String>> translateSentencesFreeParallel({
    required List<String> sentences,
    required bool toEnglish,
    int concurrency = 6,
  }) async {
    return sentences
        .map((String s) => s.trim().isEmpty ? '' : _englishFor(s))
        .toList(growable: false);
  }

  @override
  Future<String?> translateSentence({
    required String sentence,
    required LearningSettingsState settings,
    String targetLanguage = 'zh',
  }) async {
    final String text = sentence.trim();
    return text.isEmpty ? null : _englishFor(text);
  }

  @override
  Future<List<String>> translateSentences({
    required List<String> sentences,
    required LearningSettingsState settings,
    String targetLanguage = 'zh',
  }) async {
    return sentences
        .map((String s) => s.trim().isEmpty ? '' : _englishFor(s))
        .toList(growable: false);
  }
}
