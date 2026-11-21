import 'dart:convert';
import 'dart:typed_data';

import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/reading/data/reading_ingest.dart';
import 'package:common_learn_english/features/reading/domain/reading_doc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cleanSubtitleEnglish', () {
    test('strips markers and collapses space', () {
      expect(
        cleanSubtitleEnglish('  Hello [music] (laughs) world  '),
        'Hello world',
      );
    });
  });

  group('splitSubtitlesIntoReadingDocs', () {
    test('chunks long subtitle lists into 200-600 word docs', () {
      final List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
        for (int i = 0; i < 120; i++)
          PlayerSubtitleLine(
            startTime: '00:00:${i.toString().padLeft(2, '0')}',
            english: 'This is sample sentence number $i with extra words here.',
            chinese: '',
            startMs: i * 1000,
            endMs: i * 1000 + 900,
          ),
      ];
      final List<ReadingDoc> docs = splitSubtitlesIntoReadingDocs(
        lines: lines,
        courseId: 'c1',
        episodeId: 'e1',
        courseTitle: 'Course',
        episodeTitle: 'Ep1',
        now: DateTime.utc(2026, 1, 1),
      );
      expect(docs, isNotEmpty);
      for (final ReadingDoc doc in docs) {
        expect(doc.sourceType, ReadingSourceType.video);
        expect(doc.episodeId, 'e1');
        expect(doc.wordCount, greaterThanOrEqualTo(50));
        expect(doc.wordCount, lessThanOrEqualTo(kReadingChunkMaxWords + 20));
      }
    });

    test('keeps short episode as one doc', () {
      final List<ReadingDoc> docs = splitSubtitlesIntoReadingDocs(
        lines: const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '0',
            english: 'Hello world from a short clip.',
            chinese: '',
            startMs: 0,
            endMs: 1000,
          ),
        ],
        courseId: 'c',
        episodeId: 'e',
        courseTitle: 'C',
        episodeTitle: 'E',
      );
      expect(docs, hasLength(1));
      expect(docs.first.plainText, contains('Hello world'));
    });
  });

  group('parseTxtImport', () {
    test('strips bom and trims', () {
      final Uint8List bytes = Uint8List.fromList(
        utf8.encode('\uFEFFHello reading\n'),
      );
      expect(parseTxtImport(bytes), 'Hello reading');
    });
  });

  group('ReadingProgress', () {
    test('round-trips json', () {
      final ReadingProgress p = ReadingProgress(
        docId: 'd1',
        offsetChars: 12,
        percent: 0.4,
        lastOpenedAt: DateTime.utc(2026, 2, 1),
        completed: false,
      );
      final ReadingProgress again = ReadingProgress.fromJson(p.toJson());
      expect(again.docId, 'd1');
      expect(again.offsetChars, 12);
      expect(again.percent, closeTo(0.4, 0.001));
      expect(again.completed, isFalse);
    });
  });
}
