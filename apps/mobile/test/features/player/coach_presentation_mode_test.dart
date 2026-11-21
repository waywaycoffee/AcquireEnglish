import 'package:flutter_test/flutter_test.dart';
import '../../../lib/features/settings/presentation/settings_provider.dart';

void main() {
  test('realtime lip-sync stays off for digital-human chat', () {
    final LearningSettingsState settings =
        LearningSettingsState.defaults().copyWith(
          oralCoachBackend: '视频陪练管线',
          oralCoachPipelineUrl: 'https://example.test/coach',
          cartoonDigitalHuman: true,
        );
    expect(settings.usesRealtimeLipSync, isFalse);
    final LearningSettingsState portrait = settings.copyWith(
      cartoonDigitalHuman: false,
    );
    // LiveTalking lip-sync is disabled until the dedicated avatar pipeline is ready.
    expect(portrait.usesRealtimeLipSync, isFalse);
    expect(portrait.copyWith(digitalHumanId: 'leo').digitalHumanId, 'leo');
    expect(portrait.copyWith(digitalHumanId: 'leo').cartoonDigitalHuman, isFalse);
  });
}
