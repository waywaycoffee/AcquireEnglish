import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../sync/data/acquire_api_client.dart';

/// Default Aliyun CosyVoice for vocab / review cards (expressive, recommended).
/// Override in settings; English flash voices remain available there.
const String kDefaultAliyunTtsVoice = 'longanfengyue';

final Provider<AliyunSpeechService> aliyunSpeechServiceProvider =
    Provider<AliyunSpeechService>((Ref ref) {
      return AliyunSpeechService(
        api: ref.watch(acquireApiClientProvider),
        isLoggedIn: ref.watch(authSessionProvider).isLoggedIn,
        voice: ref.watch(
          learningSettingsProvider.select(
            (LearningSettingsState s) => s.cloudTtsVoice,
          ),
        ),
      );
    });

/// Resolves Aliyun TTS audio URLs (cached on ECS `/media/reading/speech`).
class AliyunSpeechService {
  AliyunSpeechService({
    required this.api,
    required this.isLoggedIn,
    required this.voice,
  });

  final AcquireApiClient api;
  final bool isLoggedIn;
  final String voice;

  String get resolvedVoice {
    final String trimmed = voice.trim();
    return trimmed.isEmpty ? kDefaultAliyunTtsVoice : trimmed;
  }

  bool get isAvailable => isLoggedIn;

  Future<String?> resolveAudioUrl(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty || !isAvailable) return null;
    try {
      return await api.readingSpeech(trimmed, resolvedVoice);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> fetchVoices() => api.readingVoices();
}
