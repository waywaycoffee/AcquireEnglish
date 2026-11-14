import 'dart:convert';

import 'package:flutter/services.dart';

import 'bilingual_subtitle_helpers.dart';
import 'player_media_source.dart';
import 'player_mock_state.dart';
import 'subtitle_language_sanitize.dart';

export 'subtitle_language_sanitize.dart' show sanitizeSubtitleLanguageFields;

Future<List<PlayerSubtitleLine>> loadSubtitleLinesFromAsset(
  String assetPath,
) async {
  final String raw = await rootBundle.loadString(assetPath);
  return parseSubtitleLines(raw);
}

Future<List<PlayerSubtitleLine>> loadSubtitleLines(String source) async {
  final String raw = await loadPlayerTextSource(source);
  return parseSubtitleLines(raw);
}

/// Official Chinese-only CC/AI tracks parse into [PlayerSubtitleLine.english]
/// by default. Keep the cue in [PlayerSubtitleLine.chinese] only — do **not**
/// copy Chinese into [english], or 双语 mode looks "all Chinese" and word
/// highlighting treats CJK as English tokens.
List<PlayerSubtitleLine> normalizeChineseOnlySubtitleLines(
  List<PlayerSubtitleLine> lines,
) {
  return sanitizeSubtitleLanguageFields(
    lines
        .map((PlayerSubtitleLine line) {
          final String text = line.chinese.trim().isNotEmpty
              ? line.chinese.trim()
              : line.english.trim();
          if (text.isEmpty) {
            return line;
          }
          return PlayerSubtitleLine(
            startTime: line.startTime,
            english: '',
            chinese: text,
            startMs: line.startMs,
            endMs: line.endMs,
            words: const [],
          );
        })
        .toList(growable: false),
  );
}

/// Overlay sparse persisted English cues onto a full Chinese timeline.
///
/// Partial `en.srt` omits cues without English; reloading must keep every
/// Chinese cue so the next fill only translates holes.
List<PlayerSubtitleLine> mergePartialEnglishOntoChineseBase({
  required List<PlayerSubtitleLine> chineseLines,
  required List<PlayerSubtitleLine> englishLines,
  int minOverlapMs = 120,
  bool allowIndexFallback = true,
}) {
  if (chineseLines.isEmpty) {
    return sanitizeSubtitleLanguageFields(englishLines);
  }
  final List<PlayerSubtitleLine> base =
      normalizeChineseOnlySubtitleLines(chineseLines);
  if (englishLines.isEmpty) {
    return base;
  }
  final List<PlayerSubtitleLine> enSanitized =
      sanitizeSubtitleLanguageFields(englishLines);
  return sanitizeSubtitleLanguageFields(
    List<PlayerSubtitleLine>.generate(base.length, (int index) {
      final PlayerSubtitleLine zh = base[index];
      String bestEnglish = '';
      int bestOverlap = 0;
      for (final PlayerSubtitleLine en in enSanitized) {
        if (!subtitleLooksEnglish(en.english)) {
          continue;
        }
        final int start = zh.startMs > en.startMs ? zh.startMs : en.startMs;
        final int end = zh.endMs < en.endMs ? zh.endMs : en.endMs;
        final int overlap = end - start;
        if (overlap > bestOverlap) {
          bestOverlap = overlap;
          bestEnglish = en.english.trim();
        }
      }
      if (allowIndexFallback &&
          bestOverlap < minOverlapMs &&
          index < enSanitized.length) {
        final PlayerSubtitleLine sameIndex = enSanitized[index];
        if (subtitleLooksEnglish(sameIndex.english)) {
          bestEnglish = sameIndex.english.trim();
          bestOverlap = minOverlapMs;
        }
      }
      if (bestOverlap < minOverlapMs || bestEnglish.isEmpty) {
        return zh;
      }
      return PlayerSubtitleLine(
        startTime: zh.startTime,
        english: bestEnglish,
        chinese: zh.chinese,
        startMs: zh.startMs,
        endMs: zh.endMs,
        words: zh.words,
      );
    }),
  );
}

