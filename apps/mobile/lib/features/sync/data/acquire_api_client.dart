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
    this.phone,
    this.wechatBound = false,
    this.pointsBalance = 0,
  });

  factory AcquireUser.fromJson(Map<String, dynamic> json) => AcquireUser(
    id: json['id'] as int,
    email: json['email'] as String,
    displayName: json['display_name'] as String?,
    phone: json['phone'] as String?,
    wechatBound: json['wechat_bound'] == true,
    pointsBalance: (json['points_balance'] as num?)?.toInt() ?? 0,
  );

  final int id;
  final String email;
  final String? displayName;
  final String? phone;
  final bool wechatBound;
  final int pointsBalance;
}

class AcquireShareRewardResult {
  const AcquireShareRewardResult({
    required this.awarded,
    required this.delta,
    required this.balance,
    required this.reason,
  });

  factory AcquireShareRewardResult.fromJson(Map<String, dynamic> json) =>
      AcquireShareRewardResult(
        awarded: json['awarded'] == true,
        delta: (json['delta'] as num?)?.toInt() ?? 0,
        balance: (json['balance'] as num?)?.toInt() ?? 0,
        reason: '${json['reason'] ?? ''}',
      );

  final bool awarded;
  final int delta;
  final int balance;
  final String reason;
}

class AcquireTokenResult {
  const AcquireTokenResult({
    required this.accessToken,
    required this.user,
    this.isNewUser = false,
  });

  factory AcquireTokenResult.fromJson(Map<String, dynamic> json) =>
      AcquireTokenResult(
        accessToken: json['access_token'] as String,
        user: AcquireUser.fromJson(json['user'] as Map<String, dynamic>),
        isNewUser: json['is_new_user'] == true,
      );

  final String accessToken;
  final AcquireUser user;
  final bool isNewUser;
}

class AcquireLiveKitToken {
  const AcquireLiveKitToken({
    required this.url,
    required this.token,
    required this.room,
    required this.identity,
    this.expiresIn = 3600,
  });

  factory AcquireLiveKitToken.fromJson(Map<String, dynamic> json) =>
      AcquireLiveKitToken(
        url: '${json['url'] ?? ''}',
        token: '${json['token'] ?? ''}',
        room: '${json['room'] ?? ''}',
        identity: '${json['identity'] ?? ''}',
        expiresIn: (json['expires_in'] as num?)?.toInt() ?? 3600,
      );

  final String url;
  final String token;
  final String room;
  final String identity;
  final int expiresIn;
}

class PersonalImportAsset {
  const PersonalImportAsset({
    required this.id,
    required this.source,
    required this.externalId,
    required this.title,
    required this.watchUrl,
    required this.durationSec,
    required this.hasEn,
    required this.hasZh,
    required this.courseId,
    this.hasCover = false,
    this.author,
    this.coverUrl,
    this.coverImageUrl,
    this.subtitleEnUrl,
    this.subtitleZhUrl,
  });

  factory PersonalImportAsset.fromJson(Map<String, dynamic> json) =>
      PersonalImportAsset(
        id: (json['id'] as num?)?.toInt() ?? 0,
        source: '${json['source'] ?? ''}',
        externalId: '${json['external_id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        author: json['author'] as String?,
        watchUrl: '${json['watch_url'] ?? ''}',
        durationSec: (json['duration_sec'] as num?)?.toInt() ?? 60,
        hasEn: json['has_en'] == true,
        hasZh: json['has_zh'] == true,
        hasCover: json['has_cover'] == true,
        courseId: '${json['course_id'] ?? 'link-${json['id']}'}',
        coverUrl: (json['cover_url'] as String?)?.trim(),
        coverImageUrl: (json['cover_image_url'] as String?)?.trim(),
        subtitleEnUrl: json['subtitle_en_url'] as String?,
        subtitleZhUrl: json['subtitle_zh_url'] as String?,
      );

  final int id;
  final String source;
  final String externalId;
  final String title;
  final String? author;
  final String watchUrl;
  final int durationSec;
  final bool hasEn;
  final bool hasZh;
  final bool hasCover;
  final String courseId;
  final String? coverUrl;
  final String? coverImageUrl;
  final String? subtitleEnUrl;
  final String? subtitleZhUrl;
}

