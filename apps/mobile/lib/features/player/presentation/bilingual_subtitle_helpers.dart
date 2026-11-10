import 'player_mock_state.dart';
import 'subtitle_word_alignment.dart';

enum MissingSubtitleSide { none, english, chinese, both }

enum BilingualPipelinePhase {
  idle,
  ocrRunning,
  ocrSlow,
  translating,
  asrProofreading,
  completed,
  cancelled,
}

class OcrCueText {
  const OcrCueText({this.english = '', this.chinese = ''});

  final String english;
  final String chinese;

  bool get isEmpty => english.trim().isEmpty && chinese.trim().isEmpty;

  OcrCueText merge(OcrCueText other) {
    return OcrCueText(
      english: english.trim().isNotEmpty ? english : other.english,
      chinese: chinese.trim().isNotEmpty ? chinese : other.chinese,
    );
  }
}

final RegExp _latinWord = RegExp(r"[A-Za-z]{2,}");
final RegExp _chineseChar = RegExp(r'[\u4e00-\u9fff]');

bool looksEnglish(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) {
    return false;
  }
  final int latin = _latinWord.allMatches(text).length;
  final int chinese = _chineseChar.allMatches(text).length;
  return latin > 0 && latin >= chinese;
}

bool looksChinese(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) {
    return false;
  }
  return _chineseChar.hasMatch(text);
}