/// Official Chinese cues stay the timeline. English is restored only when it
/// was saved as the translation of that same Chinese cue. A fluent sentence
/// that merely shares the timestamp (ASR/OCR) is left blank so it can be
/// translated from the Chinese text.
List<PlayerSubtitleLine> subtitleBaseFromOfficialChinese({
  required List<PlayerSubtitleLine> officialChinese,
  List<PlayerSubtitleLine> cachedLines = const <PlayerSubtitleLine>[],
  bool cachedEnglishIsTranslation = false,
}) {
  final List<PlayerSubtitleLine> base = normalizeChineseOnlySubtitleLines(
    officialChinese,
  );
  if (!cachedEnglishIsTranslation || base.isEmpty || cachedLines.isEmpty) {
    return base;
  }
  return <PlayerSubtitleLine>[
    for (final PlayerSubtitleLine line in base)
      _restoreTranslationForCue(line, cachedLines),
  ];
}

PlayerSubtitleLine _restoreTranslationForCue(
  PlayerSubtitleLine cue,
  List<PlayerSubtitleLine> cachedLines,
) {
  final String chinese = cue.chinese.trim();
  if (chinese.isEmpty) {
    return cue;
  }
  for (final PlayerSubtitleLine cached in cachedLines) {
    if (cached.startMs != cue.startMs || cached.chinese.trim() != chinese) {
      continue;
    }
    final String english = cached.english.trim();
    if (!looksEnglish(english) || looksChinese(english)) {
      continue;
    }
    return PlayerSubtitleLine(
      startTime: cue.startTime,
      english: english,
      chinese: chinese,
      startMs: cue.startMs,
      endMs: cue.endMs,
      words: cue.words,
    );
  }
  return cue;
}

List<PlayerSubtitleLine> mergeSubtitleLines({
  required List<PlayerSubtitleLine> englishLines,
  required List<PlayerSubtitleLine> chineseLines,
}) {
  final List<PlayerSubtitleLine> enSanitized =
      sanitizeSubtitleLanguageFields(englishLines);
  final List<PlayerSubtitleLine> zhSanitized =
      sanitizeSubtitleLanguageFields(chineseLines);

  final bool hasRealEnglish = enSanitized.any(
    (PlayerSubtitleLine line) => subtitleLooksEnglish(line.english),
  );

  // Official "en" tracks are sometimes Chinese AI content mislabeled as EN.
  if (!hasRealEnglish) {
    if (zhSanitized.isNotEmpty) {
      return normalizeChineseOnlySubtitleLines(zhSanitized);
    }
    if (enSanitized.isNotEmpty) {
      return normalizeChineseOnlySubtitleLines(enSanitized);
    }
    return const <PlayerSubtitleLine>[];
  }

  return sanitizeSubtitleLanguageFields(
    List<PlayerSubtitleLine>.generate(enSanitized.length, (int index) {
      final PlayerSubtitleLine englishLine = enSanitized[index];
      final String chinese = _chineseForEnglishCue(
        englishLine,
        zhSanitized,
        index,
      );

      return PlayerSubtitleLine(
        startTime: englishLine.startTime,
        english: englishLine.english,
        chinese: chinese,
        startMs: englishLine.startMs,
        endMs: englishLine.endMs,
        words: englishLine.words,
      );
    }),
  );
}

String _chineseForEnglishCue(
  PlayerSubtitleLine englishLine,
  List<PlayerSubtitleLine> chineseLines,
  int index,
) {
  if (chineseLines.isEmpty) {
    return englishLine.chinese;
  }

  int bestIndex = -1;
  int bestOverlap = 0;
  for (int i = 0; i < chineseLines.length; i++) {
    final PlayerSubtitleLine zh = chineseLines[i];
    final int start = englishLine.startMs > zh.startMs
        ? englishLine.startMs
        : zh.startMs;
    final int end = englishLine.endMs < zh.endMs
        ? englishLine.endMs
        : zh.endMs;
    final int overlap = end - start;
    if (overlap > bestOverlap) {
      bestOverlap = overlap;
      bestIndex = i;
    }
  }

  // Prefer time overlap; fall back to same index when tracks are aligned.
  final PlayerSubtitleLine? matched = bestOverlap > 0
      ? chineseLines[bestIndex]
      : (index < chineseLines.length ? chineseLines[index] : null);
  if (matched == null) {
    return englishLine.chinese;
  }
  if (matched.chinese.trim().isNotEmpty) {
    return matched.chinese.trim();
  }
  if (subtitleLooksChineseOnly(matched.english)) {
    return matched.english.trim();
  }
  return englishLine.chinese;
}

