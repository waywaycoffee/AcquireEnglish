import 'package:flutter/material.dart';

import '../../player/presentation/widgets/subtitle_chunk_highlight.dart';
import '../../words/presentation/word_book_provider.dart' show normalizeWord;

/// Reader colors follow the reading surface, independently of the app theme.
Color readingForegroundColor(bool dark) =>
    dark ? const Color(0xFFF2F2F7) : const Color(0xFF242428);

Color readingBackgroundColor(bool dark) =>
    dark ? const Color(0xFF1C1C1E) : const Color(0xFFF7F3E9);

typedef ReadingRangeCallback = void Function(String lexeme, int start, int end);

class ReadingToken {
  const ReadingToken({
    required this.raw,
    required this.start,
    required this.end,
    required this.isWord,
  });

  final String raw;
  final int start;
  final int end;
  final bool isWord;
}

List<ReadingToken> tokenizeReadingText(String text) {
  final List<ReadingToken> out = <ReadingToken>[];
  final RegExp re = RegExp(r"[A-Za-z]+(?:['’-][A-Za-z]+)*|[^A-Za-z]+");
  for (final RegExpMatch m in re.allMatches(text)) {
    final String raw = m.group(0)!;
    out.add(
      ReadingToken(
        raw: raw,
        start: m.start,
        end: m.end,
        isWord: RegExp(r'^[A-Za-z]').hasMatch(raw),
      ),
    );
  }
  return out;
}

/// Sentence span covering [start, end) character offsets in [text].
({int start, int end, String text}) sentenceBounds(String text, int start, int end) {
  int left = start.clamp(0, text.length);
  int right = end.clamp(0, text.length);
  while (left > 0 && !'.!?。！？'.contains(text[left - 1])) {
    left--;
  }
  while (right < text.length && !'.!?。！？'.contains(text[right])) {
    right++;
  }
  if (right < text.length) right++;
  final String sentence = text.substring(left, right).trim();
  return (start: left, end: right, text: sentence);
}

/// Build rich-text spans with chunk highlight + optional hard-word Chinese.
List<InlineSpan> buildReadingTextSpans({
  required String text,
  required Color textColor,
  required double fontSize,
  required double lineHeight,
  required bool dark,
  required bool showChinese,
  required bool showChunks,
  required Set<String> learnedWords,
  required Map<String, String> hardGlosses,
  required SubtitleChunkHighlighter? chunkHighlighter,
  required ReadingRangeCallback onWordTap,
  required ReadingRangeCallback onWordLongPress,
  required ReadingRangeCallback onChunkDoubleTap,
  required ReadingRangeCallback onChunkLongPress,
  int? highlightWordIndex,
}) {
  final List<ReadingToken> tokens = tokenizeReadingText(text);
  if (tokens.isEmpty) return const <InlineSpan>[];

  final List<int> wordTokenIndexes = <int>[
    for (int i = 0; i < tokens.length; i++)
      if (tokens[i].isWord) i,
  ];
  final String wordLine = <String>[
    for (final int idx in wordTokenIndexes) tokens[idx].raw,
  ].join(' ');
  final Map<int, SubtitleChunkSpan> chunkHits = showChunks
      ? (chunkHighlighter?.matchLine(wordLine) ??
            const <int, SubtitleChunkSpan>{})
      : const <int, SubtitleChunkSpan>{};

  final Set<int> consumed = <int>{};
  final List<InlineSpan> spans = <InlineSpan>[];

  for (int i = 0; i < tokens.length; i++) {
    if (consumed.contains(i)) continue;
    final ReadingToken token = tokens[i];
    if (!token.isWord) {
      spans.add(
        TextSpan(
          text: token.raw,
          style: TextStyle(
            color: textColor,
            fontSize: fontSize,
            height: lineHeight,
          ),
        ),
      );
      continue;
    }

    final int wordIdx = wordTokenIndexes.indexOf(i);
    final SubtitleChunkSpan? chunk = chunkHits[wordIdx];
    if (chunk != null && wordIdx == chunk.start) {
      final int firstAbs = wordTokenIndexes[chunk.start];
      final int lastAbs = wordTokenIndexes[chunk.endExclusive - 1];
      final StringBuffer buf = StringBuffer();
      for (int j = firstAbs; j <= lastAbs; j++) {
        buf.write(tokens[j].raw);
        consumed.add(j);
      }
      final Color fill = SubtitleChunkHighlighter.fill(
        chunk.kind,
        onDarkVideo: dark,
      );
      final Color fg = SubtitleChunkHighlighter.textColor(
        chunk.kind,
        fallback: textColor,
        onDarkVideo: dark,
      );
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: () => onChunkDoubleTap(
              chunk.phrase,
              tokens[firstAbs].start,
              tokens[lastAbs].end,
            ),
            onLongPress: () => onChunkLongPress(
              chunk.phrase,
              tokens[firstAbs].start,
              tokens[lastAbs].end,
            ),
            onTap: () => onWordTap(
              chunk.phrase,
              tokens[firstAbs].start,
              tokens[lastAbs].end,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              color: fill,
              child: Text(
                buf.toString(),
                style: TextStyle(
                  color: fg,
                  fontSize: fontSize,
                  height: lineHeight,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
      continue;
    }

    final String norm = normalizeWord(token.raw);
    final String? gloss = showChinese ? hardGlosses[norm] : null;
    final bool learned = learnedWords.contains(norm);
    final bool karaoke = highlightWordIndex != null && wordIdx == highlightWordIndex;
    final Color wordColor = karaoke
        ? (dark ? const Color(0xFFE8FFC8) : const Color(0xFF146638))
        : learned
            ? (dark ? const Color(0xFF9AE6B4) : const Color(0xFF146638))
            : textColor;
    final Color? karaokeBg = karaoke
        ? (dark ? const Color(0xFF3A5A20) : const Color(0xFFDFF8C8))
        : null;

    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => onWordTap(token.raw, token.start, token.end),
          onLongPress: () =>
              onWordLongPress(token.raw, token.start, token.end),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            decoration: karaokeBg == null
                ? null
                : BoxDecoration(
                    color: karaokeBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: dark
                          ? const Color(0xFF9AE6B4)
                          : const Color(0xFF2F6B3A),
                    ),
                  ),
            child: gloss != null && gloss.isNotEmpty
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        token.raw,
                        style: TextStyle(
                          color: wordColor,
                          fontSize: fontSize,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        gloss,
                        style: TextStyle(
                          color: dark
                              ? const Color(0xFFB0B0B8)
                              : const Color(0xFF6B6B76),
                          fontSize: fontSize * 0.52,
                          height: 1.05,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                : Text(
                    token.raw,
                    style: TextStyle(
                      color: wordColor,
                      fontSize: fontSize,
                      height: lineHeight,
                      fontWeight: karaoke ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
  return spans;
}
