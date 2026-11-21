import 'package:common_learn_english/features/reading/data/reading_gloss.dart';
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
    test('marks words outside the top set as hard', () {
      final ReadingFrequencyLexicon lexicon = ReadingFrequencyLexicon(
        const <String>{'the', 'is', 'and', 'you'},
      );
      expect(lexicon.isHard('the'), isFalse);
      expect(lexicon.isHard('serendipity'), isTrue);
      expect(lexicon.isCommon('IS'), isTrue);
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
