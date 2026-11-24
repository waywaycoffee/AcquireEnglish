import 'package:flutter_test/flutter_test.dart';
import '../../../lib/features/settings/presentation/settings_provider.dart';

void main() {
  test('cartoon atlas is default; LiveTalking lip-sync stays off', () {
    final LearningSettingsState settings = LearningSettingsState.defaults();
    expect(settings.cartoonDigitalHuman, isTrue);
    expect(settings.usesRealtimeLipSync, isFalse);
    expect(settings.selectedDigitalHuman.hasCartoonAtlas, isTrue);
    expect(
      settings.selectedDigitalHuman.cartoonAssetPath,
      'assets/img/digital_human/mia-cartoon.webp',
    );
  });
}
