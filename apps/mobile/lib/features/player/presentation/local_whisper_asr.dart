import 'dart:io';

import '../../settings/presentation/settings_provider.dart';

typedef LocalWhisperProgress = void Function(double? fraction, String message);

/// Former on-device Whisper.cpp entry points.
///
/// The `whisper_cpp_flutter_plus` plugin and model weights are **not** shipped
/// in the APK. Subtitle fill uses shared cloud packs + ECS GPU generation.
/// These stubs keep call sites compiling and fail fast if still invoked.
class LocalWhisperAsr {
  LocalWhisperAsr._();

  static final LocalWhisperAsr instance = LocalWhisperAsr._();

  static const String providerName = '本地 Whisper';
  static const List<String> modelOptions = <String>[
    'tiny.en',
    'base.en',
    'small.en',
    'tiny',
    'base',
  ];
  static const String defaultModel = 'base.en';
  static const String defaultMultilingualModel = 'base';

  /// Internal failure for residual call sites — never show this as product copy.
  static const String removedMessage = '本地识别暂不可用';

  static bool isLocalProvider(LearningSettingsState settings) {
    return settings.asrProvider == providerName;
  }

  static bool needsMultilingualModel(String language) {
    final String lang = language.trim().toLowerCase();
    return lang.startsWith('zh') ||
        lang == 'chinese' ||
        lang == 'cn' ||
        lang == 'auto' ||
        lang == 'mixed';
  }

  static String modelForLanguage(
    String modelId,
    String language, {
    bool enableChineseSpeechAsr = false,
  }) {
    final String lang = language.trim().toLowerCase();
    final String id = modelId.trim().isEmpty ? defaultModel : modelId.trim();
    if (needsMultilingualModel(lang)) {
      if (!enableChineseSpeechAsr) {
        throw StateError(removedMessage);
      }
      if (id.endsWith('.en') || id == 'small.en') {
        return defaultMultilingualModel;
      }
    }
    return id;
  }

  static bool isMultilingualModel(String modelId) {
    final String id = modelId.trim();
    return id == 'tiny' || id == 'base' || (!id.contains('.en') && id.isNotEmpty);
  }

  Future<bool> isModelReady(String modelId) async {
    return false;
  }

  Future<void> ensureModel(
    String modelId, {
    LocalWhisperProgress? onProgress,
  }) async {
    onProgress?.call(null, removedMessage);
    throw StateError(removedMessage);
  }

  Future<Map<String, Object?>> transcribeChunk({
    required File file,
    required LearningSettingsState settings,
    required int offsetMs,
    String language = 'en',
    LocalWhisperProgress? onProgress,
  }) async {
    onProgress?.call(null, removedMessage);
    throw StateError(removedMessage);
  }
}
