import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:media_kit/media_kit.dart';

import '../../settings/presentation/settings_provider.dart';
import 'aliyun_speech_service.dart';

final Provider<WordPronunciationService> wordPronunciationServiceProvider =
    Provider<WordPronunciationService>((Ref ref) {
      final LearningSettingsState settings = ref.watch(
        learningSettingsProvider,
      );
      final AliyunSpeechService aliyun = ref.watch(aliyunSpeechServiceProvider);
      return WordPronunciationService(
        selectedEngine: settings.ttsEngine,
        selectedVoice: settings.ttsVoice,
        selectedRate: settings.ttsRate,
        preferAliyunCloud: settings.preferAliyunTts,
        cloudAudioResolver: aliyun.isAvailable
            ? aliyun.resolveAudioUrl
            : null,
      );
    });

final Provider<TtsEngineService> ttsEngineServiceProvider =
    Provider<TtsEngineService>((Ref ref) => const TtsEngineService());

final FutureProvider<TtsEngineSnapshot> ttsEngineSnapshotProvider =
    FutureProvider<TtsEngineSnapshot>((Ref ref) {
      return ref.read(ttsEngineServiceProvider).fetchEngines();
    });

// ignore: always_specify_types
final ttsVoiceSnapshotProvider =
    FutureProvider.family<TtsVoiceSnapshot, String>((Ref ref, String engine) {
      return ref.read(ttsEngineServiceProvider).fetchVoices(engine: engine);
    });

const Duration _ttsBindRetryDelay = Duration(milliseconds: 150);
const int _ttsBindRetryAttempts = 2;
const double _defaultPronunciationSpeechRate = 0.75;
const MethodChannel _nativeTtsChannel = MethodChannel(
  'com.shadowing.english/native_tts',
);

/// Hold playback after end-of-stream so OEM TTS / CosyVoice tails are audible.
/// Short words ≈1s; longer spellings scale up (capped).
Duration pronunciationEndGraceFor(String text) {
  final int units = text
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z']+"), ' ')
      .split(RegExp(r'\s+'))
      .where((String w) => w.isNotEmpty)
      .fold<int>(0, (int sum, String w) => sum + w.length);
  final int letters = units <= 0 ? 1 : units;
  final int ms = (1000 + (letters - 1) * 120).clamp(1000, 3500);
  return Duration(milliseconds: ms);
}

class WordPronunciationException implements Exception {
  const WordPronunciationException([this.message = '朗读失败，请检查设备 TTS。']);

  final String message;

  @override
  String toString() => message;
}

class WordPronunciationService {
  WordPronunciationService({
    this.speakOverride,
    this.stopOverride,
    this.selectedEngine = '',
    this.selectedVoice = '',
    this.selectedRate = _defaultPronunciationSpeechRate,
    this.preferAliyunCloud = true,
    this.cloudAudioResolver,
    WordPronunciationTtsClient? ttsClient,
  }) : _ttsClient = ttsClient ?? WordPronunciationTtsClient();

  final Future<void> Function(String text)? speakOverride;
  final Future<void> Function()? stopOverride;
  final String selectedEngine;
  final String selectedVoice;
  final double selectedRate;
  /// Prefer Aliyun (DashScope) human voices via ECS-cached MP3 when available.
  final bool preferAliyunCloud;
  final Future<String?> Function(String text)? cloudAudioResolver;
  final WordPronunciationTtsClient _ttsClient;

  Player? _recordedPlayer;
  Completer<bool>? _recordedCompletion;

  Future<void> speak(
    String text, {
    String language = 'en-US',
    String? recordedUrl,
    bool allowSynthesisFallback = true,
    double? rate,
    bool forceCloud = false,
  }) async {
    if (speakOverride != null) {
      await speakOverride!(text);
      return;
    }

    final String normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return;
    }

    // One tap must never layer a new utterance on top of an in-flight one.
    await stop();

    final double effectiveRate = (rate ?? selectedRate).clamp(0.5, 1.8);

    if (recordedUrl != null &&
        await _playRecording(
          recordedUrl,
          rate: effectiveRate,
          sourceText: normalizedText,
        )) {
      return;
    }

    final bool tryCloud =
        cloudAudioResolver != null && (preferAliyunCloud || forceCloud);
    if (tryCloud) {
      final String? cloudUrl = await cloudAudioResolver!(normalizedText);
      if (cloudUrl != null &&
          cloudUrl.isNotEmpty &&
          // Keep natural CosyVoice pacing; rate only for on-device fallback.
          await _playRecording(
            cloudUrl,
            rate: 1.0,
            sourceText: normalizedText,
          )) {
        return;
      }
      // Prefer Aliyun, but keep learning moving if CDN/media path is briefly
      // broken: fall back to on-device TTS unless the caller forbids it.
      if (forceCloud && !allowSynthesisFallback) {
        throw const WordPronunciationException(
          '阿里云发音暂不可用，请确认已登录且服务器已配置配音。',
        );
      }
    } else if (forceCloud && cloudAudioResolver == null) {
      throw const WordPronunciationException(
        '请先登录账号以使用阿里云真人音色。',
      );
    }

