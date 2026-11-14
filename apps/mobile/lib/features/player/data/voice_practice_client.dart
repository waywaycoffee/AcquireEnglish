import 'dart:io';

import 'package:dio/dio.dart';

/// Client for the vendored [Zemksh/voice](https://github.com/Zemksh/voice) sidecar.
///
/// Laptop runs `tools/voice/run_server.sh`; the phone uploads 影子跟读 audio to
/// `POST /api/shadow` for local Whisper transcript + word-overlap feedback.
class VoicePracticeClient {
  VoicePracticeClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static String normalizeBaseUrl(String raw) {
    String value = raw.trim();
    if (value.isEmpty) {
      throw StateError('请先在设置中填写 Voice 服务地址。');
    }
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  Future<VoiceHealth> health(String rawBaseUrl) async {
    final String base = normalizeBaseUrl(rawBaseUrl);
    final Response<dynamic> response = await _dio.get<dynamic>(
      '$base/api/health',
      options: Options(
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
      ),
    );
    final Object? data = response.data;
    if (data is! Map) {
      throw StateError('Voice 健康检查返回异常。');
    }
    return VoiceHealth.fromJson(data);
  }

  /// Sentence shadowing: reference English + WAV/M4A → transcript + overlap.
  Future<VoiceShadowResult> shadowSentence({
    required String rawBaseUrl,
    required String referenceText,
    required String audioPath,
  }) async {
    final String base = normalizeBaseUrl(rawBaseUrl);
    final String reference = referenceText.trim();
    if (reference.isEmpty) {
      throw StateError('没有可对照的英文句子。');
    }
    final File file = File(audioPath);
    if (!file.existsSync()) {
      throw StateError('录音文件不存在。');
    }
    final String name = file.uri.pathSegments.isEmpty
        ? 'recording.wav'
        : file.uri.pathSegments.last;
    final FormData form = FormData.fromMap(<String, dynamic>{
      'reference_text': reference,
      'file': await MultipartFile.fromFile(audioPath, filename: name),
    });
    final Response<dynamic> response = await _dio.post<dynamic>(
      '$base/api/shadow',
      data: form,
      options: Options(
        receiveTimeout: const Duration(minutes: 3),
        sendTimeout: const Duration(minutes: 2),
      ),
    );
    final Object? data = response.data;
    if (data is! Map) {
      throw StateError('Voice 影子跟读返回异常。');
    }
    return VoiceShadowResult.fromJson(data);
  }
}

class VoiceHealth {
  const VoiceHealth({
    required this.ready,
    required this.mock,
    required this.ffmpeg,
    required this.transcriptionModel,
    required this.ollama,
    required this.gemmaModel,
    required this.issues,
  });

  factory VoiceHealth.fromJson(Map<dynamic, dynamic> raw) {
    final List<String> issues = <String>[];
    final Object? rawIssues = raw['issues'];
    if (rawIssues is List) {
      for (final Object? item in rawIssues) {
        final String text = '$item'.trim();
        if (text.isNotEmpty) {
          issues.add(text);
        }
      }
    }
    return VoiceHealth(
      ready: raw['ready'] == true,
      mock: raw['mock'] == true,
      ffmpeg: raw['ffmpeg'] == true,
      transcriptionModel: raw['transcription_model'] == true,
      ollama: raw['ollama'] == true,
      gemmaModel: raw['gemma_model'] == true,
      issues: issues,
    );
  }

  final bool ready;
  final bool mock;
  final bool ffmpeg;
  final bool transcriptionModel;
  final bool ollama;
  final bool gemmaModel;
  final List<String> issues;

  /// Shadow endpoint only needs ffmpeg + whisper (or mock).
  bool get shadowReady => mock || (ffmpeg && transcriptionModel);
}

class VoiceShadowOverlap {
  const VoiceShadowOverlap({
    required this.score,
    required this.precision,
    required this.recall,
    required this.missingWords,
    required this.extraWords,
    required this.referenceWords,
    required this.hypothesisWords,
  });

  factory VoiceShadowOverlap.fromJson(Map<dynamic, dynamic> raw) {
    List<String> words(Object? value) {
      if (value is! List) {
        return const <String>[];
      }
      return value
          .map((Object? e) => '$e'.trim())
          .where((String e) => e.isNotEmpty)
          .toList(growable: false);
    }

    double number(Object? value) {
      if (value is num) {
        return value.toDouble();
      }
      return double.tryParse('$value') ?? 0;
    }

    int integer(Object? value) {
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.round();
      }
      return int.tryParse('$value') ?? 0;
    }

    return VoiceShadowOverlap(
      score: number(raw['score']),
      precision: number(raw['precision']),
      recall: number(raw['recall']),
      missingWords: words(raw['missing_words']),
      extraWords: words(raw['extra_words']),
      referenceWords: integer(raw['reference_words']),
      hypothesisWords: integer(raw['hypothesis_words']),
    );
  }

  final double score;
  final double precision;
  final double recall;
  final List<String> missingWords;
  final List<String> extraWords;
  final int referenceWords;
  final int hypothesisWords;
}

class VoiceShadowResult {
  const VoiceShadowResult({
    required this.id,
    required this.referenceText,
    required this.transcript,
    required this.duration,
    required this.mock,
    required this.overlap,
    required this.label,
  });

  factory VoiceShadowResult.fromJson(Map<dynamic, dynamic> raw) {
    final Object? overlapRaw = raw['overlap'];
    final VoiceShadowOverlap overlap = overlapRaw is Map
        ? VoiceShadowOverlap.fromJson(overlapRaw)
        : const VoiceShadowOverlap(
            score: 0,
            precision: 0,
            recall: 0,
            missingWords: <String>[],
            extraWords: <String>[],
            referenceWords: 0,
            hypothesisWords: 0,
          );
    return VoiceShadowResult(
      id: '${raw['id'] ?? ''}',
      referenceText: '${raw['reference_text'] ?? ''}',
      transcript: '${raw['transcript'] ?? ''}',
      duration: raw['duration'] is num
          ? (raw['duration'] as num).toDouble()
          : double.tryParse('${raw['duration']}') ?? 0,
      mock: raw['mock'] == true,
      overlap: overlap,
      label: '${raw['label'] ?? ''}'.trim().isEmpty
          ? 'Local shadowing feedback'
          : '${raw['label']}'.trim(),
    );
  }

  final String id;
  final String referenceText;
  final String transcript;
  final double duration;
  final bool mock;
  final VoiceShadowOverlap overlap;
  final String label;

  String get scorePercentLabel {
    final int pct = (overlap.score * 100).round().clamp(0, 100);
    return '$pct%';
  }
}