List<PlayerSubtitleLine> parseSubtitleLines(String rawSubtitle) {
  final String trimmed = rawSubtitle.trimLeft();
  if (trimmed.startsWith('{')) {
    return sanitizeSubtitleLanguageFields(
      _parseGeneratedWordsJson(rawSubtitle),
    );
  }

  // ponytail: parser supports SRT/VTT lines with basic bilingual cue split, no extra dependency.
  final List<String> lines = rawSubtitle
      .replaceAll('\r\n', '\n')
      .replaceAll('\uFEFF', '')
      .split('\n');
  final List<PlayerSubtitleLine> result = <PlayerSubtitleLine>[];

  final RegExp timingLine = RegExp(
    r'(?:(\d+:)?\d{2}:\d{2}[.,]\d{1,3})\s*-->\s*'
    r'(?:(\d+:)?\d{2}:\d{2}[.,]\d{1,3})',
  );

  for (int index = 0; index < lines.length; index++) {
    final String rawLine = lines[index].trim();
    if (rawLine.startsWith('WEBVTT')) {
      continue;
    }
    final Match? match = timingLine.firstMatch(rawLine);
    if (match == null) {
      continue;
    }

    final List<String> parts = rawLine.split('-->');
    if (parts.length != 2) {
      continue;
    }

    final int? startMs = _parseTimestampToMs(parts[0].trim());
    final int? endMs = _parseTimestampToMs(parts[1].trim());
    if (startMs == null || endMs == null || endMs <= startMs) {
      continue;
    }

    final List<String> textLines = <String>[];
    index += 1;
    while (index < lines.length) {
      final String textLine = lines[index].trim();
      if (textLine.isEmpty) {
        break;
      }
      textLines.add(textLine);
      index += 1;
    }
    final List<String> cleanedLines = textLines
        .map(
          (String textLine) => textLine
              .replaceAll(RegExp('<[^>]+>'), '')
              .trim()
              .replaceAll(RegExp(r'\{[^}]*\}'), ''),
        )
        .where((String textLine) => textLine.isNotEmpty)
        .toList(growable: false);
    if (cleanedLines.isEmpty) {
      continue;
    }

    final _DualLanguageLinePair pair = _splitDualLanguageLine(cleanedLines);
    result.add(
      PlayerSubtitleLine(
        startTime: _formatTimestamp(startMs),
        english: pair.english,
        chinese: pair.chinese,
        startMs: startMs,
        endMs: endMs,
      ),
    );
  }

  return sanitizeSubtitleLanguageFields(result);
}

List<PlayerSubtitleLine> _parseGeneratedWordsJson(String rawSubtitle) {
  final Object? decoded = jsonDecode(rawSubtitle);
  if (decoded is! Map<String, dynamic>) {
    return const <PlayerSubtitleLine>[];
  }
  final Object? rawLines = decoded['lines'];
  if (rawLines is! List<dynamic>) {
    return const <PlayerSubtitleLine>[];
  }

  return rawLines
      .whereType<Map<String, dynamic>>()
      .map(_parseGeneratedWordsLine)
      .whereType<PlayerSubtitleLine>()
      .toList(growable: false);
}

Map<String, String> parseSubtitleGlossary(String rawSubtitle) {
  final Object? decoded = jsonDecode(rawSubtitle);
  if (decoded is! Map<String, dynamic>) return const <String, String>{};
  final Map<String, String> glossary = <String, String>{};
  for (final Object? item
      in decoded['glossary'] as List<dynamic>? ?? const <dynamic>[]) {
    if (item is! Map<String, dynamic>) continue;
    final String word = (item['word'] as String? ?? '').trim().toLowerCase();
    final String definition = (item['definitionCn'] as String? ?? '').trim();
    if (RegExp(r'^[a-z]{2,}$').hasMatch(word) && definition.isNotEmpty) {
      glossary.putIfAbsent(word, () => definition);
    }
  }
  return glossary;
}

