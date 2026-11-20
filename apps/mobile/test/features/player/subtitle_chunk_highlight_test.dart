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
        ),
        SubtitleChunkEntry(
          phrase: 'in order to',
          tokens: <String>['in', 'order', 'to'],
          kind: SubtitleChunkKind.usage,
        ),
        SubtitleChunkEntry(
          phrase: 'by the way',
          tokens: <String>['by', 'the', 'way'],
          kind: SubtitleChunkKind.chunk,
        ),
      ],
    );

    final Map<int, SubtitleChunkSpan> hits = highlighter.matchLine(
      'By the way, I look forward to talking.',
    );
    expect(hits[0]?.kind, SubtitleChunkKind.chunk); // by
    expect(hits[1]?.kind, SubtitleChunkKind.chunk); // the
    expect(hits[2]?.kind, SubtitleChunkKind.chunk); // way
    expect(hits[4]?.kind, SubtitleChunkKind.phrase); // look
    expect(hits[5]?.kind, SubtitleChunkKind.phrase); // forward
    expect(hits[6]?.kind, SubtitleChunkKind.phrase); // to
    expect(hits.containsKey(7), isFalse); // talking

    expect(
      SubtitleChunkHighlighter.fill(
        SubtitleChunkKind.chunk,
        onDarkVideo: false,
      ),
      isNot(
        SubtitleChunkHighlighter.fill(
          SubtitleChunkKind.usage,
          onDarkVideo: false,
        ),
      ),
    );
  });
}
