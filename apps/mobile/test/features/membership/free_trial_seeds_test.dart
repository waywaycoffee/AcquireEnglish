import 'package:common_learn_english/features/membership/domain/free_trial_seeds.dart';
import 'package:common_learn_english/features/membership/domain/module_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each module ships about five permanent free starters with a path', () {
    for (final String code in <String>['video', 'reading', 'exam', 'course']) {
      final List<FreeTrialSeedItem> rows = freeTrialSeedsFor(code);
      expect(rows.length, kModuleFreePreviewCount);
      for (final FreeTrialSeedItem item in rows) {
        expect(item.freeTrial, isTrue);
        expect(item.id, isNotEmpty);
        expect(item.learningPath.length, greaterThanOrEqualTo(3));
      }
    }
  });

  test('grandfather keeps labeled free shelf items open', () {
    expect(
      isGrandfatheredFreeReading(
        docId: 'user-imported-1',
        sourceLabel: '免费体验 · 入门推荐',
      ),
      isTrue,
    );
    expect(
      isGrandfatheredFreeReading(
        docId: 'catalog_other_book',
        sourceLabel: '社区精选',
      ),
      isFalse,
    );
    expect(isFreeReadingPreviewDocId('starter-rainy-afternoon'), isTrue);
  });

  test('personal upload floor is at least 15', () {
    expect(kFreePersonalUploadSlotsMin, greaterThanOrEqualTo(15));
  });
}
