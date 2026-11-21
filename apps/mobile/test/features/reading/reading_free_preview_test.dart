import 'package:common_learn_english/features/membership/domain/module_access.dart';
import 'package:common_learn_english/features/reading/data/reading_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starter stories and the default Oz book are free previews', () {
    expect(isFreeReadingPreviewDocId('starter-cafe'), isTrue);
    expect(isFreeReadingPreviewDocId('starter-rainy-afternoon'), isTrue);
    expect(
      isFreeReadingPreviewDocId(kDefaultWizardOfOzEntry.stableDocId),
      isTrue,
    );
    expect(isFreeReadingPreviewDocId('catalog_other_book'), isFalse);
  });
}
