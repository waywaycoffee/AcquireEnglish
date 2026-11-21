import 'package:common_learn_english/features/reading/data/reading_gloss.dart';
import 'package:common_learn_english/features/reading/data/reading_ingest.dart';
import 'package:common_learn_english/features/reading/domain/reading_study_mode.dart';
import 'package:common_learn_english/features/reading/presentation/reading_text_spans.dart';
import 'package:common_learn_english/features/player/presentation/widgets/subtitle_chunk_highlight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shortReadingGloss', () {
    test('keeps first Chinese sense', () {
      expect(
        shortReadingGloss(r"n. 苹果, 家伙\n[医] 苹果"),
        '苹果',
      );
      expect(shortReadingGloss('vt. 承认, 告知收悉'), '承认');
    });
  });

  group('ReadingFrequencyLexicon', () {
    test('marks words outside the threshold as hard', () {
      final ReadingFrequencyLexicon lexicon = ReadingFrequencyLexicon(
        const <String, int>{'the': 1, 'is': 2, 'and': 3, 'you': 4},
      );
      expect(lexicon.isHard('the', threshold: 3), isFalse);
      expect(lexicon.isHard('you', threshold: 3), isTrue);
      expect(lexicon.isHard('serendipity', threshold: 3), isTrue);
      expect(lexicon.rankOf('IS'), 2);
    });
  });

  group('unknownWordRate', () {
    test('computes share above threshold', () {
      final ReadingFrequencyLexicon lexicon = ReadingFrequencyLexicon(
        const <String, int>{'the': 1, 'cat': 100, 'serendipity': 9000},
      );
      final double rate = unknownWordRate(
        words: const <String>['the', 'cat', 'serendipity'],
        lexicon: lexicon,
        threshold: 3000,
      );
      expect(rate, closeTo(1 / 3, 0.001));
    });
  });

  group('ReadingStudyMode', () {
    test('defaults to immersion', () {
      expect(
        ReadingStudyModeX.fromStorage(null),
        ReadingStudyMode.immersion,
      );
      expect(ReadingStudyMode.immersion.showInlineChinese, isFalse);
      expect(ReadingStudyMode.intensive.showInlineChinese, isTrue);
    });
  });

  group('sentenceBounds', () {
    test('expands to surrounding clause', () {
      const String text = 'Hello there. This is a test sentence! Next.';
      final ({int start, int end, String text}) b =
          sentenceBounds(text, 14, 16); // "is"
      expect(b.text, 'This is a test sentence!');
    });
  });

  group('stripMarkdownLight', () {
    test('strips headings and links', () {
      const String md = '# Title\n\nHello **world** and [link](https://x.test).';
      final String plain = stripMarkdownLight(md);
      expect(plain, contains('Title'));
      expect(plain, contains('Hello world'));
      expect(plain, contains('link'));
      expect(plain, isNot(contains('https://')));
      expect(plain, isNot(contains('##')));
    });
  });

  group('tokenizeReadingText', () {
    test('splits words and punctuation', () {
      final List<ReadingToken> tokens = tokenizeReadingText("Don't give up.");
      expect(tokens.map((ReadingToken t) => t.raw).toList(), <String>[
        "Don't",
        ' ',
        'give',
        ' ',
        'up',
        '.',
      ]);
    });
  });

  group('chunk matching for reading', () {
    test('highlights short phrasal verbs', () {
      final SubtitleChunkHighlighter highlighter = SubtitleChunkHighlighter(
        const <SubtitleChunkEntry>[
          SubtitleChunkEntry(
            phrase: 'give up',
            tokens: <String>['give', 'up'],
            kind: SubtitleChunkKind.phrase,
          ),
        ],
      );
      final Map<int, SubtitleChunkSpan> hits =
          highlighter.matchLine("Don't give up now");
      expect(hits[1]?.phrase, 'give up');
      expect(hits[2]?.phrase, 'give up');
    });
  });
}
