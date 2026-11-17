import 'package:flutter_test/flutter_test.dart';
import '../../../lib/features/player/data/dub_session_store.dart';
void main() {
  test('legacy recordings remain readable without a score', () {
    final DubTake take = DubTake.fromJson(<String, dynamic>{});
    expect(take.scorePercent, isNull);
    expect(take.professionalScore, isFalse);
  });
  test('score type survives persistence', () {
    for (final bool professional in <bool>[true, false]) {
      final DubTake take = DubTake(episodeId: 'episode', lineId: '10-20',
        startMs: 10, endMs: 20, english: 'Hello', userWavPath: '/missing.wav',
        createdAt: DateTime.utc(2026), scorePercent: 82, professionalScore: professional);
      final DubTake restored = DubTake.fromJson(take.toJson());
      expect(restored.professionalScore, professional);
      expect(restored.scorePercent, 82);
    }
  });
}
