import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../shared/data/word_pronunciation_service.dart';
import '../../sync/data/acquire_api_client.dart';

const String kReadingTtsGenderKey = 'reading_tts_gender_v1';

/// Reading uses Alibaba CosyVoice via the oral-coach `/api/tts/speak` proxy.
enum ReadingTtsGender { female, male, luna, nora, ivy, alexander, james, ryan }

extension ReadingTtsGenderX on ReadingTtsGender {
  String get storageValue => name;

  String get labelCn => switch (this) {
    ReadingTtsGender.female => 'Olivia Lin',
    ReadingTtsGender.male => 'Adrian Gao',
    ReadingTtsGender.luna => 'Luna Wang',
    ReadingTtsGender.nora => 'Nora Hu',
    ReadingTtsGender.ivy => 'Ivy Hu',
    ReadingTtsGender.alexander => 'Alexander Hu',
    ReadingTtsGender.james => 'James Zhao',
    ReadingTtsGender.ryan => 'Ryan Ma',
  };

  /// DashScope CosyVoice id (English).
  String get aliyunVoiceId => switch (this) {
    ReadingTtsGender.female => 'qwen-audio-3.0-tts-flash-loongolivialin',
    ReadingTtsGender.male => 'qwen-audio-3.0-tts-flash-loongadriangao',
    ReadingTtsGender.luna => 'qwen-audio-3.0-tts-flash-loonglunawang',
    ReadingTtsGender.nora => 'qwen-audio-3.0-tts-flash-loongnorahu',
    ReadingTtsGender.ivy => 'qwen-audio-3.0-tts-flash-loongivyhu',
    ReadingTtsGender.alexander => 'qwen-audio-3.0-tts-flash-loongalexanderhu',
    ReadingTtsGender.james => 'qwen-audio-3.0-tts-flash-loongjameszhao',
    ReadingTtsGender.ryan => 'qwen-audio-3.0-tts-flash-loongryanma',
  };

  static ReadingTtsGender fromStorage(String? raw) => ReadingTtsGender.values
      .firstWhere((v) => v.name == raw, orElse: () => ReadingTtsGender.female);
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
  ).put(kReadingTtsGenderKey, gender.storageValue);
}

/// Synthesize only through the authenticated ECS Aliyun endpoint.
Future<void> speakReadingText(
  WidgetRef ref,
  String text, {
  double? rate,
  ReadingTtsGender? gender,
}) async {
  if (text.trim().isEmpty) return;
  final voice = gender ?? loadReadingTtsGender();
  final url = await ref
      .read(acquireApiClientProvider)
      .readingSpeech(text.trim(), voice.aliyunVoiceId);
  await ref
      .read(wordPronunciationServiceProvider)
      .speak(text, recordedUrl: url, rate: rate, allowSynthesisFallback: false);
}
