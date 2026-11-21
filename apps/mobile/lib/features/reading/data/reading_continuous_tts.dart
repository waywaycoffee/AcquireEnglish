import '../presentation/reading_text_spans.dart';

/// One spoken unit for continuous reading (usually a sentence).
class ReadingSpeakUnit {
  const ReadingSpeakUnit({
    required this.text,
    required this.startChar,
    required this.endChar,
    required this.firstWordIndex,
    required this.wordCount,
  });

  final String text;
  final int startChar;
  final int endChar;

  /// Absolute word index of the first word in the document.
  final int firstWordIndex;
  final int wordCount;
}

/// Split [text] into sentence units with absolute word indices.
List<ReadingSpeakUnit> splitReadingSpeakUnits(String text) {
  final List<ReadingToken> tokens = tokenizeReadingText(text);
  final List<int> wordAbs = <int>[
    for (int i = 0; i < tokens.length; i++)
      if (tokens[i].isWord) i,
  ];
  if (wordAbs.isEmpty) return const <ReadingSpeakUnit>[];

  final List<ReadingSpeakUnit> units = <ReadingSpeakUnit>[];
  int cursor = 0;
  while (cursor < text.length) {
    while (cursor < text.length && text[cursor].trim().isEmpty) {
      cursor += 1;
    }
    if (cursor >= text.length) break;
    final ({int start, int end, String text}) bounds =
        sentenceBounds(text, cursor, cursor + 1);
    final String sentence = bounds.text;
    if (sentence.isEmpty) {
      cursor = bounds.end;
      continue;
    }
    int firstWord = -1;
    int count = 0;
    for (int wi = 0; wi < wordAbs.length; wi++) {
      final ReadingToken t = tokens[wordAbs[wi]];
      if (t.end <= bounds.start) continue;
      if (t.start >= bounds.end) break;
      if (firstWord < 0) firstWord = wi;
      count += 1;
    }
    if (firstWord >= 0 && count > 0) {
      units.add(
        ReadingSpeakUnit(
          text: sentence,
          startChar: bounds.start,
          endChar: bounds.end,
          firstWordIndex: firstWord,
          wordCount: count,
        ),
      );
    }
    cursor = bounds.end;
    if (cursor <= bounds.start) cursor = bounds.start + 1;
  }
  return units;
}

/// Estimated ms per word at the given TTS rate (baseline ~420ms @ 0.75).
int estimatedMsPerWord(double rate) {
  final double r = rate.clamp(0.5, 1.8);
  return (420 * (0.75 / r)).round().clamp(180, 900);
}
