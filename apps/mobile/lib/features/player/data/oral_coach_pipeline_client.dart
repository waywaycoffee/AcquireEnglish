import 'dart:io';

import 'package:dio/dio.dart';

/// Client for `tools/oral_coach` video-topic conversation sidecar.
class OralCoachPipelineClient {
  OralCoachPipelineClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static String normalizeBaseUrl(String raw) {
    String value = raw.trim();
    if (value.isEmpty) {
      throw StateError('请先在设置中填写视频陪练管线地址。');
    }
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  Future<Map<String, dynamic>> health(String rawBaseUrl) async {
    final String base = normalizeBaseUrl(rawBaseUrl);
    final Response<dynamic> response = await _dio.get<dynamic>(
      '$base/api/health',
      options: Options(
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    return _asMap(response.data);
  }

  Future<OralCoachSession> createSession({
    required String rawBaseUrl,
    required OralCoachVideoContext context,
  }) async {
    final String base = normalizeBaseUrl(rawBaseUrl);
    final Response<dynamic> response = await _dio.post<dynamic>(
      '$base/api/sessions',
      data: context.toJson(),
      options: Options(
        contentType: Headers.jsonContentType,
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    final Map<String, dynamic> body = _asMap(response.data);
    final String id = '${body['id'] ?? ''}'.trim();
    if (id.isEmpty) {
      throw StateError('陪练会话创建失败。');
    }
    return OralCoachSession(id: id, baseUrl: base, difficulty: '${body['difficulty'] ?? 'B1'}');
  }

  Future<void> updateContext({
    required OralCoachSession session,
    required OralCoachVideoContext context,
  }) async {
    await _dio.patch<dynamic>(
      '${session.baseUrl}/api/sessions/${session.id}/context',
      data: context.toJson(),
      options: Options(
        contentType: Headers.jsonContentType,
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
  }

  Future<OralCoachDraftResult> createDraft({
    required OralCoachSession session,
    required String audioPath,
    String? referenceText,
  }) async {
    final File file = File(audioPath);
    if (!file.existsSync()) {
      throw StateError('录音文件不存在。');
    }
    final String name = file.uri.pathSegments.isEmpty
        ? 'turn.wav'
        : file.uri.pathSegments.last;
    final FormData form = FormData.fromMap(<String, dynamic>{
      if ((referenceText ?? '').trim().isNotEmpty)
        'reference_text': referenceText!.trim(),
      'file': await MultipartFile.fromFile(audioPath, filename: name),
    });
    final Response<dynamic> response = await _dio.post<dynamic>(
      '${session.baseUrl}/api/sessions/${session.id}/draft',
      data: form,
      options: Options(
        sendTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 3),
      ),
    );
    final Map<String, dynamic> body = _asMap(response.data);
    final String draftId = '${body['draft_id'] ?? ''}'.trim();
    if (draftId.isEmpty) {
      throw StateError('转写草稿创建失败。');
    }
    final Map<String, dynamic> pron = body['pronunciation'] is Map
        ? Map<String, dynamic>.from(body['pronunciation'] as Map)
        : <String, dynamic>{};
    return OralCoachDraftResult(
      draftId: draftId,
      transcript: '${body['transcript'] ?? ''}',
      pronunciationOverall: (pron['overall'] is num)
          ? (pron['overall'] as num).toDouble()
          : double.tryParse('${pron['overall']}') ?? 0,
      pronunciationNotes: '${pron['notes'] ?? ''}',
    );
  }

  Future<OralCoachTurnResult> confirmDraft({
    required OralCoachSession session,
    required String draftId,
    String? confirmedText,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '${session.baseUrl}/api/sessions/${session.id}/confirm',
      data: <String, dynamic>{
        'draft_id': draftId,
        if ((confirmedText ?? '').trim().isNotEmpty)
          'confirmed_text': confirmedText!.trim(),
      },
      options: Options(
        contentType: Headers.jsonContentType,
        sendTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 3),
      ),
    );
    return OralCoachTurnResult.fromJson(_asMap(response.data), session.baseUrl);
  }

  Future<OralCoachTurnResult> turn({
    required OralCoachSession session,
    required String audioPath,
    String? referenceText,
  }) async {
    final File file = File(audioPath);
    if (!file.existsSync()) {
      throw StateError('录音文件不存在。');
    }
    final String name = file.uri.pathSegments.isEmpty
        ? 'turn.wav'
        : file.uri.pathSegments.last;
    final FormData form = FormData.fromMap(<String, dynamic>{
      if ((referenceText ?? '').trim().isNotEmpty)
        'reference_text': referenceText!.trim(),
      'file': await MultipartFile.fromFile(audioPath, filename: name),
    });
    final Response<dynamic> response = await _dio.post<dynamic>(
      '${session.baseUrl}/api/sessions/${session.id}/turn',
      data: form,
      options: Options(
        sendTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 3),
      ),
    );
    return OralCoachTurnResult.fromJson(_asMap(response.data), session.baseUrl);
  }

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{};
  }
}

class OralCoachVideoContext {
  const OralCoachVideoContext({
    this.courseTitle = '',
    this.episodeTitle = '',
    this.currentEnglish = '',
    this.currentChinese = '',
    this.previousEnglish = '',
    this.nextEnglish = '',
    this.difficulty = 'B1',
  });

  final String courseTitle;
  final String episodeTitle;
  final String currentEnglish;
  final String currentChinese;
  final String previousEnglish;
  final String nextEnglish;
  final String difficulty;

  Map<String, Object?> toJson() => <String, Object?>{
    'course_title': courseTitle,
    'episode_title': episodeTitle,
    'current_english': currentEnglish,
    'current_chinese': currentChinese,
    'previous_english': previousEnglish,
    'next_english': nextEnglish,
    'difficulty': difficulty,
  };
}

class OralCoachSession {
  const OralCoachSession({
    required this.id,
    required this.baseUrl,
    this.difficulty = 'B1',
  });

  final String id;
  final String baseUrl;
  final String difficulty;
}

class OralCoachDraftResult {
  const OralCoachDraftResult({
    required this.draftId,
    required this.transcript,
    required this.pronunciationOverall,
    required this.pronunciationNotes,
  });

  final String draftId;
  final String transcript;
  final double pronunciationOverall;
  final String pronunciationNotes;
}

class OralCoachTurnResult {
  const OralCoachTurnResult({
    required this.transcript,
    required this.coachText,
    required this.difficulty,
    required this.pronunciationOverall,
    required this.pronunciationNotes,
    required this.corrections,
    required this.ttsUrl,
    required this.avatarAction,
    required this.avatarText,
    required this.livetalkingUrl,
    required this.providers,
  });

  factory OralCoachTurnResult.fromJson(
    Map<String, dynamic> raw,
    String baseUrl,
  ) {
    final Map<String, dynamic> pron = raw['pronunciation'] is Map
        ? Map<String, dynamic>.from(raw['pronunciation'] as Map)
        : <String, dynamic>{};
    final Map<String, dynamic> avatar = raw['avatar'] is Map
        ? Map<String, dynamic>.from(raw['avatar'] as Map)
        : <String, dynamic>{};
    final Object? tts = raw['tts_url'];
    String? ttsUrl;
    if (tts is String && tts.trim().isNotEmpty) {
      ttsUrl = tts.startsWith('http') ? tts : '$baseUrl$tts';
    }
    final List<String> corrections = <String>[];
    final Object? rawCorrections = raw['corrections'];
    if (rawCorrections is List) {
      for (final Object? item in rawCorrections) {
        final String text = '$item'.trim();
        if (text.isNotEmpty) {
          corrections.add(text);
        }
      }
    }
    final Map<String, String> providers = <String, String>{};
    final Object? rawProviders = raw['providers'];
    if (rawProviders is Map) {
      rawProviders.forEach((Object? key, Object? value) {
        providers['$key'] = '$value';
      });
    }
    final Object? overall = pron['overall'];
    return OralCoachTurnResult(
      transcript: '${raw['transcript'] ?? ''}',
      coachText: '${raw['coach_text'] ?? ''}',
      difficulty: '${raw['difficulty'] ?? 'B1'}',
      pronunciationOverall: overall is num
          ? overall.toDouble()
          : double.tryParse('$overall') ?? 0,
      pronunciationNotes: '${pron['notes'] ?? ''}',
      corrections: corrections,
      ttsUrl: ttsUrl,
      avatarAction: '${avatar['action'] ?? 'none'}',
      avatarText: '${avatar['text'] ?? raw['coach_text'] ?? ''}',
      livetalkingUrl: '${avatar['livetalking_url'] ?? ''}',
      providers: providers,
    );
  }

  final String transcript;
  final String coachText;
  final String difficulty;
  final double pronunciationOverall;
  final String pronunciationNotes;
  final List<String> corrections;
  final String? ttsUrl;
  final String avatarAction;
  final String avatarText;
  final String livetalkingUrl;
  final Map<String, String> providers;

  String get scoreLabel {
    final int pct = (pronunciationOverall * 100).round().clamp(0, 100);
    return '$pct%';
  }
}