class SharedBilibiliSubtitlePack {
  const SharedBilibiliSubtitlePack({
    required this.bvid,
    required this.page,
    required this.subtitleEnSrt,
    this.cid,
    this.durationSec,
    this.subtitleZhSrt,
    this.qualityScore = 0,
    this.cueCount = 0,
    this.enHits = 0,
    this.zhHits = 0,
    this.sourceOrigin = 'asr',
  });

  factory SharedBilibiliSubtitlePack.fromJson(Map<String, dynamic> json) =>
      SharedBilibiliSubtitlePack(
        bvid: '${json['bvid'] ?? ''}',
        page: (json['page'] as num?)?.toInt() ?? 1,
        cid: (json['cid'] as num?)?.toInt(),
        durationSec: (json['duration_sec'] as num?)?.toInt(),
        subtitleEnSrt: '${json['subtitle_en_srt'] ?? ''}',
        subtitleZhSrt: json['subtitle_zh_srt'] as String?,
        qualityScore: (json['quality_score'] as num?)?.toDouble() ?? 0,
        cueCount: (json['cue_count'] as num?)?.toInt() ?? 0,
        enHits: (json['en_hits'] as num?)?.toInt() ?? 0,
        zhHits: (json['zh_hits'] as num?)?.toInt() ?? 0,
        sourceOrigin: '${json['source_origin'] ?? 'asr'}',
      );

  final String bvid;
  final int page;
  final int? cid;
  final int? durationSec;
  final String subtitleEnSrt;
  final String? subtitleZhSrt;
  final double qualityScore;
  final int cueCount;
  final int enHits;
  final int zhHits;
  final String sourceOrigin;
}

class SharedBilibiliSubtitleUpsertResult {
  const SharedBilibiliSubtitleUpsertResult({
    required this.stored,
    this.replaced = false,
    this.qualityScore = 0,
    this.cueCount = 0,
    this.reason = '',
  });

  factory SharedBilibiliSubtitleUpsertResult.fromJson(
    Map<String, dynamic> json,
  ) => SharedBilibiliSubtitleUpsertResult(
    stored: json['stored'] == true,
    replaced: json['replaced'] == true,
    qualityScore: (json['quality_score'] as num?)?.toDouble() ?? 0,
    cueCount: (json['cue_count'] as num?)?.toInt() ?? 0,
    reason: '${json['reason'] ?? ''}',
  );

  final bool stored;
  final bool replaced;
  final double qualityScore;
  final int cueCount;
  final String reason;
}

class AcquireSmsSendResult {
  const AcquireSmsSendResult({
    required this.expiresIn,
    required this.mock,
    this.debugCode,
  });

  factory AcquireSmsSendResult.fromJson(Map<String, dynamic> json) =>
      AcquireSmsSendResult(
        expiresIn: (json['expires_in'] as num?)?.toInt() ?? 300,
        mock: json['mock'] == true,
        debugCode: json['debug_code'] as String?,
      );

  final int expiresIn;
  final bool mock;
  final String? debugCode;
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

/// Interest-based Bilibili recommendation (not a library course pack).
class AcquireDailyFeedItemDto {
  const AcquireDailyFeedItemDto({
    required this.id,
    required this.bvid,
    required this.title,
    required this.watchUrl,
    this.author = '',
    this.coverUrl,
    this.durationSec,
    this.description,
    this.tags = const <String>[],
    this.source = 'bilibili',
  });

  factory AcquireDailyFeedItemDto.fromJson(Map<String, dynamic> json) =>
      AcquireDailyFeedItemDto(
        id: json['id'] as String? ?? '',
        bvid: json['bvid'] as String? ?? '',
        title: json['title'] as String? ?? '',
        author: json['author'] as String? ?? '',
        coverUrl: json['coverUrl'] as String?,
        durationSec: (json['durationSec'] as num?)?.toDouble(),
        watchUrl: json['watchUrl'] as String? ?? '',
        description: json['description'] as String?,
        tags: (json['tags'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList(growable: false),
        source: json['source'] as String? ?? 'bilibili',
      );

  final String id;
  final String bvid;
  final String title;
  final String author;
  final String? coverUrl;
  final double? durationSec;
  final String watchUrl;
  final String? description;
  final List<String> tags;
  final String source;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'bvid': bvid,
        'title': title,
        'author': author,
        'coverUrl': coverUrl,
        'durationSec': durationSec,
        'watchUrl': watchUrl,
        'description': description,
        'tags': tags,
        'source': source,
      };
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
        dailyQuota: (json['daily_quota'] as num?)?.toInt() ?? 2,
        notifyDailyFeed: json['notify_daily_feed'] as bool? ?? true,
        hasBilibiliCookie: json['has_bilibili_cookie'] == true,
        hasAsrApiKey: json['has_asr_api_key'] == true,
      );

