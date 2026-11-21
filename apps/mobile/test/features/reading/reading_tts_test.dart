import 'package:common_learn_english/features/reading/data/reading_tts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reading TTS gender maps to Alibaba CosyVoice ids', () {
    expect(
      ReadingTtsGender.female.aliyunVoiceId,
      'longanfengyue',
    );
    expect(
      ReadingTtsGender.male.aliyunVoiceId,
      'longshu_v3.1',
    );
    expect(
      ReadingTtsGender.values.map((v) => v.aliyunVoiceId).toSet(),
      hasLength(8),
    );
    for (final voice in ReadingTtsGender.values) {
      expect(ReadingTtsGenderX.fromStorage(voice.storageValue), voice);
    }
    expect(ReadingTtsGenderX.fromStorage('male'), ReadingTtsGender.male);
    expect(ReadingTtsGenderX.fromStorage(null), ReadingTtsGender.female);
  });
}
