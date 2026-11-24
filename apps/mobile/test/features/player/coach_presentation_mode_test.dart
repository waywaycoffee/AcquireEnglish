import 'package:flutter_test/flutter_test.dart';
import '../../../lib/features/settings/presentation/settings_provider.dart';

void main() {
  test('realtime lip-sync follows LiveTalking avatar mapping', () {
    final LearningSettingsState pipeline =
        LearningSettingsState.defaults().copyWith(
          oralCoachBackend: '视频陪练管线',
          oralCoachPipelineUrl: 'https://example.test/coach',
          digitalHumanId: 'mia',
          cartoonDigitalHuman: false,
        );
    // Default Mia maps to wav2lip_avatar_glass_man → lip-sync on.
    expect(pipeline.usesRealtimeLipSync, isTrue);
    expect(pipeline.selectedDigitalHuman.liveTalkingAvatarId, isNotEmpty);

    final LearningSettingsState localOnly = pipeline.copyWith(
      oralCoachBackend: '本地 TTS',
    );
    expect(localOnly.usesRealtimeLipSync, isFalse);

    final LearningSettingsState noAvatar = pipeline.copyWith(
      digitalHumanId: 'olivia',
    );
    expect(noAvatar.selectedDigitalHuman.liveTalkingAvatarId, isEmpty);
    expect(noAvatar.usesRealtimeLipSync, isFalse);
  });
}
