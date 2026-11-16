import '../player/presentation/bilingual_subtitle_helpers.dart';
import '../player/presentation/player_mock_state.dart';
import '../player/presentation/subtitle_file_persist.dart';

/// Result of client-side shared-pack heuristics (mirrors ECS rules).
class SharedSubtitleQualityResult {
  const SharedSubtitleQualityResult({
    required this.passed,
    required this.score,
    required this.cueCount,
    required this.enHits,
    required this.zhHits,
    this.reason = '',
  });

  final bool passed;
  final double score;
  final int cueCount;
  final int enHits;
  final int zhHits;
  final String reason;
}

/// Parse SRT text into timed cues (startMs, endMs, body).
List<({int startMs, int endMs, String body})> parseSrtCues(String srt) {
  final String text =
      srt.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (text.isEmpty) {
    return const <({int startMs, int endMs, String body})>[];
  }
  final List<({int startMs, int endMs, String body})> cues =
      <({int startMs, int endMs, String body})>[];
  final RegExp ts = RegExp(
    r'(\d{1,2}:\d{2}:\d{2}[.,]\d{1,3})\s*-->\s*(\d{1,2}:\d{2}:\d{2}[.,]\d{1,3})',
  );
  for (final String block in text.split(RegExp(r'\n\s*\n+'))) {
    final List<String> lines = block
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      continue;
    }
    List<String> bodyLines = lines;
    if (int.tryParse(lines.first) != null && lines.length >= 2) {
      bodyLines = lines.sublist(1);
    }
    if (bodyLines.isEmpty) {
      continue;
    }
    final RegExpMatch? match = ts.firstMatch(bodyLines.first);
    if (match == null) {
      continue;
    }
    final int startMs = _clockToMs(match.group(1)!);
    final int endMs = _clockToMs(match.group(2)!);
    final String body = bodyLines.skip(1).join(' ').trim();
    if (endMs <= startMs || body.isEmpty) {
      continue;
    }
    cues.add((startMs: startMs, endMs: endMs, body: body));
  }
  return cues;
}

int _clockToMs(String raw) {
  final String cleaned = raw.replaceAll(',', '.');
  final List<String> parts = cleaned.split(':');
  if (parts.length != 3) {
    return 0;
  }
  final int hours = int.tryParse(parts[0]) ?? 0;
  final int minutes = int.tryParse(parts[1]) ?? 0;
  final List<String> secParts = parts[2].split('.');
  final int seconds = int.tryParse(secParts[0]) ?? 0;
  final int millis = secParts.length > 1
      ? int.tryParse((secParts[1] + '000').substring(0, 3)) ?? 0
      : 0;
  return ((hours * 60 + minutes) * 60 + seconds) * 1000 + millis;
}

/// Evaluate EN (+ optional ZH) SRT for shared-cache upload eligibility.
SharedSubtitleQualityResult evaluateSharedSubtitlePack({
  required String enSrt,
  String? zhSrt,
  int? durationSec,
}) {
  final List<({int startMs, int endMs, String body})> enCues =
      parseSrtCues(enSrt);
  final List<({int startMs, int endMs, String body})> zhCues =
      parseSrtCues(zhSrt ?? '');
  if (enCues.length < 5) {
    return SharedSubtitleQualityResult(
      passed: false,
      score: 0,
      cueCount: enCues.length,
      enHits: 0,
      zhHits: 0,
      reason: '英文字幕句数不足（至少 5 句）',
    );
  }

  final int enHits = enCues.where((cue) => looksEnglish(cue.body)).length;
  if (enHits * 2 < enCues.length) {
    return SharedSubtitleQualityResult(
      passed: false,
      score: 0,
      cueCount: enCues.length,
      enHits: enHits,
      zhHits: 0,
      reason: '英文字幕语言比例不合格',
    );
  }

  int zhHits = 0;
  if (zhCues.isNotEmpty) {
    zhHits = zhCues.where((cue) => looksChinese(cue.body)).length;
    if (zhHits * 2 < zhCues.length) {
      return SharedSubtitleQualityResult(
        passed: false,
        score: 0,
        cueCount: enCues.length,
        enHits: enHits,
        zhHits: zhHits,
        reason: '中文字幕语言比例不合格',
      );
    }
  }

  final int lastEndMs =
      enCues.map((cue) => cue.endMs).reduce((a, b) => a > b ? a : b);
  if (durationSec != null && durationSec >= 30) {
    final int mediaMs = durationSec * 1000;
    if (lastEndMs < mediaMs * 0.70) {
      return SharedSubtitleQualityResult(
        passed: false,
        score: 0,
        cueCount: enCues.length,
        enHits: enHits,
        zhHits: zhHits,
        reason: '字幕时长覆盖不足（需达到视频约 70%）',
      );
    }
  }

  final double enRatio = enHits / enCues.length;
  final double zhBonus =
      zhCues.isNotEmpty && zhHits * 2 >= zhCues.length ? 0.15 : 0.0;
  double coverage = 1.0;
  if (durationSec != null && durationSec >= 30) {
    coverage = (lastEndMs / (durationSec * 1000)).clamp(0.0, 1.0);
  }
  double score = (enRatio * 0.7 + coverage * 0.15 + zhBonus).clamp(0.0, 1.0);
  if (enCues.length >= 40) {
    score = (score + 0.05).clamp(0.0, 1.0);
  }
  final bool passed = score >= 0.55;
  return SharedSubtitleQualityResult(
    passed: passed,
    score: double.parse(score.toStringAsFixed(4)),
    cueCount: enCues.length,
    enHits: enHits,
    zhHits: zhHits,
    reason: passed ? '' : '质量分过低',
  );
}

/// Convenience: evaluate from already-parsed player lines.
SharedSubtitleQualityResult evaluateSharedSubtitleLines({
  required List<PlayerSubtitleLine> english,
  List<PlayerSubtitleLine> chinese = const <PlayerSubtitleLine>[],
  int? durationSec,
}) {
  return evaluateSharedSubtitlePack(
    enSrt: linesToSrt(lines: english, english: true),
    zhSrt: chinese.isEmpty
        ? null
        : linesToSrt(lines: chinese, english: false),
    durationSec: durationSec,
  );
}

/// Build a multi-cue English SRT sample for tests.
String buildSampleEnglishSrt({int cues = 8, int gapMs = 2000}) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < cues; i++) {
    final int start = i * gapMs;
    final int end = start + gapMs - 200;
    out
      ..writeln(i + 1)
      ..writeln('${formatSrtTimestamp(start)} --> ${formatSrtTimestamp(end)}')
      ..writeln('Hello world sentence number ${i + 1}.')
      ..writeln();
  }
  return out.toString();
}

String buildSampleChineseSrt({int cues = 8, int gapMs = 2000}) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < cues; i++) {
    final int start = i * gapMs;
    final int end = start + gapMs - 200;
    out
      ..writeln(i + 1)
      ..writeln('${formatSrtTimestamp(start)} --> ${formatSrtTimestamp(end)}')
      ..writeln('你好世界第${i + 1}句。')
      ..writeln();
  }
  return out.toString();
}