  final String level;
  final List<String> tags;
  final int dailyQuota;
  final bool notifyDailyFeed;
  final bool hasBilibiliCookie;
  final bool hasAsrApiKey;
  /// Write-only: sent on PUT when non-null.
  final String? bilibiliCookie;
  final String? asrApiKey;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'level': level,
    'tags': tags,
    'daily_quota': dailyQuota,
    'notify_daily_feed': notifyDailyFeed,
    'has_bilibili_cookie': hasBilibiliCookie,
    'has_asr_api_key': hasAsrApiKey,
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

class AcquirePhraseDto {
  const AcquirePhraseDto({
    required this.clientId,
    required this.english,
    required this.chinese,
    required this.course,
    required this.episode,
    required this.time,
    this.id,
    this.courseId,
    this.episodeId,
    this.startTime,
    this.endTime,
    this.note,
    this.rating = 1,
    this.needsReview = true,
    this.reviewCount = 0,
    this.lapseCount = 0,
    this.collectedAt,
    this.lastReviewedAt,
    this.nextReviewAt,
  });

  factory AcquirePhraseDto.fromJson(Map<String, dynamic> json) =>
      AcquirePhraseDto(
        id: json['id'] as int?,
        clientId: '${json['client_id'] ?? ''}',
        english: '${json['english'] ?? ''}',
        chinese: '${json['chinese'] ?? ''}',
        course: '${json['course'] ?? ''}',
        episode: '${json['episode'] ?? ''}',
        time: '${json['time'] ?? ''}',
        courseId: json['course_id'] as String?,
        episodeId: json['episode_id'] as String?,
        startTime: json['start_time'] as String?,
        endTime: json['end_time'] as String?,
        note: json['note'] as String?,
        rating: (json['rating'] as num?)?.toInt() ?? 1,
        needsReview: json['needs_review'] == true || json['needs_review'] == 1,
        reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
        lapseCount: (json['lapse_count'] as num?)?.toInt() ?? 0,
        collectedAt: json['collected_at'] == null
            ? null
            : DateTime.tryParse('${json['collected_at']}'),
        lastReviewedAt: json['last_reviewed_at'] == null
            ? null
            : DateTime.tryParse('${json['last_reviewed_at']}'),
        nextReviewAt: json['next_review_at'] == null
            ? null
            : DateTime.tryParse('${json['next_review_at']}'),
      );

  final int? id;
  final String clientId;
  final String english;
  final String chinese;
  final String course;
  final String episode;
  final String time;
  final String? courseId;
  final String? episodeId;
  final String? startTime;
  final String? endTime;
  final String? note;
  final int rating;
  final bool needsReview;
  final int reviewCount;
  final int lapseCount;
  final DateTime? collectedAt;
  final DateTime? lastReviewedAt;
  final DateTime? nextReviewAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'client_id': clientId,
    'english': english,
    'chinese': chinese,
    'course': course,
    'episode': episode,
    'time': time,
    'course_id': courseId,
    'episode_id': episodeId,
    'start_time': startTime,
    'end_time': endTime,
    'note': note,
    'rating': rating,
    'needs_review': needsReview,
    'review_count': reviewCount,
    'lapse_count': lapseCount,
    'collected_at': collectedAt?.toUtc().toIso8601String(),
    'last_reviewed_at': lastReviewedAt?.toUtc().toIso8601String(),
    'next_review_at': nextReviewAt?.toUtc().toIso8601String(),
  };
}

class AcquireApiClient {
  AcquireApiClient(this._dio);

  final Dio _dio;

