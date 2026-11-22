import 'package:common_learn_english/features/reading/data/reading_continuous_tts.dart';
import 'package:common_learn_english/features/reading/data/reading_gloss.dart';
import 'package:common_learn_english/features/reading/data/reading_iplus1.dart';
import 'package:common_learn_english/features/reading/data/reading_ingest.dart';
import 'package:common_learn_english/features/reading/data/reading_vocab_lists.dart';
import 'package:common_learn_english/features/reading/domain/reading_doc.dart';
import 'package:common_learn_english/features/reading/domain/reading_study_mode.dart';
import 'package:common_learn_english/features/reading/presentation/reading_text_spans.dart';
import 'package:common_learn_english/features/player/presentation/widgets/subtitle_chunk_highlight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shortReadingGloss', () {
    test('keeps first Chinese sense', () {
      expect(shortReadingGloss(r"n. 苹果, 家伙\n[医] 苹果"), '苹果');
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
      expect(ReadingStudyModeX.fromStorage(null), ReadingStudyMode.immersion);
      expect(ReadingStudyMode.immersion.showInlineChinese, isFalse);
      expect(ReadingStudyMode.intensive.showInlineChinese, isTrue);
    });
  });

  group('sentenceBounds', () {
    test('expands to surrounding clause', () {
      const String text = 'Hello there. This is a test sentence! Next.';
      final ({int start, int end, String text}) b = sentenceBounds(
        text,
        14,
        16,
      ); // "is"
      expect(b.text, 'This is a test sentence!');
    });
  });

  group('stripMarkdownLight', () {
    test('strips headings and links', () {
      const String md =
          '# Title\n\nHello **world** and [link](https://x.test).';
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
      final Map<int, SubtitleChunkSpan> hits = highlighter.matchLine(
        "Don't give up now",
      );
      expect(hits[1]?.phrase, 'give up');
      expect(hits[2]?.phrase, 'give up');
    });
  });

  group('splitReadingSpeakUnits', () {
    test('splits sentences with word indices', () {
      const String text = 'Hello world. Give up now!';
      final List<ReadingSpeakUnit> units = splitReadingSpeakUnits(text);
      expect(units.length, greaterThanOrEqualTo(2));
      expect(units.first.text, contains('Hello'));
      expect(units.first.wordCount, 2);
      expect(units[1].firstWordIndex, 2);
    });

    test('keeps word indices aligned across a long book', () {
      final text = List.filled(3000, 'Dorothy walked home.').join(' ');
      final units = splitReadingSpeakUnits(text);
      expect(units.length, 3000);
      expect(units.last.firstWordIndex, 8997);
      expect(units.last.wordCount, 3);
    });
  });

  group('estimatedMsPerWord', () {
    test('slows down when rate decreases', () {
      expect(estimatedMsPerWord(0.5), greaterThan(estimatedMsPerWord(1.0)));
    });
  });

  group('vocab lists + i+1', () {
    final ReadingFrequencyLexicon lexicon = ReadingFrequencyLexicon(
      const <String, int>{
        'the': 1,
        'cat': 100,
        'sat': 200,
        'mat': 300,
        'serendipity': 9000,
      },
    );

    test('whitelist suppresses hard; blacklist forces hard', () {
      expect(
        isReadingHardWord(
          word: 'serendipity',
          lexicon: lexicon,
          threshold: 3000,
          known: const <String>{'serendipity'},
        ),
        isFalse,
      );
      expect(
        isReadingHardWord(
          word: 'the',
          lexicon: lexicon,
          threshold: 3000,
          focus: const <String>{'the'},
        ),
        isTrue,
      );
    });

    test('unknownWordRate respects lists', () {
      final double rate = unknownWordRate(
        words: const <String>['the', 'cat', 'serendipity'],
        lexicon: lexicon,
        threshold: 3000,
        known: const <String>{'serendipity'},
      );
      expect(rate, 0);
    });

    test('i+1 fitness peaks inside ideal band', () {
      expect(iPlus1Fitness(0.04), 1.0);
      expect(iPlus1Fitness(0.0), lessThan(1.0));
      expect(iPlus1Fitness(0.25), lessThan(iPlus1Fitness(0.10)));
      expect(bandForUnknownRate(0.04), ReadingIPlus1Band.ideal);
      expect(bandForUnknownRate(0.01), ReadingIPlus1Band.tooEasy);
    });

    test('rankDocsForIPlus1 prefers ideal unknown rate', () {
      // 1/20 = 5% unknown → ideal.
      final String idealText =
          List<String>.filled(19, 'the').join(' ') + ' serendipity';
      const ReadingDoc hard = ReadingDoc(
        id: 'hard',
        title: 'Hard',
        sourceType: ReadingSourceType.builtin,
        plainText: 'serendipity serendipity serendipity serendipity',
      );
      final ReadingDoc ideal = ReadingDoc(
        id: 'ideal',
        title: 'Ideal',
        sourceType: ReadingSourceType.builtin,
        plainText: idealText,
      );
      final List<ReadingIPlus1Match> ranked = rankDocsForIPlus1(
        docs: <ReadingDoc>[hard, ideal],
        lexicon: lexicon,
        threshold: 3000,
        limit: 2,
      );
      expect(ranked.first.doc.id, 'ideal');
      expect(ranked.first.band, ReadingIPlus1Band.ideal);
      expect(ranked.last.doc.id, 'hard');
    });

    test('ReadingVocabLists markKnown removes from focus', () {
      final ReadingVocabLists lists = const ReadingVocabLists(
        focus: <String>{'apple'},
      ).markKnown('Apple');
      expect(lists.isKnown('apple'), isTrue);
      expect(lists.isFocus('apple'), isFalse);
    });

    test('slash known word is no longer hard for inline Chinese', () {
      final ReadingFrequencyLexicon lexicon = ReadingFrequencyLexicon(
        const <String, int>{'the': 1},
      );
      expect(
        isReadingHardWord(
          word: 'serendipity',
          lexicon: lexicon,
          threshold: 3000,
          focus: <String>{'serendipity'},
        ),
        isTrue,
      );
      expect(
        isReadingHardWord(
          word: 'serendipity',
          lexicon: lexicon,
          threshold: 3000,
          known: <String>{'serendipity'},
          focus: <String>{'serendipity'},
        ),
        isFalse,
      );
    });
  });
}
