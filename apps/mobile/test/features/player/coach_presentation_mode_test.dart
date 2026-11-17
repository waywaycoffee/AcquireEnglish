import 'package:flutter_test/flutter_test.dart';
import '../../../lib/features/settings/presentation/settings_provider.dart';
void main() {
  test('cartoon avoids LiveTalking while portrait can use existing pipeline', () {
    final LearningSettingsState settings = LearningSettingsState.defaults().copyWith(
      oralCoachBackend: '视频陪练管线', oralCoachPipelineUrl: 'https://example.test/coach', cartoonDigitalHuman: true);
    expect(settings.usesRealtimeLipSync, isFalse);
    final LearningSettingsState portrait = settings.copyWith(cartoonDigitalHuman: false);
    expect(portrait.usesRealtimeLipSync, isTrue);
    expect(portrait.copyWith(digitalHumanId: 'leo').digitalHumanId, 'leo');
    expect(portrait.copyWith(digitalHumanId: 'leo').cartoonDigitalHuman, isFalse);
  });
}
