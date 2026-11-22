import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../shared/data/word_pronunciation_service.dart';
import '../../sync/data/acquire_api_client.dart';

const String kReadingTtsGenderKey = 'reading_tts_gender_v1';

/// Reading uses expressive Aliyun CosyVoice narrators via ECS `/api/reading/speech`.
/// Long novels always pregen the [female]/[male] pair onto ECS.
enum ReadingTtsGender { female, male, luna, nora, ivy, alexander, james, ryan }

/// Canonical emotional pair saved per long novel on ECS.
const String kReadingBookFemaleVoiceId = 'longanfengyue';
const String kReadingBookMaleVoiceId = 'longze_v3.1';

extension ReadingTtsGenderX on ReadingTtsGender {
  String get storageValue => name;

  String get labelCn => switch (this) {
    ReadingTtsGender.female => '女声 · 龙安风悦（温暖有感情）',
    ReadingTtsGender.male => '男声 · 龙泽（磁性有感情）',
    ReadingTtsGender.luna => '龙安小昕 · 亲切活泼',
    ReadingTtsGender.nora => '龙安灵希 · 甜美轻快',
    ReadingTtsGender.ivy => '龙安欢 · 元气感染力',
    ReadingTtsGender.alexander => '龙小诚 · 沉稳男声',
    ReadingTtsGender.james => '李白 · 文气旁白',
    ReadingTtsGender.ryan => '龙泽 · 磁性男声',
  };

  /// CosyVoice bilingual ids — richer prosody than flat English-native loong voices.
  String get aliyunVoiceId => switch (this) {
    ReadingTtsGender.female => kReadingBookFemaleVoiceId,
    ReadingTtsGender.male => kReadingBookMaleVoiceId,
    ReadingTtsGender.luna => 'longanxiaoxin',
    ReadingTtsGender.nora => 'longanlingxi',
    ReadingTtsGender.ivy => 'longanhuan_v3.6',
    ReadingTtsGender.alexander => 'longxiaocheng_v3.1',
    ReadingTtsGender.james => 'libai_v3.1',
    ReadingTtsGender.ryan => kReadingBookMaleVoiceId,
  };

  bool get isBookPairVoice =>
      this == ReadingTtsGender.female || this == ReadingTtsGender.male;

  /// Only the emotional book-pair voices are offered in the reading UI.
  static const List<ReadingTtsGender> selectableBookVoices =
      <ReadingTtsGender>[
        ReadingTtsGender.female,
        ReadingTtsGender.male,
      ];

  /// Map legacy CosyVoice picks onto the book pair (female / male only).
  ReadingTtsGender get asBookPairVoice => switch (this) {
        ReadingTtsGender.female ||
        ReadingTtsGender.luna ||
        ReadingTtsGender.nora ||
        ReadingTtsGender.ivy =>
          ReadingTtsGender.female,
        ReadingTtsGender.male ||
        ReadingTtsGender.alexander ||
        ReadingTtsGender.james ||
        ReadingTtsGender.ryan =>
          ReadingTtsGender.male,
      };

  static ReadingTtsGender fromStorage(String? raw) {
    final ReadingTtsGender hit = ReadingTtsGender.values.firstWhere(
      (ReadingTtsGender v) => v.name == raw,
      orElse: () => ReadingTtsGender.female,
    );
    return hit.asBookPairVoice;
  }
}

ReadingTtsGender loadReadingTtsGender() {
  if (!Hive.isBoxOpen('prefs')) return ReadingTtsGender.female;
  return ReadingTtsGenderX.fromStorage(
    Hive.box<String>('prefs').get(kReadingTtsGenderKey),
  );
}

Future<void> saveReadingTtsGender(ReadingTtsGender gender) async {
  if (!Hive.isBoxOpen('prefs')) return;
  await Hive.box<String>(
    'prefs',
  ).put(kReadingTtsGenderKey, gender.asBookPairVoice.storageValue);
}

/// Kick off ECS TTS without awaiting playback (continuous / prefetch).
Future<String> prefetchReadingSpeechUrl(
  WidgetRef ref,
  String text, {
  ReadingTtsGender? gender,
}) {
  final String spoken = text.trim();
  if (spoken.isEmpty) {
    return Future<String>.error(StateError('empty speech text'));
  }
  final ReadingTtsGender voice =
      (gender ?? loadReadingTtsGender()).asBookPairVoice;
  return ref
      .read(acquireApiClientProvider)
      .readingSpeech(spoken, voice.aliyunVoiceId);
}

/// Synthesize only through the authenticated ECS Aliyun endpoint.
/// Never falls back to device/Edge TTS (keeps reading voice consistent).
Future<void> speakReadingText(
  WidgetRef ref,
  String text, {
  double? rate,
  ReadingTtsGender? gender,
}) async {
  final String spoken = text.trim();
  if (spoken.isEmpty) return;
  final ReadingTtsGender voice =
      (gender ?? loadReadingTtsGender()).asBookPairVoice;
  final String url = await ref
      .read(acquireApiClientProvider)
      .readingSpeech(spoken, voice.aliyunVoiceId);
  await ref
      .read(wordPronunciationServiceProvider)
      .speak(
        spoken,
        recordedUrl: url,
        rate: rate,
        allowSynthesisFallback: false,
      );
}
