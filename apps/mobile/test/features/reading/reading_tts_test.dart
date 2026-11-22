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
      'longze_v3.1',
    );
    // ryan shares the male CosyVoice id; book-pair UI only exposes female/male.
    expect(
      ReadingTtsGender.values.map((v) => v.aliyunVoiceId).toSet(),
      hasLength(7),
    );
    expect(
      ReadingTtsGenderX.selectableBookVoices.map((v) => v.aliyunVoiceId).toSet(),
      <String>{'longanfengyue', 'longze_v3.1'},
    );
    for (final voice in ReadingTtsGender.values) {
      expect(
        ReadingTtsGenderX.fromStorage(voice.storageValue),
        voice.asBookPairVoice,
      );
    }
    expect(ReadingTtsGenderX.fromStorage('male'), ReadingTtsGender.male);
    expect(ReadingTtsGenderX.fromStorage('luna'), ReadingTtsGender.female);
    expect(ReadingTtsGenderX.fromStorage(null), ReadingTtsGender.female);
  });
}
