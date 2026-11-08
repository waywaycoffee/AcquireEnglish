import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../constants/endpoints.dart';
import '../../../data/repository/network_repository.dart';

final Provider<AcquireApiClient> acquireApiClientProvider =
    Provider<AcquireApiClient>((Ref ref) {
      return AcquireApiClient(ref.watch(networkRepositoryProvider));
    });

class AcquireUser {
  const AcquireUser({
    required this.id,
    required this.email,
    this.displayName,
  });

  factory AcquireUser.fromJson(Map<String, dynamic> json) => AcquireUser(
    id: json['id'] as int,
    email: json['email'] as String,
    displayName: json['display_name'] as String?,
  );

  final int id;
  final String email;
  final String? displayName;
}

class AcquireTokenResult {
  const AcquireTokenResult({
    required this.accessToken,
    required this.user,
  });

  factory AcquireTokenResult.fromJson(Map<String, dynamic> json) =>
      AcquireTokenResult(
        accessToken: json['access_token'] as String,
        user: AcquireUser.fromJson(json['user'] as Map<String, dynamic>),
      );

  final String accessToken;
  final AcquireUser user;
}

class AcquireLessonDto {
  const AcquireLessonDto({
    required this.id,
    required this.title,
    required this.index,
    required this.videoUrl,
    required this.subtitleEn,
    this.durationSec,
    this.subtitleZh,
  });

  factory AcquireLessonDto.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> subs =
        (json['subtitles'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return AcquireLessonDto(
      id: json['id'] as String,
      title: json['title'] as String,
      index: json['index'] as int,
      durationSec: (json['durationSec'] as num?)?.toDouble(),
      videoUrl: json['videoUrl'] as String,
      subtitleEn: subs['en'] as String? ?? '',
      subtitleZh: subs['zh'] as String?,
    );
  }

  final String id;
  final String title;
  final int index;
  final double? durationSec;
  final String videoUrl;
  final String subtitleEn;
  final String? subtitleZh;
}

class AcquireCourseDto {
  const AcquireCourseDto({
    required this.id,
    required this.title,
    required this.level,
    required this.tags,
    required this.lessons,
    this.titleZh,
    this.description,
    this.coverUrl,
  });

