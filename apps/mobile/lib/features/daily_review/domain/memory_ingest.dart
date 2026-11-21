import 'package:fsrs/fsrs.dart' as fsrs;

import '../../community/domain/cafe_adventure.dart';
import 'daily_review.dart';
import 'memory_item.dart';

/// Shared helpers for building unified memory keys / payloads.
class MemoryIngest {
  MemoryIngest._();

  static MemoryItem clipFromLine({
    required String episodeId,
    required String english,
    required String chinese,
    required int startMs,
    required int endMs,
    required String startTime,
    String? courseTitle,
    String? episodeTitle,
    String origin = 'manual',
  }) {
    final String key = MemoryItem.clipKey(
      episodeId: episodeId,
      startMs: startMs,
      endMs: endMs,
      english: english,
    );
    return MemoryItem(
      key: key,
      kind: ReviewKind.clip,
      question: chinese.trim().isEmpty ? '听原句，用英语复述' : chinese.trim(),
      answer: english.trim(),
      english: english.trim(),
      chinese: chinese.trim(),
      sourceLabel: <String>[
        if ((courseTitle ?? '').trim().isNotEmpty) courseTitle!.trim(),
        if ((episodeTitle ?? '').trim().isNotEmpty) episodeTitle!.trim(),
      ].join(' · '),
      episodeId: episodeId,
      time: startTime,
      startMs: startMs,
      endMs: endMs,
      origin: origin,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static MemoryItem cafeSkill(int levelIndex) {
    final CafeLevel level = kCafeLevels[levelIndex.clamp(0, kCafeLevels.length - 1)];
    return MemoryItem(
      key: MemoryItem.cafeSkillKey(levelIndex),
      kind: ReviewKind.skill,
      question: level.prompt,
      answer: level.answers[level.correct],
      english: level.answers[level.correct],
      chinese: '${level.title} · ${level.ability}',
      sourceLabel: '街角咖啡店 · ${level.title}',
      skillChapter: 'cafe',
      skillLevel: levelIndex,
      origin: 'cafe',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Map a raw shadowing score (0–100) onto FSRS ratings.
  static fsrs.Rating? ratingForShadowScore(int? scorePercent) {
    if (scorePercent == null) return null;
    if (scorePercent < 60) return fsrs.Rating.again;
    if (scorePercent < 75) return fsrs.Rating.hard;
    return null; // good enough — do not spam the queue
  }
}