PlayerSubtitleLine? _parseGeneratedWordsLine(Map<String, dynamic> json) {
  final int? startMs = _intOrNull(json['startMs']);
  final int? endMs = _intOrNull(json['endMs']);
  if (startMs == null || endMs == null || endMs <= startMs) {
    return null;
  }

  final List<PlayerSubtitleWord> words =
      (json['words'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> wordJson) {
            final String text = (wordJson['text'] as String? ?? '').trim();
            final int? wordStartMs = _intOrNull(wordJson['startMs']);
            final int? wordEndMs = _intOrNull(wordJson['endMs']);
            if (text.isEmpty ||
                wordStartMs == null ||
                wordEndMs == null ||
                wordEndMs <= wordStartMs ||
                wordStartMs < startMs ||
                wordEndMs > endMs) {
              return null;
            }
            return PlayerSubtitleWord(
              text: text,
              startMs: wordStartMs,
              endMs: wordEndMs,
              confidence: _doubleOrNull(wordJson['confidence']),
            );
          })
          .whereType<PlayerSubtitleWord>()
          .toList(growable: false);

  return PlayerSubtitleLine(
    startTime: _formatTimestamp(startMs),
    english: (json['english'] as String? ?? '').trim(),
    chinese: (json['chinese'] as String? ?? '').trim(),
    startMs: startMs,
    endMs: endMs,
    words: words,
  );
}

int? _intOrNull(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return null;
}

double? _doubleOrNull(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return null;
}

int? _parseTimestampToMs(String? value) {
  if (value == null) {
    return null;
  }
  final RegExp match = RegExp(
    r'^(?:(\d+):)?(\d{1,2}):(\d{2})(?:[.,](\d{1,3}))?$',
  );
  final Match? matchResult = match.firstMatch(value.trim());
  if (matchResult == null) {
    return null;
  }

  final int hours = int.tryParse(matchResult.group(1) ?? '0') ?? 0;
  final int minutes = int.tryParse(matchResult.group(2) ?? '0') ?? 0;
  final int seconds = int.tryParse(matchResult.group(3) ?? '0') ?? 0;
  final String normalizedMilliseconds = matchResult.group(4) ?? '0';
  final int milliseconds = int.parse(
    normalizedMilliseconds.padRight(3, '0').substring(0, 3),
  );
  return (((hours * 60 + minutes) * 60) + seconds) * 1000 + milliseconds;
}

String _formatTimestamp(int milliseconds) {
  final int totalSeconds = milliseconds ~/ 1000;
  final int totalMinutes = totalSeconds ~/ 60;
  final int seconds = totalSeconds % 60;
  return '${totalMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

_DualLanguageLinePair _splitDualLanguageLine(List<String> lines) {
  if (lines.isEmpty) {
    return const _DualLanguageLinePair(english: '', chinese: '');
  }
  if (lines.length == 1) {
    final String only = lines.first;
    if (_containsChinese(only) && !_looksLikeEnglishLine(only)) {
      return _DualLanguageLinePair(english: '', chinese: only);
    }
    return _DualLanguageLinePair(english: only, chinese: '');
  }

  final String firstLine = lines.first;
  final String secondLine = lines[1];
  if (!_containsChinese(secondLine) && !_containsChinese(firstLine)) {
    return _DualLanguageLinePair(english: lines.join(' '), chinese: '');
  }
  if (_containsChinese(secondLine) &&
      !_containsChinese(firstLine) &&
      lines.length == 2) {
    return _DualLanguageLinePair(english: firstLine, chinese: secondLine);
  }
  // ZH-only multi-line cue (or EN mislabeled as first line of CJK).
  if (_containsChinese(firstLine) && !_looksLikeEnglishLine(firstLine)) {
    return _DualLanguageLinePair(
      english: '',
      chinese: lines.join(' '),
    );
  }

  return _DualLanguageLinePair(
    english: firstLine,
    chinese: lines.sublist(1).join(' '),
  );
}

bool _containsChinese(String value) {
  return RegExp(r'[\u4e00-\u9fff]').hasMatch(value);
}

bool _looksLikeEnglishLine(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) {
    return false;
  }
  final int latin = RegExp(r'[A-Za-z]').allMatches(text).length;
  final int chinese = RegExp(r'[\u4e00-\u9fff]').allMatches(text).length;
  return latin > 0 && latin >= chinese;
}

class _DualLanguageLinePair {
  const _DualLanguageLinePair({required this.english, required this.chinese});

  final String english;
  final String chinese;
}
