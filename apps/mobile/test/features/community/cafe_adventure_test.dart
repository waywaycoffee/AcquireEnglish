import 'package:common_learn_english/features/community/domain/cafe_adventure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cafe challenge path round-trip', () {
    expect(cafeChallengePath(2), '/community/explore/cafe/3');
    expect(cafeLevelFromPath('/community/explore/cafe/3'), 2);
    expect(cafeLevelFromPath('/community/explore/cafe/30'), isNull);
    expect(cafeLevelFromPath(null), isNull);
  });

  test('cafe week id is stable within week', () {
    final String a = cafeWeekId(DateTime(2026, 11, 21));
    final String b = cafeWeekId(DateTime(2026, 11, 22));
    expect(a, startsWith('2026-W'));
    expect(a, b);
  });
}