  Future<({int revision, Map<String, dynamic>? state})> reviewBackup(
    String token, {
    int? revision,
    Map<String, dynamic>? state,
  }) async {
    final Options options = Options(
      headers: <String, String>{'Authorization': 'Bearer $token'},
    );
    final Response<Map<String, dynamic>> response = revision == null
        ? await _dio.get<Map<String, dynamic>>(
            Endpoints.reviewBackup,
            options: options,
          )
        : await _dio.put<Map<String, dynamic>>(
            Endpoints.reviewBackup,
            data: <String, dynamic>{'revision': revision, 'state': state},
            options: options,
          );
    final Map<String, dynamic> body = response.data!;
    return (
      revision: body['revision'] as int,
      state: body['state'] as Map<String, dynamic>?,
    );
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
    required String code,
    String? displayName,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.register,
      data: <String, dynamic>{
        'email': email,
        'password': password,
        'code': code,
        if (displayName != null) 'display_name': displayName,
      },
    );
    return AcquireTokenResult.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AcquireSmsSendResult> sendEmailCode({required String email}) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.emailSend,
      data: <String, String>{'email': email},
    );
    return AcquireSmsSendResult.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<AcquireSmsSendResult> sendSmsCode({required String phone}) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.smsSend,
      data: <String, String>{'phone': phone},
    );
    return AcquireSmsSendResult.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<AcquireTokenResult> loginWithSms({
    required String phone,
    required String code,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.smsLogin,
      data: <String, String>{'phone': phone, 'code': code},
    );
    return AcquireTokenResult.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AcquireTokenResult> loginWithWechat({
    required String code,
    String? nickname,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.wechatLogin,
      data: <String, dynamic>{
        'code': code,
        if (nickname != null && nickname.trim().isNotEmpty)
          'nickname': nickname.trim(),
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
    DateTime? clientUpdatedAt,
  }) async {
    final Response<dynamic> response = await _dio.put(
      Endpoints.progress,
      data: <String, dynamic>{
        'course_id': courseId,
        'lesson_id': lessonId,
        'position_sec': positionSec,
        'completed': completed,
        if (clientUpdatedAt != null)
          'client_updated_at': clientUpdatedAt.toUtc().toIso8601String(),
      },
    );
    return AcquireProgressDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AcquirePreferencesDto> getPreferences() async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.preferences,
      options: Options(
        extra: const <String, Object>{'dio_cache_interceptor_force_refresh': true},
      ),
    );
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
      options: Options(
        extra: const <String, Object>{'dio_cache_interceptor_force_refresh': true},
      ),
    );
    return AcquirePreferencesDto.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<List<AcquireDailyFeedItemDto>> dailyFeed({String? date}) async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.dailyFeed,
      queryParameters: <String, dynamic>{
        if (date != null) 'date': date,
      },
    );
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(AcquireDailyFeedItemDto.fromJson)
        .where(
          (AcquireDailyFeedItemDto item) =>
              item.bvid.isNotEmpty && item.watchUrl.isNotEmpty,
        )
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

  Future<String> startLearningSession({
    String taskId = 'video_line',
    String courseTitle = '',
    String currentEnglish = '',
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.learningSessions,
      data: <String, dynamic>{
        'task_id': taskId,
        'course_title': courseTitle,
        'current_english': currentEnglish,
      },
    );
    return (response.data as Map<String, dynamic>)['id'] as String;
  }

  Future<void> appendLearningTurn({
    required String sessionId,
    required String role,
    required String text,
    String? machineTranscript,
    bool confirmed = true,
    Map<String, dynamic>? scores,
  }) async {
    await _dio.post<dynamic>(
      '${Endpoints.learningSessions}/$sessionId/turns',
      data: <String, dynamic>{
        'role': role,
        'text': text,
        if (machineTranscript != null) 'machine_transcript': machineTranscript,
        'confirmed': confirmed,
        'scores': scores ?? <String, dynamic>{},
      },
    );
  }

  Future<List<Map<String, dynamic>>> finalizeLearningFeedback({
    required String sessionId,
    required List<Map<String, dynamic>> items,
  }) async {
    final Response<dynamic> response = await _dio.post(
      '${Endpoints.learningSessions}/$sessionId/feedback',
      data: <String, dynamic>{'items': items},
    );
    final Object? raw = (response.data as Map<String, dynamic>)['items'];
    if (raw is! List<dynamic>) {
      return const <Map<String, dynamic>>[];
    }
    return raw.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listWrongItems() async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.learningWrongItems,
    );
    return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<void> saveReviewExpression({
    required String expression,
    required String sourceQuote,
  }) async {
    await _dio.post<dynamic>(
      Endpoints.learningReviews,
      data: <String, String>{
        'expression': expression,
        'source_quote': sourceQuote,
      },
    );
  }

  Future<List<Map<String, dynamic>>> listDueLearningReviews() async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.learningReviewsDue,
    );
    return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<void> completeLearningReview({
    required String reviewId,
    required bool independentOk,
  }) async {
    await _dio.post<dynamic>(
      '${Endpoints.learningReviews}/$reviewId/complete',
      data: <String, dynamic>{'independent_ok': independentOk},
    );
  }

  Future<Map<String, dynamic>> getAssets() async {
    final Response<dynamic> response = await _dio.get(Endpoints.assets);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> consumeEntitlement({
    required String assetKind,
    String assetRef = '',
    int quantity = 1,
    String reason = 'consume',
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.assetsConsume,
      data: <String, dynamic>{
        'asset_kind': assetKind,
        'asset_ref': assetRef,
        'quantity': quantity,
        'reason': reason,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<List<AcquirePhraseDto>> listPhrases() async {
    final Response<dynamic> response = await _dio.get(Endpoints.phrases);
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(AcquirePhraseDto.fromJson)
        .toList(growable: false);
  }

  Future<AcquirePhraseDto> upsertPhrase(AcquirePhraseDto phrase) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.phrases,
      data: phrase.toJson(),
    );
    return AcquirePhraseDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> netdiskStatus() async {
    final Response<dynamic> response = await _dio.get(Endpoints.netdiskStatus);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> bindNetdisk({
    required String provider,
    required String credential,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.netdiskBind,
      data: <String, String>{
        'provider': provider,
        'credential': credential,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> unbindNetdisk(String provider) async {
    await _dio.delete<dynamic>('api/netdisk/bind/$provider');
  }

  Future<Map<String, dynamic>> listNetdisk({
    required String provider,
    String path = '',
  }) async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.netdiskList,
      queryParameters: <String, dynamic>{
        'provider': provider,
        if (path.trim().isNotEmpty) 'path': path.trim(),
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> importNetdiskVideos({
    required String provider,
    required List<String> paths,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.netdiskImport,
      data: <String, dynamic>{
        'provider': provider,
        'paths': paths,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<bool> liveKitConfigured() async {
    try {
      final Response<dynamic> response = await _dio.get(Endpoints.livekitStatus);
      final Object? configured =
          (response.data as Map<String, dynamic>)['configured'];
      return configured == true || configured == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<AcquireLiveKitToken> createLiveKitToken({String? room}) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.livekitToken,
      data: <String, dynamic>{
        if (room != null && room.trim().isNotEmpty) 'room': room.trim(),
      },
    );
    return AcquireLiveKitToken.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// Returns null on 404 / network miss (shared cache optional).
  Future<SharedBilibiliSubtitlePack?> getSharedBilibiliSubtitle({
    required String bvid,
    int page = 1,
    int? cid,
  }) async {
    try {
      final Response<dynamic> response = await _dio.get(
        Endpoints.sharedSubtitlesBilibili,
        queryParameters: <String, dynamic>{
          'bvid': bvid,
          'page': page,
          if (cid != null) 'cid': cid,
        },
        options: Options(
          validateStatus: (int? status) =>
              status != null &&
              ((status >= 200 && status < 300) || status == 404),
          extra: const <String, Object>{
            'dio_cache_interceptor_force_refresh': true,
          },
        ),
      );
      if (response.statusCode == 404 || response.data == null) {
        return null;
      }
      return SharedBilibiliSubtitlePack.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<List<PersonalImportAsset>> listPersonalImports() async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.imports,
      options: Options(
        extra: const <String, Object>{
          'dio_cache_interceptor_force_refresh': true,
        },
      ),
    );
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(PersonalImportAsset.fromJson)
        .toList(growable: false);
  }

  Future<PersonalImportAsset> upsertPersonalImport({
    required String source,
    required String externalId,
    required String title,
    required String watchUrl,
    String? author,
    int durationSec = 60,
    String? subtitleEnSrt,
    String? subtitleZhSrt,
    String? coverUrl,
    String? coverImageBase64,
  }) async {
    final Response<dynamic> response = await _dio.put(
      Endpoints.importsAsset,
      data: <String, dynamic>{
        'source': source,
        'external_id': externalId,
        'title': title,
        'watch_url': watchUrl,
        if (author != null && author.trim().isNotEmpty) 'author': author.trim(),
        'duration_sec': durationSec,
        if (subtitleEnSrt != null) 'subtitle_en_srt': subtitleEnSrt,
        if (subtitleZhSrt != null) 'subtitle_zh_srt': subtitleZhSrt,
        if (coverUrl != null && coverUrl.trim().isNotEmpty)
          'cover_url': coverUrl.trim(),
        if (coverImageBase64 != null && coverImageBase64.trim().isNotEmpty)
          'cover_image_base64': coverImageBase64.trim(),
      },
      options: Options(
        extra: const <String, Object>{
          'dio_cache_interceptor_force_refresh': true,
        },
      ),
    );
    return PersonalImportAsset.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<List<int>?> fetchPersonalImportCover({required int importId}) async {
    try {
      final Response<List<int>> response = await _dio.get<List<int>>(
        '${Endpoints.imports}/$importId/cover',
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (int? status) =>
              status != null &&
              ((status >= 200 && status < 300) || status == 404),
          extra: const <String, Object>{
            'dio_cache_interceptor_force_refresh': true,
          },
        ),
      );
      if (response.statusCode == 404) {
        return null;
      }
      final List<int>? data = response.data;
      if (data == null || data.length < 256) {
        return null;
      }
      return data;
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<String?> fetchPersonalImportSrt({
    required int importId,
    required String lang,
  }) async {
    try {
      final Response<dynamic> response = await _dio.get(
        '${Endpoints.imports}/$importId/srt/$lang',
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (int? status) =>
              status != null &&
              ((status >= 200 && status < 300) || status == 404),
          extra: const <String, Object>{
            'dio_cache_interceptor_force_refresh': true,
          },
        ),
      );
      if (response.statusCode == 404) {
        return null;
      }
      final Object? data = response.data;
      if (data is String && data.trim().isNotEmpty) {
        return data;
      }
      return data?.toString();
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<SharedBilibiliSubtitleUpsertResult> putSharedBilibiliSubtitle({
    required String bvid,
    int page = 1,
    int? cid,
    int? durationSec,
    required String subtitleEnSrt,
    String? subtitleZhSrt,
    String sourceOrigin = 'asr',
  }) async {
    final Response<dynamic> response = await _dio.put(
      Endpoints.sharedSubtitlesBilibili,
      data: <String, dynamic>{
        'bvid': bvid,
        'page': page,
        if (cid != null) 'cid': cid,
        if (durationSec != null) 'duration_sec': durationSec,
        'subtitle_en_srt': subtitleEnSrt,
        if (subtitleZhSrt != null) 'subtitle_zh_srt': subtitleZhSrt,
        'source_origin': sourceOrigin,
      },
      options: Options(
        extra: const <String, Object>{
          'dio_cache_interceptor_force_refresh': true,
        },
      ),
    );
    return SharedBilibiliSubtitleUpsertResult.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<int> fetchPointsBalance() async {
    final Response<dynamic> response = await _dio.get(Endpoints.rewardsPoints);
    final Object? data = response.data;
    if (data is Map<String, dynamic>) {
      return (data['balance'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  Future<AcquireShareRewardResult> claimShareReward({
    required String episodeId,
    required String clientShareId,
    String assetKind = 'dub_video',
    String channel = 'wechat_moments',
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.rewardsShare,
      data: <String, dynamic>{
        'episode_id': episodeId,
        'asset_kind': assetKind,
        'channel': channel,
        'client_share_id': clientShareId,
      },
      options: Options(
        extra: const <String, Object>{
          'dio_cache_interceptor_force_refresh': true,
        },
      ),
    );
    return AcquireShareRewardResult.fromJson(
      response.data as Map<String, dynamic>,
    );
  }
}