    if (!allowSynthesisFallback) {
      throw const WordPronunciationException('词库发音暂不可用。');
    }

    await _ttsClient.speakText(
      normalizedText,
      language: language,
      engine: selectedEngine,
      voice: selectedVoice,
      rate: effectiveRate,
    );
    // Xiaomi/OEM onDone often fires before the last syllable is audible.
    await Future<void>.delayed(pronunciationEndGraceFor(normalizedText));
  }

  Future<bool> _playRecording(
    String url, {
    double rate = 1.0,
    String sourceText = '',
  }) async {
    Player? player;
    StreamSubscription<bool>? completed;
    StreamSubscription<bool>? playing;
    StreamSubscription<String>? errors;
    try {
      player = Player();
      _recordedPlayer = player;
      final Completer<bool> result = Completer<bool>();
      _recordedCompletion = result;
      bool started = false;
      bool finishing = false;
      final Duration endGrace = pronunciationEndGraceFor(sourceText);
      // Keep the player alive after EOS so CosyVoice / long words are not cut.
      void scheduleFinish(bool ok) {
        if (result.isCompleted || finishing) return;
        finishing = true;
        unawaited(() async {
          await Future<void>.delayed(endGrace);
          if (!result.isCompleted) {
            result.complete(ok);
          }
        }());
      }

      playing = player.stream.playing.listen((bool value) {
        if (value) {
          started = true;
          return;
        }
        // Only finish after playback actually started — media_kit can emit
        // completed/playing=false during open, which used to cut words short.
        if (started) {
          scheduleFinish(true);
        }
      });
      completed = player.stream.completed.listen((bool value) {
        if (value && started) {
          scheduleFinish(true);
        }
      });
      errors = player.stream.error.listen((String _) {
        if (!result.isCompleted) result.complete(false);
      });
      await player.open(Media(url), play: true).timeout(
        const Duration(seconds: 20),
      );
      // Cloud MP3 already has natural pacing; don't slow it (caused choppy cutoffs).
      final double clamped = rate.clamp(0.85, 1.8);
      if ((clamped - 1.0).abs() > 0.02) {
        await player.setRate(clamped);
      }
      // Short clips: also watch duration/position as a safety net.
      unawaited(() async {
        try {
          final Duration duration = await player!.stream.duration
              .firstWhere((Duration d) => d > Duration.zero)
              .timeout(const Duration(seconds: 5));
          await player.stream.position
              .firstWhere(
                (Duration p) =>
                    duration.inMilliseconds > 0 &&
                    p.inMilliseconds >= duration.inMilliseconds - 20,
              )
              .timeout(duration + endGrace + const Duration(seconds: 3));
          scheduleFinish(true);
        } catch (_) {}
      }());
      return await result.future.timeout(
        const Duration(seconds: 60) + endGrace,
      );
    } catch (_) {
      return false;
    } finally {
      await completed?.cancel();
      await playing?.cancel();
      await errors?.cancel();
      if (identical(_recordedPlayer, player)) {
        _recordedPlayer = null;
        _recordedCompletion = null;
        await player?.dispose();
      }
    }
  }

  Future<void> stop() async {
    if (stopOverride != null) {
      await stopOverride!();
      return;
    }
    final Player? player = _recordedPlayer;
    _recordedPlayer = null;
    final Completer<bool>? playback = _recordedCompletion;
    _recordedCompletion = null;
    if (playback != null && !playback.isCompleted) playback.complete(true);
    await player?.dispose();
    await _ttsClient.stop();
  }
}

class TtsEngineOption {
  const TtsEngineOption({
    required this.id,
    required this.label,
    required this.isDefault,
  });

  final String id;
  final String label;
  final bool isDefault;
}

class TtsEngineSnapshot {
  const TtsEngineSnapshot({required this.defaultEngine, required this.engines});

  final String defaultEngine;
  final List<TtsEngineOption> engines;
}

class TtsVoiceOption {
  const TtsVoiceOption({required this.id, required this.label});

  final String id;
  final String label;
}

class TtsVoiceSnapshot {
  const TtsVoiceSnapshot({required this.voices});

  final List<TtsVoiceOption> voices;
}

class TtsEngineService {
  const TtsEngineService({MethodChannel nativeChannel = _nativeTtsChannel})
    : _nativeChannel = nativeChannel;

  final MethodChannel _nativeChannel;

  Future<TtsEngineSnapshot> fetchEngines() async {
    try {
      final dynamic raw = await _nativeChannel.invokeMethod<dynamic>(
        'getEngines',
      );
      final Map<dynamic, dynamic> map = raw as Map<dynamic, dynamic>;
      final List<dynamic> engines =
          map['engines'] as List<dynamic>? ?? <dynamic>[];
      return TtsEngineSnapshot(
        defaultEngine: (map['defaultEngine'] as String?)?.trim() ?? '',
        engines: engines
            .map((dynamic item) {
              final Map<dynamic, dynamic> engine =
                  item as Map<dynamic, dynamic>;
              return TtsEngineOption(
                id: (engine['id'] as String?)?.trim() ?? '',
                label: (engine['label'] as String?)?.trim() ?? '',
                isDefault: engine['isDefault'] == true,
              );
            })
            .where((TtsEngineOption engine) => engine.id.isNotEmpty)
            .toList(growable: false),
      );
    } on MissingPluginException {
      return const TtsEngineSnapshot(
        defaultEngine: '',
        engines: <TtsEngineOption>[],
      );
    }
  }

