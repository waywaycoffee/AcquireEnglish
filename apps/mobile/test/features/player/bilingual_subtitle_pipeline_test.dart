import 'dart:async';

import 'package:common_learn_english/features/player/presentation/bilingual_subtitle_helpers.dart';
import 'package:common_learn_english/features/player/presentation/bilingual_subtitle_pipeline.dart';
import 'package:common_learn_english/features/player/presentation/ocr_subtitle_sampler.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
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
  });

  group('bilingual pipeline timeout', () {
    test('marks ocrSlow after timeout when yield is low', () async {
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
      final Completer<void> slowSeen = Completer<void>();
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
          captureFrame: ({
            required player,
            required videoPath,
            required positionMs,
          }) async =>
              null,
          recognizeText: (bytes) async => const <String>[],
        ),
        onPhaseChanged: (BilingualPipelinePhase next) {
          phase = next;
          if (next == BilingualPipelinePhase.ocrSlow && !slowSeen.isCompleted) {
            slowSeen.complete();
          }
        },
      );

      await pipeline.startOcr(
        isPlaying: () => true,
        positionMs: () => 1500,
      );
      await slowSeen.future.timeout(const Duration(seconds: 2));
      expect(phase, BilingualPipelinePhase.ocrSlow);
      expect(pipeline.showAiCompleteButton, isTrue);
      await pipeline.dispose();
    });
  });
}
