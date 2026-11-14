import 'player_mock_state.dart';

final RegExp _chineseChar = RegExp(r'[\u4e00-\u9fff]');
final RegExp _latinChar = RegExp(r'[A-Za-z]');

bool subtitleLooksChineseOnly(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) {
    return false;
  }
  if (!_chineseChar.hasMatch(text)) {
    return false;
  }
  final int latin = _latinChar.allMatches(text).length;
  final int chinese = _chineseChar.allMatches(text).length;
  return chinese > 0 && chinese >= latin;
}

bool subtitleLooksEnglish(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) {
    return false;
  }
  final int latin = _latinChar.allMatches(text).length;
  final int chinese = _chineseChar.allMatches(text).length;
  return latin > 0 && latin > chinese;
}

/// Move CJK-only text out of [PlayerSubtitleLine.english].
///
/// Also collapses identical en/zh pairs so 双语 mode cannot render the same
/// Chinese sentence twice (primary + secondary).
List<PlayerSubtitleLine> sanitizeSubtitleLanguageFields(
  List<PlayerSubtitleLine> lines,
) {
  return lines.map(_sanitizeOne).toList(growable: false);
}

PlayerSubtitleLine _sanitizeOne(PlayerSubtitleLine line) {
  final String en = line.english.trim();
  final String zh = line.chinese.trim();

  if (en.isEmpty && zh.isEmpty) {
    return line;
  }

  // Same text on both sides: keep one side only.
  if (en.isNotEmpty && en == zh) {
    if (subtitleLooksChineseOnly(en)) {
      return PlayerSubtitleLine(
        startTime: line.startTime,
        english: '',
        chinese: en,
        startMs: line.startMs,
        endMs: line.endMs,
        words: const <PlayerSubtitleWord>[],
      );
    }
    return PlayerSubtitleLine(
      startTime: line.startTime,
      english: en,
      chinese: '',
      startMs: line.startMs,
      endMs: line.endMs,
      words: line.words,
    );
  }

  if (subtitleLooksChineseOnly(en)) {
    final String mergedZh = zh.isNotEmpty ? zh : en;
    return PlayerSubtitleLine(
      startTime: line.startTime,
      english: '',
      chinese: mergedZh,
      startMs: line.startMs,
      endMs: line.endMs,
      words: const <PlayerSubtitleWord>[],
    );
  }

  // Chinese leaked into english while a real English line is missing.
  if (en.isEmpty && subtitleLooksChineseOnly(zh)) {
    return PlayerSubtitleLine(
      startTime: line.startTime,
      english: '',
      chinese: zh,
      startMs: line.startMs,
      endMs: line.endMs,
      words: const <PlayerSubtitleWord>[],
    );
  }

  return line;
}
