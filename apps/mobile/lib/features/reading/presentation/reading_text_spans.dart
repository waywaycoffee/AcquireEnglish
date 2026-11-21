import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../player/presentation/widgets/subtitle_chunk_highlight.dart';
import '../../words/presentation/word_book_provider.dart' show normalizeWord;

typedef ReadingWordTap = void Function(String word, int start, int end);

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

/// Build rich-text spans with chunk highlight + optional hard-word Chinese.
List<InlineSpan> buildReadingTextSpans({
  required String text,
  required Color textColor,
  required double fontSize,
  required double lineHeight,
  required bool dark,
  required bool showChinese,
  required Set<String> learnedWords,
  required Map<String, String> hardGlosses,
  required SubtitleChunkHighlighter? chunkHighlighter,
  required ReadingWordTap onWordTap,
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
  final Map<int, SubtitleChunkSpan> chunkHits =
      chunkHighlighter?.matchLine(wordLine) ?? const <int, SubtitleChunkSpan>{};

  // word-token-index → absolute token index covered by a chunk (from start).
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
        TextSpan(
          text: buf.toString(),
          style: TextStyle(
            color: fg,
            fontSize: fontSize,
            height: lineHeight,
            fontWeight: FontWeight.w600,
            backgroundColor: fill,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => onWordTap(
              chunk.phrase,
              tokens[firstAbs].start,
              tokens[lastAbs].end,
            ),
        ),
      );
      continue;
    }

    final String norm = normalizeWord(token.raw);
    final String? gloss = showChinese ? hardGlosses[norm] : null;
    final bool learned = learnedWords.contains(norm);
    final Color wordColor = learned
        ? (dark ? const Color(0xFF9AE6B4) : const Color(0xFF146638))
        : textColor;

    if (gloss != null && gloss.isNotEmpty) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () => onWordTap(token.raw, token.start, token.end),
            child: Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    token.raw,
                    style: TextStyle(
                      color: wordColor,
                      fontSize: fontSize,
                      height: 1.15,
                      fontWeight: FontWeight.w500,
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
              ),
            ),
          ),
        ),
      );
    } else {
      spans.add(
        TextSpan(
          text: token.raw,
          style: TextStyle(
            color: wordColor,
            fontSize: fontSize,
            height: lineHeight,
            fontWeight: FontWeight.w500,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => onWordTap(token.raw, token.start, token.end),
        ),
      );
    }
  }
  return spans;
}