/// Split OCR block lines into EN / ZH buckets.
OcrCueText splitOcrTextBlocks(List<String> blocks) {
  final StringBuffer english = StringBuffer();
  final StringBuffer chinese = StringBuffer();
  void appendEnglish(String value) {
    if (value.isEmpty) {
      return;
    }
    if (english.isNotEmpty) {
      english.write(' ');
    }
    english.write(value);
  }

  void appendChinese(String value) {
    if (value.isEmpty) {
      return;
    }
    if (chinese.isNotEmpty) {
      chinese.write(' ');
    }
    chinese.write(value);
  }

  for (final String raw in blocks) {
    final String line = raw.trim();
    if (line.isEmpty) {
      continue;
    }
    final bool hasLatin = _latinWord.hasMatch(line);
    final bool hasChinese = _chineseChar.hasMatch(line);
    if (hasLatin && hasChinese) {
      // Mixed line: keep Latin as EN, CJK as ZH when possible.
      final String enPart = line
          .replaceAll(_chineseChar, ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final String zhPart = line
          .replaceAll(_latinWord, ' ')
          .replaceAll(RegExp(r"[A-Za-z0-9’'\-]+"), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      appendEnglish(enPart);
      appendChinese(zhPart);
    } else if (hasLatin) {
      appendEnglish(line);
    } else if (hasChinese) {
      appendChinese(line);
    }
  }
  return OcrCueText(english: english.toString(), chinese: chinese.toString());
}

MissingSubtitleSide detectMissingSubtitleSide(List<PlayerSubtitleLine> lines) {
  if (lines.isEmpty) {
    return MissingSubtitleSide.both;
  }
  final bool hasUsableEnglish = usableReferenceSubtitles(lines).isNotEmpty;
  int chineseHits = 0;
  for (final PlayerSubtitleLine line in lines) {
    if (looksChinese(line.chinese)) {
      chineseHits += 1;
      continue;
    }
    // Chinese-only normalized lines put CJK into english.
    if (!looksEnglish(line.english) && looksChinese(line.english)) {
      chineseHits += 1;
    }
  }
  final bool hasChinese = chineseHits > 0;
  if (hasUsableEnglish && hasChinese) {
    // Still treat as missing Chinese when every chinese field is empty/duplicate
    // of a true English line.
    final bool chineseIsUseful = lines.any((PlayerSubtitleLine line) {
      final String zh = line.chinese.trim();
      final String en = line.english.trim();
      return zh.isNotEmpty && zh != en && looksChinese(zh);
    });
    if (chineseIsUseful) {
      return MissingSubtitleSide.none;
    }
    return MissingSubtitleSide.chinese;
  }
  if (hasUsableEnglish) {
    return MissingSubtitleSide.chinese;
  }
  if (hasChinese) {
    return MissingSubtitleSide.english;
  }
  return MissingSubtitleSide.both;
}

bool needsBilingualFill(List<PlayerSubtitleLine> lines) {
  return detectMissingSubtitleSide(lines) != MissingSubtitleSide.none;
}

/// Count how many lines gained the previously-missing side after a merge.
int countFilledMissingSide({
  required List<PlayerSubtitleLine> before,
  required List<PlayerSubtitleLine> after,
  required MissingSubtitleSide missing,
}) {
  if (missing == MissingSubtitleSide.none || after.isEmpty) {
    return 0;
  }
  int filled = 0;
  final int n = after.length < before.length ? after.length : before.length;
  for (int i = 0; i < n; i++) {
    final PlayerSubtitleLine a = before[i];
    final PlayerSubtitleLine b = after[i];
    switch (missing) {
      case MissingSubtitleSide.english:
        if (!looksEnglish(a.english) && looksEnglish(b.english)) {
          filled += 1;
        }
      case MissingSubtitleSide.chinese:
        if (!looksChinese(a.chinese) && looksChinese(b.chinese)) {
          filled += 1;
        }
      case MissingSubtitleSide.both:
        if ((!looksEnglish(a.english) && looksEnglish(b.english)) ||
            (!looksChinese(a.chinese) && looksChinese(b.chinese))) {
          filled += 1;
        }
      case MissingSubtitleSide.none:
        break;
    }
  }
  // New OCR-only cues appended after seed lines.
  for (int i = n; i < after.length; i++) {
    final PlayerSubtitleLine line = after[i];
    if (looksEnglish(line.english) || looksChinese(line.chinese)) {
      filled += 1;
    }
  }
  return filled;
}

List<PlayerSubtitleLine> mergeOcrCueIntoLines({
  required List<PlayerSubtitleLine> lines,
  required int positionMs,
  required OcrCueText cue,
  int toleranceMs = 1800,
}) {
  if (cue.isEmpty) {
    return List<PlayerSubtitleLine>.of(lines);
  }
  final List<PlayerSubtitleLine> next = List<PlayerSubtitleLine>.of(lines);
  int bestIndex = -1;
  int bestDistance = 1 << 30;
  for (int i = 0; i < next.length; i++) {
    final PlayerSubtitleLine line = next[i];
    if (positionMs >= line.startMs - toleranceMs &&
        positionMs <= line.endMs + toleranceMs) {
      final int mid = (line.startMs + line.endMs) ~/ 2;
      final int distance = (mid - positionMs).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
  }

  if (bestIndex >= 0) {
    final PlayerSubtitleLine current = next[bestIndex];
    final bool currentEnglishIsChineseOnly =
        !looksEnglish(current.english) && looksChinese(current.english);
    final String english = cue.english.trim().isNotEmpty &&
            (current.english.trim().isEmpty ||
                currentEnglishIsChineseOnly ||
                !looksEnglish(current.english))
        ? cue.english.trim()
        : current.english;
    final String chinese = cue.chinese.trim().isNotEmpty &&
            (current.chinese.trim().isEmpty ||
                current.chinese.trim() == current.english.trim())
        ? cue.chinese.trim()
        : (current.chinese.trim().isNotEmpty
              ? current.chinese
              : (currentEnglishIsChineseOnly ? current.english : current.chinese));
    next[bestIndex] = PlayerSubtitleLine(
      startTime: current.startTime,
      english: english,
      chinese: chinese,
      startMs: current.startMs,
      endMs: current.endMs,
      words: current.words,
    );
    return next;
  }

  final int startMs = positionMs < 400 ? 0 : positionMs - 400;
  final int endMs = positionMs + 1600;
  next.add(
    PlayerSubtitleLine(
      startTime: _formatClock(startMs),
      english: cue.english,
      chinese: cue.chinese,
      startMs: startMs,
      endMs: endMs,
    ),
  );
  next.sort(
    (PlayerSubtitleLine a, PlayerSubtitleLine b) => a.startMs.compareTo(b.startMs),
  );
  return next;
}

List<PlayerSubtitleLine> fillMissingSideByTranslation({
  required List<PlayerSubtitleLine> lines,
  required MissingSubtitleSide missing,
  required List<String> translations,
}) {
  if (missing == MissingSubtitleSide.none || translations.isEmpty) {
    return lines;
  }
  final List<PlayerSubtitleLine> next = <PlayerSubtitleLine>[];
  int cursor = 0;
  for (final PlayerSubtitleLine line in lines) {
    final String translated =
        cursor < translations.length ? translations[cursor].trim() : '';
    cursor += 1;
    if (translated.isEmpty) {
      next.add(line);
      continue;
    }
    switch (missing) {
      case MissingSubtitleSide.english:
        next.add(
          PlayerSubtitleLine(
            startTime: line.startTime,
            english: looksEnglish(line.english) ? line.english : translated,
            chinese: looksChinese(line.chinese)
                ? line.chinese
                : (looksChinese(line.english) ? line.english : line.chinese),
            startMs: line.startMs,
            endMs: line.endMs,
            words: line.words,
          ),
        );
      case MissingSubtitleSide.chinese:
        next.add(
          PlayerSubtitleLine(
            startTime: line.startTime,
            english: line.english,
            chinese: looksChinese(line.chinese) ? line.chinese : translated,
            startMs: line.startMs,
            endMs: line.endMs,
            words: line.words,
          ),
        );
      case MissingSubtitleSide.both:
        next.add(
          PlayerSubtitleLine(
            startTime: line.startTime,
            english: looksEnglish(line.english) ? line.english : translated,
            chinese: looksChinese(line.chinese) ? line.chinese : translated,
            startMs: line.startMs,
            endMs: line.endMs,
            words: line.words,
          ),
        );
      case MissingSubtitleSide.none:
        next.add(line);
    }
  }
  return next;
}

List<String> sourceTextsForTranslation({
  required List<PlayerSubtitleLine> lines,
  required MissingSubtitleSide missing,
}) {
  return lines.map((PlayerSubtitleLine line) {
    switch (missing) {
      case MissingSubtitleSide.english:
        return looksChinese(line.chinese)
            ? line.chinese
            : (looksChinese(line.english) ? line.english : line.chinese);
      case MissingSubtitleSide.chinese:
        return line.english;
      case MissingSubtitleSide.both:
        return line.english.isNotEmpty ? line.english : line.chinese;
      case MissingSubtitleSide.none:
        return '';
    }
  }).toList(growable: false);
}

String _formatClock(int milliseconds) {
  final int totalSeconds = milliseconds ~/ 1000;
  final int minutes = totalSeconds ~/ 60;
  final int seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
