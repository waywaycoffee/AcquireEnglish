import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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

  group('parseEpubImport', () {
    test('extracts xhtml body text from zip', () {
      final Archive archive = Archive();
      final List<int> chapter = utf8.encode(
        '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
        '<p>The cafe opens early.</p>'
        '<p>I order coffee to go.</p>'
        '</body></html>',
      );
      final List<int> colophon = utf8.encode(
        '<html><body><p>Should be skipped colophon.</p></body></html>',
      );
      archive.addFile(
        ArchiveFile('OEBPS/chapter-1.xhtml', chapter.length, chapter),
      );
      archive.addFile(
        ArchiveFile('OEBPS/colophon.xhtml', colophon.length, colophon),
      );
      final List<int>? encoded = ZipEncoder().encode(archive);
      expect(encoded, isNotNull);
      final String text = parseEpubImport(Uint8List.fromList(encoded!));
      expect(text, contains('cafe opens early'));
      expect(text, contains('coffee to go'));
      expect(text, isNot(contains('colophon')));
    });

    test('rejects non-zip payloads', () {
      expect(
        () => parseEpubImport(Uint8List.fromList(utf8.encode('<html>nope</html>'))),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('titleFromFilename', () {
    test('strips extension', () {
      expect(titleFromFilename('My Book.epub'), 'My Book');
      expect(titleFromFilename(r'C:\tmp\sample_cafe.txt'), 'sample_cafe');
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
