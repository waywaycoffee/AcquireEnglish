import 'package:common_learn_english/features/player/presentation/widgets/subtitle_chunk_highlight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches longest known chunks and colors by kind', () {
    final SubtitleChunkHighlighter highlighter = SubtitleChunkHighlighter(
      const <SubtitleChunkEntry>[
        SubtitleChunkEntry(
          phrase: 'look forward to',
          tokens: <String>['look', 'forward', 'to'],
          kind: SubtitleChunkKind.phrase,
          source: 'lexicon',
        ),
        SubtitleChunkEntry(
          phrase: 'in order to',
          tokens: <String>['in', 'order', 'to'],
          kind: SubtitleChunkKind.chunk,
          source: 'lexicon',
        ),
        SubtitleChunkEntry(
          phrase: 'by the way',
          tokens: <String>['by', 'the', 'way'],
          kind: SubtitleChunkKind.chunk,
          source: 'lexicon',
        ),
        SubtitleChunkEntry(
          phrase: 'chaotic',
          tokens: <String>['chaotic'],
          kind: SubtitleChunkKind.vocab,
          source: 'word_book',
        ),
      ],
    );

    final Map<int, SubtitleChunkSpan> hits = highlighter.matchLine(
      'By the way, I look forward to talking.',
    );
    expect(hits[0]?.kind, SubtitleChunkKind.chunk); // by
    expect(hits[1]?.kind, SubtitleChunkKind.chunk); // the
    expect(hits[2]?.kind, SubtitleChunkKind.chunk); // way
    expect(hits[0]?.source, 'lexicon');
    expect(hits[4]?.kind, SubtitleChunkKind.phrase); // look
    expect(hits[5]?.kind, SubtitleChunkKind.phrase); // forward
    expect(hits[6]?.kind, SubtitleChunkKind.phrase); // to
    expect(hits.containsKey(7), isFalse); // talking

    final Map<int, SubtitleChunkSpan> vocabHits = highlighter.matchLine(
      'The city was too chaotic for them.',
    );
    expect(vocabHits[4]?.kind, SubtitleChunkKind.vocab);
    expect(vocabHits[4]?.source, 'word_book');

    expect(SubtitleChunkKind.vocab.labelCn, '生词');
    expect(SubtitleChunkKindLabel.fromName('用法'), SubtitleChunkKind.chunk);
    expect(SubtitleChunkKindLabel.fromName('生词'), SubtitleChunkKind.vocab);

    expect(
      SubtitleChunkHighlighter.fill(
        SubtitleChunkKind.chunk,
        onDarkVideo: false,
      ),
      isNot(
        SubtitleChunkHighlighter.fill(
          SubtitleChunkKind.vocab,
          onDarkVideo: false,
        ),
      ),
    );

    final List<SubtitleLineMark> marks = highlighter.marksForLine(
      'By the way, I look forward to talking.',
    );
    expect(marks, isNotEmpty);
    expect(marks.first.kind, SubtitleChunkKind.chunk);
    expect(marks.any((SubtitleLineMark m) => m.kind == SubtitleChunkKind.phrase), isTrue);
  });
}