  Future<TtsVoiceSnapshot> fetchVoices({required String engine}) async {
    try {
      final dynamic raw = await _nativeChannel.invokeMethod<dynamic>(
        'getVoices',
        <String, Object>{'engine': engine},
      );
      final Map<dynamic, dynamic> map = raw as Map<dynamic, dynamic>;
      final List<dynamic> voices =
          map['voices'] as List<dynamic>? ?? <dynamic>[];
      return TtsVoiceSnapshot(
        voices: voices
            .map((dynamic item) {
              final Map<dynamic, dynamic> voice = item as Map<dynamic, dynamic>;
              return TtsVoiceOption(
                id: (voice['id'] as String?)?.trim() ?? '',
                label: (voice['label'] as String?)?.trim() ?? '',
              );
            })
            .where((TtsVoiceOption voice) => voice.id.isNotEmpty)
            .toList(growable: false),
      );
    } on MissingPluginException {
      return const TtsVoiceSnapshot(voices: <TtsVoiceOption>[]);
    }
  }
}

class WordPronunciationTtsClient {
  WordPronunciationTtsClient({MethodChannel nativeChannel = _nativeTtsChannel})
    : _nativeChannel = nativeChannel;

  final MethodChannel _nativeChannel;
  FlutterTts? _flutterTts;
  bool _handlersInitialized = false;
  Completer<void>? _activeSpeakCompleter;

  FlutterTts get _client => _flutterTts ??= FlutterTts();

  Future<void> speakText(
    String text, {
    String language = 'en-US',
    String engine = '',
    String voice = '',
    double rate = _defaultPronunciationSpeechRate,
  }) async {
    try {
      final bool? success = await _nativeChannel.invokeMethod<bool>(
        'speak',
        <String, Object>{
          'text': text,
          'language': language,
          'engine': engine,
          'voice': voice,
          'rate': rate,
        },
      );
      if (success ?? false) {
        return;
      }
      throw const WordPronunciationException();
    } on MissingPluginException {
      await _speakWithFlutterTts(text, language: language, rate: rate);
    } on PlatformException {
      throw const WordPronunciationException();
    }
  }

  Future<void> stop() async {
    try {
      final bool? success = await _nativeChannel.invokeMethod<bool>('stop');
      if (success ?? false) return;
      throw const WordPronunciationException();
    } on MissingPluginException {
      _ensureHandlers();
      await _ensureTtsCallSucceeded(_client.stop());
      _completeActiveSpeak();
    } on PlatformException {
      throw const WordPronunciationException();
    }
  }

  Future<void> _speakWithFlutterTts(
    String normalizedText, {
    required String language,
    required double rate,
  }) async {
    _ensureHandlers();
    if (_activeSpeakCompleter != null) {
      await _ensureTtsCallSucceeded(_client.stop());
    }
    await _ensureLanguageReady(language);
    await _client.setSpeechRate(rate / 2);
    await _client.awaitSpeakCompletion(true);
    final Completer<void> completer = Completer<void>();
    _activeSpeakCompleter = completer;
    await _ensureTtsCallSucceeded(_client.speak(normalizedText));
    try {
      await completer.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      await _client.stop();
    } finally {
      if (identical(_activeSpeakCompleter, completer)) {
        _activeSpeakCompleter = null;
      }
    }
  }

  void _ensureHandlers() {
    if (_handlersInitialized) {
      return;
    }
    _handlersInitialized = true;
    _client
      ..setCompletionHandler(_completeActiveSpeak)
      ..setCancelHandler(_completeActiveSpeak)
      ..setErrorHandler((dynamic _) => _completeActiveSpeak());
  }

  void _completeActiveSpeak() {
    final Completer<void>? completer = _activeSpeakCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    completer.complete();
  }

  Future<void> _ensureLanguageReady(String language) async {
    for (int attempt = 0; attempt < _ttsBindRetryAttempts; attempt++) {
      try {
        await _ensureTtsCallSucceeded(_client.setLanguage(language));
        return;
      } on WordPronunciationException {
        if (attempt == _ttsBindRetryAttempts - 1) {
          rethrow;
        }
      } on PlatformException catch (error) {
        if (!_isTransientTtsBindError(error) ||
            attempt == _ttsBindRetryAttempts - 1) {
          rethrow;
        }
      }
      await Future<void>.delayed(_ttsBindRetryDelay);
    }
  }

  bool _isTransientTtsBindError(PlatformException error) {
    final String message = error.message?.toLowerCase() ?? '';
    return message.contains('not bound to tts engine');
  }

  Future<void> _ensureTtsCallSucceeded(Future<dynamic> action) async {
    final dynamic result = await action;
    if (result == false || result == 0) {
      throw const WordPronunciationException();
    }
  }
}
