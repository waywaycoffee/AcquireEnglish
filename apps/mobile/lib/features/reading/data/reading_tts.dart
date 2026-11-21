import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../digital_human/data/oral_coach_pipeline_client.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_pronunciation_service.dart';
import '../../sync/data/acquire_api_client.dart';

const String kReadingTtsGenderKey = 'reading_tts_gender_v1';

/// Reading uses Alibaba CosyVoice via the oral-coach `/api/tts/speak` proxy.
enum ReadingTtsGender {
  female,
  male,
}

extension ReadingTtsGenderX on ReadingTtsGender {
  String get storageValue => name;

  String get labelCn => switch (this) {
        ReadingTtsGender.female => '女声',
        ReadingTtsGender.male => '男声',
      };

  /// DashScope CosyVoice id (English).
  String get aliyunVoiceId => switch (this) {
        ReadingTtsGender.female =>
          'qwen-audio-3.0-tts-flash-loongolivialin',
        ReadingTtsGender.male => 'qwen-audio-3.0-tts-flash-loongadriangao',
      };

  String get digitalHumanId => switch (this) {
        ReadingTtsGender.female => 'mia',
        ReadingTtsGender.male => 'leo',
      };

  static ReadingTtsGender fromStorage(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'male':
        return ReadingTtsGender.male;
      case 'female':
      default:
        return ReadingTtsGender.female;
    }
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
  await Hive.box<String>('prefs').put(kReadingTtsGenderKey, gender.storageValue);
}

final OralCoachPipelineClient _readingTtsClient = OralCoachPipelineClient();

/// Prefer Alibaba Cloud TTS through the coach pipeline; fall back to device TTS.
Future<void> speakReadingText(
  WidgetRef ref,
  String text, {
  double? rate,
  ReadingTtsGender? gender,
}) async {
  final String spoken = text.trim();
  if (spoken.isEmpty) return;

  final ReadingTtsGender voice = gender ?? loadReadingTtsGender();
  final LearningSettingsState settings = ref.read(learningSettingsProvider);
  final String base = settings.oralCoachPipelineUrl.trim();
  final WordPronunciationService pronunciation =
      ref.read(wordPronunciationServiceProvider);

  // 1) ECS pre-generated reading TTS (content-addressed).
  try {
    final String? cached = await ref
        .read(acquireApiClientProvider)
        .lookupReadingSpeechUrl(
          text: spoken,
          voice: voice.aliyunVoiceId,
        );
    if (cached != null && cached.isNotEmpty) {
      await pronunciation.speak(spoken, recordedUrl: cached, rate: rate);
      return;
    }
  } catch (_) {}

  // 2) Oral-coach CosyVoice (server-side content-addressed cache).
  if (base.isNotEmpty) {
    try {
      final String? url = await _readingTtsClient.synthesizeSpeech(
        rawBaseUrl: base,
        text: spoken,
        digitalHumanId: voice.digitalHumanId,
        ttsVoice: voice.aliyunVoiceId,
      );
      if (url != null && url.isNotEmpty) {
        await pronunciation.speak(
          spoken,
          recordedUrl: url,
          rate: rate,
        );
        return;
      }
    } catch (_) {
      // Fall through to on-device TTS.
    }
  }

  await pronunciation.speak(spoken, rate: rate);
}
