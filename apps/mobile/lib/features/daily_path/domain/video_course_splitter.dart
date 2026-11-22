import '../../player/presentation/player_mock_state.dart';
import 'course_plan.dart';
import 'course_word_extract.dart';

class VideoCourseSplitException implements Exception {
  VideoCourseSplitException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Metadata-only video units aligned to subtitle cue starts (≤5s snap).
List<CourseUnit> splitVideoIntoUnits({
  required List<PlayerSubtitleLine> lines,
  int dailyMinutes = 10,
}) {
  final List<PlayerSubtitleLine> usable = lines
      .where((PlayerSubtitleLine l) => l.english.trim().isNotEmpty)
      .toList(growable: false);
  if (usable.isEmpty) {
    throw VideoCourseSplitException('缺少字幕，暂不支持课程化');
  }

  final int unitMs = (dailyMinutes.clamp(5, 30) * 60 * 1000);
  final int totalEnd = usable.last.endMs;
  final int totalStart = usable.first.startMs;
  final int duration = (totalEnd - totalStart).clamp(0, 1 << 30);

  // Short video (<10 min): single unit.
  if (duration < 10 * 60 * 1000) {
    return <CourseUnit>[
      _videoUnit(
        index: 0,
        lines: usable,
        startMs: usable.first.startMs,
        endMs: usable.last.endMs,
      ),
    ];
  }

  final List<CourseUnit> units = <CourseUnit>[];
  int cursor = usable.first.startMs;
  int index = 0;
  while (cursor < totalEnd) {
    final int idealEnd = cursor + unitMs;
    final int snapped = _snapToNearestCueStart(usable, idealEnd, cursor);
    final int endMs = snapped <= cursor
        ? (cursor + unitMs).clamp(0, totalEnd)
        : snapped.clamp(0, totalEnd);
    final List<PlayerSubtitleLine> slice = usable
        .where(
          (PlayerSubtitleLine l) =>
              l.startMs >= cursor && l.startMs < endMs,
        )
        .toList(growable: false);
    if (slice.isEmpty) {
      // Advance past gap.
      final PlayerSubtitleLine? next = usable
          .where((PlayerSubtitleLine l) => l.startMs >= endMs)
          .firstOrNull;
      if (next == null) break;
      cursor = next.startMs;
      continue;
    }
    units.add(
      _videoUnit(
        index: index,
        lines: slice,
        startMs: slice.first.startMs,
        endMs: slice.last.endMs,
      ),
    );
    index += 1;
    cursor = endMs;
    if (endMs >= totalEnd) break;
  }
  return units;
}

int _snapToNearestCueStart(
  List<PlayerSubtitleLine> lines,
  int idealMs,
  int notBefore,
) {
  PlayerSubtitleLine? best;
  int bestDelta = 1 << 30;
  for (final PlayerSubtitleLine line in lines) {
    if (line.startMs <= notBefore) continue;
    final int delta = (line.startMs - idealMs).abs();
    if (delta <= 5000 && delta < bestDelta) {
      best = line;
      bestDelta = delta;
    }
  }
  if (best != null) return best.startMs;
  // Fall back to first cue at/after ideal.
  for (final PlayerSubtitleLine line in lines) {
    if (line.startMs >= idealMs && line.startMs > notBefore) {
      return line.startMs;
    }
  }
  return idealMs;
}

CourseUnit _videoUnit({
  required int index,
  required List<PlayerSubtitleLine> lines,
  required int startMs,
  required int endMs,
}) {
  final List<String> sentences = lines
      .map((PlayerSubtitleLine l) => l.english.trim())
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);
  final String topic = sentences.isEmpty
      ? '视频小节 ${index + 1}'
      : (sentences.first.length > 36
          ? '${sentences.first.substring(0, 36)}…'
          : sentences.first);
  return CourseUnit(
    unitId: 's${(index + 1).toString().padLeft(2, '0')}',
    startMs: startMs,
    endMs: endMs,
    sentences: sentences,
    wordIds: extractCourseWordIds(sentences),
    topic: topic,
  );
}