  factory AcquireCourseDto.fromJson(Map<String, dynamic> json) =>
      AcquireCourseDto(
        id: json['id'] as String,
        title: json['title'] as String,
        titleZh: json['titleZh'] as String?,
        description: json['description'] as String?,
        coverUrl: json['coverUrl'] as String?,
        level: json['level'] as String? ?? 'unknown',
        tags: (json['tags'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList(growable: false),
        lessons: (json['lessons'] as List<dynamic>? ?? const <dynamic>[])
            .cast<Map<String, dynamic>>()
            .map(AcquireLessonDto.fromJson)
            .toList(growable: false),
      );

  final String id;
  final String title;
  final String? titleZh;
  final String? description;
  final String? coverUrl;
  final String level;
  final List<String> tags;
  final List<AcquireLessonDto> lessons;
}

class AcquireProgressDto {
  const AcquireProgressDto({
    required this.courseId,
    required this.lessonId,
    required this.positionSec,
    required this.completed,
    required this.updatedAt,
  });

  factory AcquireProgressDto.fromJson(Map<String, dynamic> json) =>
      AcquireProgressDto(
        courseId: json['course_id'] as String,
        lessonId: json['lesson_id'] as String,
        positionSec: (json['position_sec'] as num).toDouble(),
        completed: json['completed'] as bool? ?? false,
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  final String courseId;
  final String lessonId;
  final double positionSec;
  final bool completed;
  final DateTime updatedAt;
}

class AcquirePreferencesDto {
  const AcquirePreferencesDto({
    this.level = 'A2',
    this.tags = const <String>['slow', 'daily'],
    this.dailyQuota = 2,
    this.notifyDailyFeed = true,
    this.hasBilibiliCookie = false,
    this.hasAsrApiKey = false,
    this.bilibiliCookie,
    this.asrApiKey,
  });

  factory AcquirePreferencesDto.fromJson(Map<String, dynamic> json) =>
      AcquirePreferencesDto(
        level: json['level'] as String? ?? 'A2',
        tags: (json['tags'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList(growable: false),
        dailyQuota: json['daily_quota'] as int? ?? 2,
        notifyDailyFeed: json['notify_daily_feed'] as bool? ?? true,
        hasBilibiliCookie: json['has_bilibili_cookie'] as bool? ?? false,
        hasAsrApiKey: json['has_asr_api_key'] as bool? ?? false,
      );

  final String level;
  final List<String> tags;
  final int dailyQuota;
  final bool notifyDailyFeed;
  final bool hasBilibiliCookie;
  final bool hasAsrApiKey;
  final String? bilibiliCookie;
  final String? asrApiKey;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'level': level,
    'tags': tags,
    'daily_quota': dailyQuota,
    'notify_daily_feed': notifyDailyFeed,
    if (bilibiliCookie != null) 'bilibili_cookie': bilibiliCookie,
    if (asrApiKey != null) 'asr_api_key': asrApiKey,
  };

  AcquirePreferencesDto copyWith({
    String? level,
    List<String>? tags,
    int? dailyQuota,
    bool? notifyDailyFeed,
    bool? hasBilibiliCookie,
    bool? hasAsrApiKey,
    String? bilibiliCookie,
    String? asrApiKey,
  }) => AcquirePreferencesDto(
    level: level ?? this.level,
    tags: tags ?? this.tags,
    dailyQuota: dailyQuota ?? this.dailyQuota,
    notifyDailyFeed: notifyDailyFeed ?? this.notifyDailyFeed,
    hasBilibiliCookie: hasBilibiliCookie ?? this.hasBilibiliCookie,
    hasAsrApiKey: hasAsrApiKey ?? this.hasAsrApiKey,
    bilibiliCookie: bilibiliCookie ?? this.bilibiliCookie,
    asrApiKey: asrApiKey ?? this.asrApiKey,
  );
}

class AcquireVocabDto {
  const AcquireVocabDto({
    required this.id,
    required this.word,
    required this.mastery,
    required this.createdAt,
    this.context,
    this.courseId,
    this.lessonId,
    this.ease = 2.5,
    this.intervalDays = 0,
    this.repetitions = 0,
    this.dueAt,
  });

  factory AcquireVocabDto.fromJson(Map<String, dynamic> json) => AcquireVocabDto(
    id: json['id'] as int,
    word: json['word'] as String,
    context: json['context'] as String?,
    courseId: json['course_id'] as String?,
    lessonId: json['lesson_id'] as String?,
    mastery: json['mastery'] as String? ?? 'new',
    ease: (json['ease'] as num?)?.toDouble() ?? 2.5,
    intervalDays: json['interval_days'] as int? ?? 0,
    repetitions: json['repetitions'] as int? ?? 0,
    dueAt: json['due_at'] == null
        ? null
        : DateTime.tryParse(json['due_at'] as String),
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final int id;
  final String word;
  final String? context;
  final String? courseId;
  final String? lessonId;
  final String mastery;
  final double ease;
  final int intervalDays;
  final int repetitions;
  final DateTime? dueAt;
  final DateTime createdAt;
}

class AcquireApiClient {
  AcquireApiClient(this._dio);

  final Dio _dio;

  bool get hasAuthorization {
    final Object? value = _dio.options.headers['Authorization'];
    return value is String && value.startsWith('Bearer ') && value.length > 20;
  }

  Future<AcquireTokenResult> login({
    required String email,
    required String password,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.login,
      data: <String, String>{'email': email, 'password': password},
    );
    return AcquireTokenResult.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AcquireTokenResult> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.register,
      data: <String, dynamic>{
        'email': email,
        'password': password,
        if (displayName != null) 'display_name': displayName,
      },
    );
    return AcquireTokenResult.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<AcquireCourseDto>> courses() async {
    final Response<dynamic> response = await _dio.get(Endpoints.courses);
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(AcquireCourseDto.fromJson)
        .toList(growable: false);
  }

  Future<AcquireCourseDto> importLink(String url) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.importLink,
      data: <String, String>{'url': url},
    );
    return AcquireCourseDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AcquireCourseDto> generateSubtitles({
    required int importId,
    String language = 'en',
    int? maxSeconds,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.generateSubtitles(importId),
      data: <String, dynamic>{
        'language': language,
        if (maxSeconds != null) 'max_seconds': maxSeconds,
      },
      options: Options(
        sendTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 45),
      ),
    );
    return AcquireCourseDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<String> fetchText(String pathOrUrl) async {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      final Response<String> response = await _dio.get<String>(
        pathOrUrl,
        options: Options(responseType: ResponseType.plain),
      );
      return response.data ?? '';
    }
    final String path = pathOrUrl.startsWith('/')
        ? pathOrUrl.substring(1)
        : pathOrUrl;
    final Response<String> response = await _dio.get<String>(
      path,
      options: Options(responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }

  Future<void> ensureAsrApiKey(String apiKey) async {
    final AcquirePreferencesDto current = await getPreferences();
    if (current.hasAsrApiKey) {
      return;
    }
    await putPreferences(current.copyWith(asrApiKey: apiKey));
  }

  Future<List<AcquireProgressDto>> listProgress() async {
    final Response<dynamic> response = await _dio.get(Endpoints.progress);
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(AcquireProgressDto.fromJson)
        .toList(growable: false);
  }

  Future<AcquireProgressDto> upsertProgress({
    required String courseId,
    required String lessonId,
    required double positionSec,
    bool completed = false,
  }) async {
    final Response<dynamic> response = await _dio.put(
      Endpoints.progress,
      data: <String, dynamic>{
        'course_id': courseId,
        'lesson_id': lessonId,
        'position_sec': positionSec,
        'completed': completed,
      },
    );
    return AcquireProgressDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AcquirePreferencesDto> getPreferences() async {
    final Response<dynamic> response = await _dio.get(Endpoints.preferences);
    return AcquirePreferencesDto.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<AcquirePreferencesDto> putPreferences(
    AcquirePreferencesDto prefs,
  ) async {
    final Response<dynamic> response = await _dio.put(
      Endpoints.preferences,
      data: prefs.toJson(),
    );
    return AcquirePreferencesDto.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<List<AcquireCourseDto>> dailyFeed({String? date}) async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.dailyFeed,
      queryParameters: <String, dynamic>{
        if (date != null) 'date': date,
      },
    );
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(AcquireCourseDto.fromJson)
        .toList(growable: false);
  }

  Future<List<AcquireVocabDto>> listVocab() async {
    final Response<dynamic> response = await _dio.get(Endpoints.vocab);
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(AcquireVocabDto.fromJson)
        .toList(growable: false);
  }

  Future<AcquireVocabDto> upsertVocab({
    required String word,
    String? context,
    String? courseId,
    String? lessonId,
    String mastery = 'new',
    double ease = 2.5,
    int intervalDays = 0,
    int repetitions = 0,
    DateTime? dueAt,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.vocab,
      data: <String, dynamic>{
        'word': word,
        'context': context,
        'course_id': courseId,
        'lesson_id': lessonId,
        'mastery': mastery,
        'ease': ease,
        'interval_days': intervalDays,
        'repetitions': repetitions,
        'due_at': dueAt?.toUtc().toIso8601String(),
      },
    );
    return AcquireVocabDto.fromJson(response.data as Map<String, dynamic>);
  }
}
