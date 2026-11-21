import 'package:common_learn_english/features/daily_review/domain/daily_review.dart';
import 'package:common_learn_english/features/daily_review/domain/memory_ingest.dart';
import 'package:common_learn_english/features/daily_review/domain/memory_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

void main() {
  test('clip and cafe skill keys are stable', () {
    final MemoryItem clip = MemoryIngest.clipFromLine(
      episodeId: 'ep1',
      english: 'A small coffee to go, please.',
      chinese: '请来一杯外带小杯咖啡',
      startMs: 1000,
      endMs: 4000,
      startTime: '00:01',
      origin: 'dictation',
    );
    expect(clip.kind, ReviewKind.clip);
    expect(clip.key, startsWith('clip:ep1:1000:4000:'));
    expect(clip.toSource().startMs, 1000);

    final MemoryItem skill = MemoryIngest.cafeSkill(1);
    expect(skill.kind, ReviewKind.skill);
    expect(skill.key, 'skill:cafe:1');
    expect(skill.skillLevel, 1);
    expect(skill.toSource().answer, isNotEmpty);
  });

  test('shadow score maps to FSRS ratings', () {
    expect(MemoryIngest.ratingForShadowScore(40), fsrs.Rating.again);
    expect(MemoryIngest.ratingForShadowScore(70), fsrs.Rating.hard);
    expect(MemoryIngest.ratingForShadowScore(90), isNull);
  });
}
