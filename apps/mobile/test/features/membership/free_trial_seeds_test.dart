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

  test('starter reading preview ids stay free', () {
    expect(isFreeReadingPreviewDocId('starter-rainy-afternoon'), isTrue);
    expect(isFreeReadingPreviewDocId('catalog_other_book'), isFalse);
  });

  test('personal upload floor is at least 15', () {
    expect(kFreePersonalUploadSlotsMin, greaterThanOrEqualTo(15));
  });
}
