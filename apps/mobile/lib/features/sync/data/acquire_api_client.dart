import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../constants/endpoints.dart';
import '../../../data/repository/network_repository.dart';
import '../../avatar/data/avatar_models.dart';
import '../../community/data/community_models.dart';
import '../../digital_human/domain/learning_scenario.dart';
import '../../digital_human/domain/scene_word_label.dart';
import '../../words/domain/foundation_media.dart';
import '../../words/domain/server_syllabus_catalog.dart';
import '../../words/domain/syllabus_book.dart';
import '../../exam/domain/exam_pack.dart';
import '../../writing/domain/writing_models.dart';

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

class OralMatchContent {
  const OralMatchContent({
    this.topic = '',
    this.kind = '',
    this.id = '',
    this.title = '',
    this.route = '',
  });

  factory OralMatchContent.fromJson(Map<String, dynamic> json) =>
      OralMatchContent(
        topic: '${json['topic'] ?? ''}'.trim(),
        kind: '${json['content_kind'] ?? json['kind'] ?? ''}'.trim(),
        id: '${json['content_id'] ?? json['id'] ?? ''}'.trim(),
        title: '${json['content_title'] ?? json['title'] ?? ''}'.trim(),
        route: '${json['content_route'] ?? json['route'] ?? ''}'.trim(),
      );

  final String topic;
  final String kind; // video | article | ''
  final String id;
  final String title;
  final String route;

  bool get hasMaterial => id.isNotEmpty || title.isNotEmpty;
  bool get hasTopic => topic.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (topic.isNotEmpty) 'topic': topic,
        if (kind.isNotEmpty) 'content_kind': kind,
        if (id.isNotEmpty) 'content_id': id,
        if (title.isNotEmpty) 'content_title': title,
        if (route.isNotEmpty) 'content_route': route,
      };
}

class OralMatchStatus {
  const OralMatchStatus({
    required this.status,
    this.roomId,
    this.inviteId,
    this.peerUserId,
    this.peerDisplayName,
    this.hostUserId,
    this.hostDisplayName,
    this.queuePosition,
    this.livekit,
    this.peerOnline,
    this.voiceReady,
    this.content = const OralMatchContent(),
  });

  factory OralMatchStatus.fromJson(Map<String, dynamic> json) {
    final Object? peer = json['peer'];
    final Map<String, dynamic>? peerMap = peer is Map
        ? Map<String, dynamic>.from(peer)
        : null;
    final Object? host = json['host'];
    final Map<String, dynamic>? hostMap = host is Map
        ? Map<String, dynamic>.from(host)
        : null;
    final Object? livekit = json['livekit'];
    return OralMatchStatus(
      status: '${json['status'] ?? 'idle'}',
      roomId: '${json['room_id'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['room_id']}'.trim(),
      inviteId: '${json['invite_id'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['invite_id']}'.trim(),
      peerUserId: peerMap == null
          ? null
          : int.tryParse('${peerMap['user_id'] ?? ''}'),
      peerDisplayName: peerMap == null
          ? null
          : '${peerMap['display_name'] ?? ''}'.trim(),
      hostUserId: hostMap == null
          ? null
          : int.tryParse('${hostMap['user_id'] ?? ''}'),
      hostDisplayName: hostMap == null
          ? null
          : '${hostMap['display_name'] ?? ''}'.trim(),
      queuePosition: (json['queue_position'] as num?)?.toInt(),
      livekit: livekit is Map
          ? AcquireLiveKitToken.fromJson(Map<String, dynamic>.from(livekit))
          : null,
      peerOnline: json['peer_online'] == true,
      voiceReady: json['voice_ready'] == true,
      content: OralMatchContent.fromJson(json),
    );
  }

  final String status; // idle | waiting | waiting_invite | matched | peer_left
  final String? roomId;
  final String? inviteId;
  final int? peerUserId;
  final String? peerDisplayName;
  final int? hostUserId;
  final String? hostDisplayName;
  final int? queuePosition;
  final AcquireLiveKitToken? livekit;
  final bool? peerOnline;
  final bool? voiceReady;
  final OralMatchContent content;

  bool get isMatched => status == 'matched' && (roomId ?? '').isNotEmpty;
  bool get isWaitingInvite =>
      status == 'waiting_invite' && (inviteId ?? '').isNotEmpty;
  bool get peerLeft => status == 'peer_left';
}

class OralMatchMessage {
  const OralMatchMessage({
    required this.id,
    required this.senderUserId,
    required this.senderName,
    required this.text,
    required this.createdAt,
    required this.mine,
    this.kind = 'user',
  });

  factory OralMatchMessage.fromJson(Map<String, dynamic> json) =>
      OralMatchMessage(
        id: '${json['id'] ?? ''}',
        senderUserId: int.tryParse('${json['sender_user_id'] ?? ''}') ?? 0,
        senderName: '${json['sender_name'] ?? ''}',
        text: '${json['text'] ?? ''}',
        createdAt: (json['created_at'] as num?)?.toDouble() ?? 0,
        mine: json['mine'] == true,
        kind: '${json['kind'] ?? 'user'}',
      );

  final String id;
  final int senderUserId;
  final String senderName;
  final String text;
  final double createdAt;
  final bool mine;
  final String kind;
}

class OralMatchInbox {
  const OralMatchInbox({
    required this.messages,
    this.roomClosed = false,
    this.peerOnline = true,
  });

  final List<OralMatchMessage> messages;
  final bool roomClosed;
  final bool peerOnline;
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

/// Durable ECS GPU subtitle job (`POST /api/shared-subtitles/jobs`).
class SharedSubtitleGpuJob {
  const SharedSubtitleGpuJob({
    required this.id,
    required this.bvid,
    required this.page,
    required this.state,
    this.attempts = 0,
    this.error = '',
  });

  factory SharedSubtitleGpuJob.fromJson(Map<String, dynamic> json) =>
      SharedSubtitleGpuJob(
        id: '${json['id'] ?? ''}',
        bvid: '${json['bvid'] ?? ''}',
        page: (json['page'] as num?)?.toInt() ?? 1,
        state: '${json['state'] ?? ''}',
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        error: '${json['error'] ?? ''}',
      );

  final String id;
  final String bvid;
  final int page;
  final String state;
  final int attempts;
  final String error;

  bool get isTerminalFailure =>
      state == 'failed' || (error.trim().isNotEmpty && state == 'failed');
}

class SharedBilibiliSubtitlePack {
  const SharedBilibiliSubtitlePack({
    required this.bvid,
    required this.page,
    required this.subtitleEnSrt,
    this.cid,
    this.durationSec,
    this.title = '',
    this.previewZh = '',
    this.subtitleZhSrt,
    this.qualityScore = 0,
    this.cueCount = 0,
    this.enHits = 0,
    this.zhHits = 0,
    this.sourceOrigin = 'asr',
    this.hasEn = true,
    this.hasZh = false,
  });

  factory SharedBilibiliSubtitlePack.fromJson(Map<String, dynamic> json) =>
      SharedBilibiliSubtitlePack(
        bvid: '${json['bvid'] ?? ''}',
        page: (json['page'] as num?)?.toInt() ?? 1,
        cid: (json['cid'] as num?)?.toInt(),
        durationSec: (json['duration_sec'] as num?)?.toInt(),
        title: '${json['title'] ?? ''}',
        previewZh: '${json['preview_zh'] ?? ''}',
        subtitleEnSrt: '${json['subtitle_en_srt'] ?? ''}',
        subtitleZhSrt: json['subtitle_zh_srt'] as String?,
        qualityScore: (json['quality_score'] as num?)?.toDouble() ?? 0,
        cueCount: (json['cue_count'] as num?)?.toInt() ?? 0,
        enHits: (json['en_hits'] as num?)?.toInt() ?? 0,
        zhHits: (json['zh_hits'] as num?)?.toInt() ?? 0,
        sourceOrigin: '${json['source_origin'] ?? 'asr'}',
        hasEn: json['has_en'] != false,
        hasZh: json['has_zh'] == true ||
            ((json['subtitle_zh_srt'] as String?)?.trim().isNotEmpty ?? false),
      );

  final String bvid;
  final int page;
  final int? cid;
  final int? durationSec;
  final String title;
  final String previewZh;
  final String subtitleEnSrt;
  final String? subtitleZhSrt;
  final double qualityScore;
  final int cueCount;
  final int enHits;
  final int zhHits;
  final String sourceOrigin;
  final bool hasEn;
  final bool hasZh;
}

class SharedBilibiliSubtitleListItem {
  const SharedBilibiliSubtitleListItem({
    required this.id,
    required this.bvid,
    required this.page,
    required this.title,
    required this.previewZh,
    this.durationSec,
    this.cueCount = 0,
    this.qualityScore = 0,
    this.hasEn = true,
    this.hasZh = false,
    this.sourceOrigin = 'asr',
  });

  factory SharedBilibiliSubtitleListItem.fromJson(Map<String, dynamic> json) =>
      SharedBilibiliSubtitleListItem(
        id: (json['id'] as num?)?.toInt() ?? 0,
        bvid: '${json['bvid'] ?? ''}',
        page: (json['page'] as num?)?.toInt() ?? 1,
        title: '${json['title'] ?? ''}',
        previewZh: '${json['preview_zh'] ?? ''}',
        durationSec: (json['duration_sec'] as num?)?.toInt(),
        cueCount: (json['cue_count'] as num?)?.toInt() ?? 0,
        qualityScore: (json['quality_score'] as num?)?.toDouble() ?? 0,
        hasEn: json['has_en'] != false,
        hasZh: json['has_zh'] == true,
        sourceOrigin: '${json['source_origin'] ?? 'asr'}',
      );

  final int id;
  final String bvid;
  final int page;
  final String title;
  final String previewZh;
  final int? durationSec;
  final int cueCount;
  final double qualityScore;
  final bool hasEn;
  final bool hasZh;
  final String sourceOrigin;

  String get displayTitle {
    final String t = title.trim();
    if (t.isNotEmpty) return t;
    return '$bvid · 第${page}P';
  }
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

class SharedOcrBookPack {
  const SharedOcrBookPack({
    required this.contentSha256,
    required this.plainText,
    this.title = '',
    this.sourceFilename = '',
    this.pageCount = 0,
    this.charCount = 0,
    this.wordCount = 0,
    this.qualityScore = 0,
    this.sourceOrigin = 'ocr',
    this.hitCount = 0,
  });

  factory SharedOcrBookPack.fromJson(Map<String, dynamic> json) =>
      SharedOcrBookPack(
        contentSha256: '${json['content_sha256'] ?? ''}',
        plainText: '${json['plain_text'] ?? ''}',
        title: '${json['title'] ?? ''}',
        sourceFilename: '${json['source_filename'] ?? ''}',
        pageCount: (json['page_count'] as num?)?.toInt() ?? 0,
        charCount: (json['char_count'] as num?)?.toInt() ?? 0,
        wordCount: (json['word_count'] as num?)?.toInt() ?? 0,
        qualityScore: (json['quality_score'] as num?)?.toDouble() ?? 0,
        sourceOrigin: '${json['source_origin'] ?? 'ocr'}',
        hitCount: (json['hit_count'] as num?)?.toInt() ?? 0,
      );

  final String contentSha256;
  final String plainText;
  final String title;
  final String sourceFilename;
  final int pageCount;
  final int charCount;
  final int wordCount;
  final double qualityScore;
  final String sourceOrigin;
  final int hitCount;
}

class FingerprintCacheSearchResult {
  const FingerprintCacheSearchResult({
    required this.hit,
    required this.message,
    this.degraded = false,
    this.assetId = '',
    this.fingerprintId = '',
    this.similarBlocks = 0,
    this.costMs = 0,
    this.uploadTaskId = '',
    this.assetName = '',
    this.lessonCount = 0,
    this.userCourseAssetId = '',
    this.asset = const <String, dynamic>{},
    this.userCourseAsset = const <String, dynamic>{},
    this.candidates = const <String>[],
    this.lessons = const <Map<String, dynamic>>[],
  });

  factory FingerprintCacheSearchResult.fromJson(Map<String, dynamic> json) {
    final Object? assetRaw = json['asset'];
    final Map<String, dynamic> asset = assetRaw is Map
        ? Map<String, dynamic>.from(assetRaw)
        : <String, dynamic>{};
    final Object? courseRaw = json['user_course_asset'];
    final Map<String, dynamic> course = courseRaw is Map
        ? Map<String, dynamic>.from(courseRaw)
        : <String, dynamic>{};
    final List<Map<String, dynamic>> lessons = _fingerprintLessonsFromAsset(asset);
    final List<String> candidates = <String>[];
    final Object? candRaw = json['candidates'];
    if (candRaw is List) {
      for (final Object? c in candRaw) {
        final String id = '$c'.trim();
        if (id.isNotEmpty) candidates.add(id);
      }
    }
    return FingerprintCacheSearchResult(
      hit: json['hit'] == true,
      degraded: json['degraded'] == true,
      message: '${json['message'] ?? ''}',
      assetId: '${json['asset_id'] ?? asset['id'] ?? ''}',
      fingerprintId: '${json['fingerprint_id'] ?? ''}',
      similarBlocks: (json['similar_blocks'] as num?)?.toInt() ?? 0,
      costMs: (json['cost_ms'] as num?)?.toInt() ?? 0,
      uploadTaskId: '${json['upload_task_id'] ?? ''}',
      assetName: '${asset['asset_name'] ?? ''}',
      lessonCount:
          (asset['total_lesson_count'] as num?)?.toInt() ?? lessons.length,
      userCourseAssetId: '${course['id'] ?? ''}',
      asset: asset,
      userCourseAsset: course,
      candidates: candidates,
      lessons: lessons,
    );
  }

  final bool hit;
  final bool degraded;
  final String message;
  final String assetId;
  final String fingerprintId;
  final int similarBlocks;
  final int costMs;
  final String uploadTaskId;
  final String assetName;
  final int lessonCount;
  final String userCourseAssetId;
  final Map<String, dynamic> asset;
  final Map<String, dynamic> userCourseAsset;
  final List<String> candidates;
  final List<Map<String, dynamic>> lessons;
}

class FingerprintUploadTaskStatus {
  const FingerprintUploadTaskStatus({
    required this.id,
    required this.status,
    this.fileName = '',
    this.fileType = '',
    this.fingerprintId = '',
    this.userCourseAssetId = '',
    this.failReason = '',
  });

  factory FingerprintUploadTaskStatus.fromJson(Map<String, dynamic> json) =>
      FingerprintUploadTaskStatus(
        id: '${json['id'] ?? ''}',
        status: '${json['status'] ?? ''}',
        fileName: '${json['file_name'] ?? ''}',
        fileType: '${json['file_type'] ?? ''}',
        fingerprintId: '${json['fingerprint_id'] ?? ''}',
        userCourseAssetId: '${json['user_course_asset_id'] ?? ''}',
        failReason: '${json['fail_reason'] ?? ''}',
      );

  final String id;
  final String status;
  final String fileName;
  final String fileType;
  final String fingerprintId;
  final String userCourseAssetId;
  final String failReason;

  bool get isTerminal =>
      status == 'success' ||
      status == 'fingerprint_match' ||
      status == 'failed';

  bool get isReady =>
      status == 'success' || status == 'fingerprint_match';
}

List<Map<String, dynamic>> _fingerprintLessonsFromAsset(
  Map<String, dynamic> asset,
) {
  final Object? lessonsRaw = asset['lessons'];
  if (lessonsRaw is Map) {
    final Object? inner = lessonsRaw['lessons'];
    if (inner is List) {
      return <Map<String, dynamic>>[
        for (final Object? item in inner)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    }
  }
  if (lessonsRaw is List) {
    return <Map<String, dynamic>>[
      for (final Object? item in lessonsRaw)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }
  return const <Map<String, dynamic>>[];
}

class SharedOcrBookUpsertResult {
  const SharedOcrBookUpsertResult({
    required this.stored,
    this.replaced = false,
    this.qualityScore = 0,
    this.charCount = 0,
    this.wordCount = 0,
    this.reason = '',
  });

  factory SharedOcrBookUpsertResult.fromJson(Map<String, dynamic> json) =>
      SharedOcrBookUpsertResult(
        stored: json['stored'] == true,
        replaced: json['replaced'] == true,
        qualityScore: (json['quality_score'] as num?)?.toDouble() ?? 0,
        charCount: (json['char_count'] as num?)?.toInt() ?? 0,
        wordCount: (json['word_count'] as num?)?.toInt() ?? 0,
        reason: '${json['reason'] ?? ''}',
      );

  final bool stored;
  final bool replaced;
  final double qualityScore;
  final int charCount;
  final int wordCount;
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
    this.authorId,
    this.coverUrl,
    this.durationSec,
    this.description,
    this.tags = const <String>[],
    this.source = 'bilibili',
    this.reason = 'interest',
  });

  factory AcquireDailyFeedItemDto.fromJson(Map<String, dynamic> json) =>
      AcquireDailyFeedItemDto(
        id: json['id'] as String? ?? '',
        bvid: json['bvid'] as String? ?? '',
        title: json['title'] as String? ?? '',
        author: json['author'] as String? ?? '',
        authorId: json['authorId'] as String?,
        coverUrl: json['coverUrl'] as String?,
        durationSec: (json['durationSec'] as num?)?.toDouble(),
        watchUrl: json['watchUrl'] as String? ?? '',
        description: json['description'] as String?,
        tags: (json['tags'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList(growable: false),
        source: json['source'] as String? ?? 'bilibili',
        reason: json['reason'] as String? ?? 'interest',
      );

  final String id;
  final String bvid;
  final String title;
  final String author;
  final String? authorId;
  final String? coverUrl;
  final double? durationSec;
  final String watchUrl;
  final String? description;
  final List<String> tags;
  final String source;
  /// `interest` | `followed`
  final String reason;

  bool get isFollowed => reason == 'followed' || tags.contains('followed');

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'bvid': bvid,
        'title': title,
        'author': author,
        'authorId': authorId,
        'coverUrl': coverUrl,
        'durationSec': durationSec,
        'watchUrl': watchUrl,
        'description': description,
        'tags': tags,
        'source': source,
        'reason': reason,
      };
}

class FollowedCreatorDto {
  const FollowedCreatorDto({
    required this.source,
    required this.creatorId,
    this.displayName = '',
    this.avatarUrl,
    this.profileUrl,
  });

  factory FollowedCreatorDto.fromJson(Map<String, dynamic> json) =>
      FollowedCreatorDto(
        source: json['source'] as String? ?? 'bilibili',
        creatorId: json['creator_id'] as String? ?? '',
        displayName: json['display_name'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String?,
        profileUrl: json['profile_url'] as String?,
      );

  final String source;
  final String creatorId;
  final String displayName;
  final String? avatarUrl;
  final String? profileUrl;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'source': source,
        'creator_id': creatorId,
        'display_name': displayName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (profileUrl != null) 'profile_url': profileUrl,
      };
}

class RecommendedBilibiliVideoDto {
  const RecommendedBilibiliVideoDto({
    required this.bvid,
    required this.title,
    required this.watchUrl,
    this.coverUrl,
    this.durationSec,
    this.hasSharedSubs = false,
    this.sharedPageCount = 0,
  });

  factory RecommendedBilibiliVideoDto.fromJson(Map<String, dynamic> json) =>
      RecommendedBilibiliVideoDto(
        bvid: '${json['bvid'] ?? ''}'.trim(),
        title: '${json['title'] ?? ''}'.trim(),
        watchUrl: '${json['watch_url'] ?? ''}'.trim(),
        coverUrl: _nullableString(json['cover_url']),
        durationSec: (json['duration_sec'] as num?)?.toDouble(),
        hasSharedSubs: json['has_shared_subs'] == true,
        sharedPageCount: (json['shared_page_count'] as num?)?.toInt() ?? 0,
      );

  final String bvid;
  final String title;
  final String watchUrl;
  final String? coverUrl;
  final double? durationSec;
  final bool hasSharedSubs;
  final int sharedPageCount;
}

class RecommendedBilibiliCreatorDto {
  const RecommendedBilibiliCreatorDto({
    required this.id,
    required this.creatorId,
    required this.displayName,
    this.source = 'bilibili',
    this.avatarUrl,
    this.profileUrl,
    this.blurb,
    this.videos = const <RecommendedBilibiliVideoDto>[],
  });

  factory RecommendedBilibiliCreatorDto.fromJson(Map<String, dynamic> json) {
    final List<RecommendedBilibiliVideoDto> videos =
        <RecommendedBilibiliVideoDto>[];
    final Object? raw = json['videos'];
    if (raw is List) {
      for (final Object? row in raw) {
        if (row is Map) {
          final RecommendedBilibiliVideoDto video =
              RecommendedBilibiliVideoDto.fromJson(
            Map<String, dynamic>.from(row),
          );
          if (video.bvid.isNotEmpty && video.watchUrl.isNotEmpty) {
            videos.add(video);
          }
        }
      }
    }
    return RecommendedBilibiliCreatorDto(
      id: '${json['id'] ?? ''}'.trim(),
      source: '${json['source'] ?? 'bilibili'}'.trim(),
      creatorId: '${json['creator_id'] ?? ''}'.trim(),
      displayName: '${json['display_name'] ?? ''}'.trim(),
      avatarUrl: _nullableString(json['avatar_url']),
      profileUrl: _nullableString(json['profile_url']),
      blurb: _nullableString(json['blurb']),
      videos: List<RecommendedBilibiliVideoDto>.unmodifiable(videos),
    );
  }

  final String id;
  final String source;
  final String creatorId;
  final String displayName;
  final String? avatarUrl;
  final String? profileUrl;
  final String? blurb;
  final List<RecommendedBilibiliVideoDto> videos;
}

String? _nullableString(Object? raw) {
  final String value = '$raw'.trim();
  return value.isEmpty || value == 'null' ? null : value;
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
    this.followedCreators = const <FollowedCreatorDto>[],
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
        followedCreators: (json['followed_creators'] as List<dynamic>? ??
                const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(FollowedCreatorDto.fromJson)
            .toList(growable: false),
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
  final List<FollowedCreatorDto> followedCreators;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'level': level,
    'tags': tags,
    'daily_quota': dailyQuota,
    'notify_daily_feed': notifyDailyFeed,
    'has_bilibili_cookie': hasBilibiliCookie,
    'has_asr_api_key': hasAsrApiKey,
    if (bilibiliCookie != null) 'bilibili_cookie': bilibiliCookie,
    if (asrApiKey != null) 'asr_api_key': asrApiKey,
    // Follows are managed via /api/creators/* — omit so prefs PUT cannot wipe them.
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
    List<FollowedCreatorDto>? followedCreators,
  }) => AcquirePreferencesDto(
    level: level ?? this.level,
    tags: tags ?? this.tags,
    dailyQuota: dailyQuota ?? this.dailyQuota,
    notifyDailyFeed: notifyDailyFeed ?? this.notifyDailyFeed,
    hasBilibiliCookie: hasBilibiliCookie ?? this.hasBilibiliCookie,
    hasAsrApiKey: hasAsrApiKey ?? this.hasAsrApiKey,
    bilibiliCookie: bilibiliCookie ?? this.bilibiliCookie,
    asrApiKey: asrApiKey ?? this.asrApiKey,
    followedCreators: followedCreators ?? this.followedCreators,
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

  /// In-memory reading TTS URL cache (text+voice → absolute media URL).
  /// Avoids repeat lookup/synth RTT when replaying the same sentence.
  static const int _readingSpeechCacheCap = 160;
  final Map<String, String> _readingSpeechUrlCache = <String, String>{};
  final Map<String, Future<String>> _readingSpeechInflight =
      <String, Future<String>>{};

  Future<({int revision, Map<String, dynamic>? state})> reviewBackup(
    String token, {
    int? revision,
    Map<String, dynamic>? state,
  }) =>
      documentBackup(
        Endpoints.reviewBackup,
        token: token,
        revision: revision,
        state: state,
      );

  /// Revision-CAS document blob (reading / wordbook / settings / review).
  Future<({int revision, Map<String, dynamic>? state})> documentBackup(
    String path, {
    String? token,
    int? revision,
    Map<String, dynamic>? state,
  }) async {
    final Options options = Options(
      headers: token == null || token.isEmpty
          ? null
          : <String, String>{'Authorization': 'Bearer $token'},
      extra: _noCache.extra,
    );
    final Response<Map<String, dynamic>> response = revision == null
        ? await _dio.get<Map<String, dynamic>>(path, options: options)
        : await _dio.put<Map<String, dynamic>>(
            path,
            data: <String, dynamic>{'revision': revision, 'state': state},
            options: options,
          );
    final Map<String, dynamic> body = response.data!;
    return (
      revision: body['revision'] as int,
      state: body['state'] as Map<String, dynamic>?,
    );
  }

  Future<Map<String, dynamic>> syncStatus({String? token}) async {
    final Response<Map<String, dynamic>> response =
        await _dio.get<Map<String, dynamic>>(
      Endpoints.syncStatus,
      options: Options(
        headers: token == null || token.isEmpty
            ? null
            : <String, String>{'Authorization': 'Bearer $token'},
        extra: _noCache.extra,
      ),
    );
    return response.data ?? <String, dynamic>{};
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

  Future<List<FollowedCreatorDto>> listFollowedCreators() async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.creatorsFollowed,
      options: Options(
        extra: const <String, Object>{
          'dio_cache_interceptor_force_refresh': true,
        },
      ),
    );
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(FollowedCreatorDto.fromJson)
        .toList(growable: false);
  }

  Future<List<RecommendedBilibiliCreatorDto>> listRecommendedCreators() async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.creatorsRecommended,
      // Allow short HTTP cache; server also keeps a 15‑minute payload cache.
      options: Options(
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(RecommendedBilibiliCreatorDto.fromJson)
        .where(
          (RecommendedBilibiliCreatorDto item) =>
              item.displayName.isNotEmpty && item.videos.isNotEmpty,
        )
        .toList(growable: false);
  }

  Future<List<FollowedCreatorDto>> followCreator({
    String? url,
    String? source,
    String? creatorId,
    String? displayName,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.creatorsFollow,
      data: <String, dynamic>{
        if (url != null && url.trim().isNotEmpty) 'url': url.trim(),
        if (source != null) 'source': source,
        if (creatorId != null) 'creator_id': creatorId,
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
      },
      options: Options(
        extra: const <String, Object>{
          'dio_cache_interceptor_force_refresh': true,
        },
      ),
    );
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(FollowedCreatorDto.fromJson)
        .toList(growable: false);
  }

  Future<List<FollowedCreatorDto>> unfollowCreator({
    required String source,
    required String creatorId,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.creatorsUnfollow,
      data: <String, dynamic>{
        'source': source,
        'creator_id': creatorId,
      },
      options: Options(
        extra: const <String, Object>{
          'dio_cache_interceptor_force_refresh': true,
        },
      ),
    );
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(FollowedCreatorDto.fromJson)
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

  Future<List<LearningScenario>> fetchLearningTasks() async {
    try {
      final Response<dynamic> response = await _dio.get(Endpoints.learningTasks);
      final Object? data = response.data;
      if (data is! List) return LearningScenario.seeds;
      final List<LearningScenario> items = <LearningScenario>[];
      for (final Object? row in data) {
        if (row is! Map) continue;
        final LearningScenario task = LearningScenario.fromJson(
          Map<String, dynamic>.from(row),
        );
        if (task.id.isNotEmpty && task.prompt.isNotEmpty) {
          items.add(task);
        }
      }
      return items.isEmpty ? LearningScenario.seeds : items;
    } catch (_) {
      return LearningScenario.seeds;
    }
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

  Future<Map<String, dynamic>?> closeLearningSession(String sessionId) async {
    final String id = sessionId.trim();
    if (id.isEmpty) return null;
    try {
      final Response<dynamic> response = await _dio.post(
        '${Endpoints.learningSessions}/$id/close',
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );
      if (response.data is! Map) return null;
      return Map<String, dynamic>.from(response.data as Map);
    } catch (_) {
      return null;
    }
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

  Future<List<Map<String, dynamic>>> listAssetSkus() async {
    final Response<dynamic> response = await _dio.get(Endpoints.assetsSkus);
    return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listAssetOrders() async {
    final Response<dynamic> response = await _dio.get(Endpoints.assetsOrders);
    return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> membershipRewards() async =>
      (await _dio.get('${Endpoints.assets}/membership-rewards')).data as Map<String, dynamic>;

  Future<void> claimMembershipReward(String code) async {
    await _dio.post('${Endpoints.assets}/membership-rewards/$code/claim');
  }

  Future<void> redeemMembershipCoupon(int id) async {
    await _dio.post('${Endpoints.assets}/membership-coupons/$id/redeem');
  }

  Future<Map<String, dynamic>> commerceModuleAccess(String moduleCode) async {
    final Response<dynamic> response =
        await _dio.get(Endpoints.commerceModuleAccess(moduleCode));
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commerceCatalog() async {
    final Response<dynamic> response = await _dio.get(Endpoints.commerceCatalog);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commerceFreeTrialSeeds() async {
    final Response<dynamic> response =
        await _dio.get(Endpoints.commerceFreeTrialSeeds);
    return response.data as Map<String, dynamic>;
  }

  /// Private product feedback — admin console only, never community-visible.
  Future<Map<String, dynamic>> submitProductFeedback({
    required String body,
    String title = '',
    String category = 'general',
    String contact = '',
    String appVersion = '',
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.productFeedback,
      data: <String, dynamic>{
        'body': body,
        if (title.trim().isNotEmpty) 'title': title.trim(),
        'category': category,
        if (contact.trim().isNotEmpty) 'contact': contact.trim(),
        if (appVersion.trim().isNotEmpty) 'app_version': appVersion.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> commerceTrialStatus() async {
    final Response<dynamic> response =
        await _dio.get(Endpoints.commerceTrialStatus);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commerceClaimWelcomePro() async {
    final Response<dynamic> response =
        await _dio.post(Endpoints.commerceTrialClaimWelcome);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commerceClaimTrialExtend() async {
    final Response<dynamic> response =
        await _dio.post(Endpoints.commerceTrialClaimExtend);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commercePoints() async {
    final Response<dynamic> response = await _dio.get(Endpoints.commercePoints);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commercePayStatus() async {
    final Response<dynamic> response =
        await _dio.get(Endpoints.commercePayStatus);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commerceEarnPoints({
    required String reason,
    int? amount,
    Map<String, dynamic>? meta,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.commercePointsEarn,
      data: <String, dynamic>{
        'reason': reason,
        if (amount != null) 'amount': amount,
        if (meta != null) 'meta': meta,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commerceSpendPoints({
    required String item,
    Map<String, dynamic>? meta,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.commercePointsSpend,
      data: <String, dynamic>{
        'item': item,
        if (meta != null) 'meta': meta,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commerceQuotas({String? moduleCode}) async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.commerceQuotas,
      queryParameters: <String, dynamic>{
        if (moduleCode != null && moduleCode.isNotEmpty) 'module_code': moduleCode,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commerceConsumeQuota({
    required String metric,
    int amount = 1,
    String? moduleCode,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.commerceQuotasConsume,
      data: <String, dynamic>{
        'metric': metric,
        'amount': amount,
        if (moduleCode != null) 'module_code': moduleCode,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commerceEntitlements() async {
    final Response<dynamic> response =
        await _dio.get(Endpoints.commerceEntitlements);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commerceRank() async {
    final Response<dynamic> response = await _dio.get(Endpoints.commerceRank);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commerceCheckin() async {
    final Response<dynamic> response = await _dio.post(Endpoints.commerceCheckin);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commerceArenaStatus() async {
    final Response<dynamic> response =
        await _dio.get(Endpoints.commerceArenaStatus);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commerceArenaStart() async {
    final Response<dynamic> response =
        await _dio.post(Endpoints.commerceArenaStart);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commerceArenaFinish({
    required String matchId,
    required List<int?> choices,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.commerceArenaFinish,
      data: <String, dynamic>{'match_id': matchId, 'choices': choices},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commerceTrackEvent({
    required String event,
    String? module,
    String? page,
    Map<String, dynamic>? meta,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.commerceEvents,
      data: <String, dynamic>{
        'event': event,
        if (module != null) 'module': module,
        if (page != null) 'page': page,
        if (meta != null) 'meta': meta,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> markAssetOrderPaid({required int orderId}) async {
    final Response<dynamic> response = await _dio.post(
      '${Endpoints.assetsOrders}/$orderId/mark-paid',
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createAssetOrder({
    required List<({String skuCode, int quantity})> items,
    String provider = 'wechat',
    int? couponId,
    List<String>? selectedModules,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.assetsOrders,
      data: <String, dynamic>{
        'provider': provider,
        if (couponId != null) 'coupon_id': couponId,
        if (selectedModules != null && selectedModules.isNotEmpty)
          'selected_modules': selectedModules,
        'items': <Map<String, dynamic>>[
          for (final ({String skuCode, int quantity}) item in items)
            <String, dynamic>{
              'sku_code': item.skuCode,
              'quantity': item.quantity,
            },
        ],
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createWechatPrepay({
    required int orderId,
  }) async {
    final Response<dynamic> response = await _dio.post(
      '${Endpoints.assetsOrders}/$orderId/wechat-prepay',
    );
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
    String? seriesFolder,
    String? seriesTitle,
  }) async {
    // Chunk large selections; server accepts up to 200 per request.
    final List<Map<String, dynamic>> allItems = <Map<String, dynamic>>[];
    Map<String, dynamic>? seriesCourse;
    for (int i = 0; i < paths.length; i += 200) {
      final List<String> chunk = paths.sublist(
        i,
        i + 200 > paths.length ? paths.length : i + 200,
      );
      final Response<dynamic> response = await _dio.post(
        Endpoints.netdiskImport,
        data: <String, dynamic>{
          'provider': provider,
          'paths': chunk,
          if (seriesFolder != null) 'series_folder': seriesFolder,
          if (seriesTitle != null) 'series_title': seriesTitle,
        },
      );
      final Map<String, dynamic> body = response.data as Map<String, dynamic>;
      final List<dynamic> items =
          (body['items'] as List<dynamic>?) ?? const <dynamic>[];
      for (final dynamic row in items) {
        if (row is Map<String, dynamic>) {
          allItems.add(row);
        } else if (row is Map) {
          allItems.add(row.map((Object? k, Object? v) => MapEntry('$k', v)));
        }
      }
      final Object? sc = body['series_course'];
      if (sc is Map<String, dynamic>) {
        seriesCourse = sc;
      } else if (sc is Map) {
        seriesCourse = sc.map((Object? k, Object? v) => MapEntry('$k', v));
      }
    }
    return <String, dynamic>{
      'items': allItems,
      if (seriesCourse != null) 'series_course': seriesCourse,
    };
  }

  Future<Map<String, dynamic>> importNetdiskSeries({
    required String provider,
    required String folderPath,
    String? title,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.netdiskImportSeries,
      data: <String, dynamic>{
        'provider': provider,
        'folder_path': folderPath,
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
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

  /// Cloud VL refine for photo scene nouns (DashScope Qwen-VL on API host).
  Future<List<SceneWordLabel>> recognizeSceneWords({
    required String imageBase64,
    String mime = 'image/jpeg',
    List<SceneWordLabel> seedLabels = const <SceneWordLabel>[],
    int limit = 8,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.learningSceneRecognize,
      data: <String, dynamic>{
        'image_base64': imageBase64,
        'mime': mime,
        'limit': limit,
        'seed_labels': seedLabels
            .map(
              (SceneWordLabel item) => <String, dynamic>{
                'word': item.word,
                'chinese': item.chinese,
                'confidence': item.confidence,
                'anchor_x': item.anchorX,
                'anchor_y': item.anchorY,
              },
            )
            .toList(growable: false),
      },
      options: Options(
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 32),
        extra: const <String, Object>{
          'dio_cache_interceptor_force_refresh': true,
        },
      ),
    );
    final Map<String, dynamic> body =
        Map<String, dynamic>.from(response.data as Map);
    final List<dynamic> rows =
        (body['labels'] as List<dynamic>?) ?? const <dynamic>[];
    return rows
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (Map<dynamic, dynamic> row) => SceneWordLabel.fromJson(
            Map<String, dynamic>.from(row),
          ).copyWith(source: 'cloud'),
        )
        .toList(growable: false);
  }

  Future<OralMatchStatus> enqueueOralMatch({
    String mode = 'peer_oral',
    String nativeLang = '',
    String targetLang = '',
    String topic = '',
    String cefr = '',
    OralMatchContent content = const OralMatchContent(),
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.oralMatchEnqueue,
      data: <String, dynamic>{
        'mode': mode,
        if (nativeLang.trim().isNotEmpty) 'native_lang': nativeLang.trim(),
        if (targetLang.trim().isNotEmpty) 'target_lang': targetLang.trim(),
        if (topic.trim().isNotEmpty) 'topic': topic.trim(),
        if (cefr.trim().isNotEmpty) 'cefr': cefr.trim(),
        ...content.toJson(),
        if (topic.trim().isEmpty && content.topic.isNotEmpty)
          'topic': content.topic,
      },
    );
    return OralMatchStatus.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<OralMatchStatus> createOralMatchInvite({
    OralMatchContent content = const OralMatchContent(),
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.oralMatchInvites,
      data: content.toJson(),
    );
    return OralMatchStatus.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<List<OralMatchStatus>> listOralMatchInvites() async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.oralMatchInvites,
    );
    final Object? raw = (response.data as Map)['invites'];
    if (raw is! List) return const <OralMatchStatus>[];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (Map<dynamic, dynamic> row) =>
              OralMatchStatus.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<OralMatchStatus> acceptOralMatchInvite(String inviteId) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.oralMatchInviteAccept(inviteId),
    );
    return OralMatchStatus.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<void> cancelOralMatchInvite(String inviteId) async {
    await _dio.post(Endpoints.oralMatchInviteCancel(inviteId));
  }

  Future<OralMatchStatus> oralMatchStatus() async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.oralMatchStatus,
    );
    return OralMatchStatus.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<void> leaveOralMatch() async {
    await _dio.post(Endpoints.oralMatchLeave);
  }

  Future<OralMatchStatus> oralMatchHeartbeat() async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.oralMatchHeartbeat,
    );
    return OralMatchStatus.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<void> reportOralMatchPeer({
    required String roomId,
    required String reason,
  }) async {
    await _dio.post(
      Endpoints.oralMatchReport(roomId),
      data: <String, dynamic>{'reason': reason},
    );
  }

  Future<OralMatchMessage> postOralMatchMessage({
    required String roomId,
    required String text,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.oralMatchMessages(roomId),
      data: <String, dynamic>{'text': text},
    );
    return OralMatchMessage.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<List<OralMatchMessage>> listOralMatchMessages({
    required String roomId,
    String? afterId,
  }) async {
    final OralMatchInbox inbox = await fetchOralMatchInbox(
      roomId: roomId,
      afterId: afterId,
    );
    return inbox.messages;
  }

  Future<OralMatchInbox> fetchOralMatchInbox({
    required String roomId,
    String? afterId,
  }) async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.oralMatchMessages(roomId),
      queryParameters: <String, dynamic>{
        if ((afterId ?? '').trim().isNotEmpty) 'after_id': afterId!.trim(),
      },
    );
    final Map<String, dynamic> data = Map<String, dynamic>.from(
      response.data as Map,
    );
    final Object? raw = data['messages'];
    final List<OralMatchMessage> messages = raw is! List
        ? const <OralMatchMessage>[]
        : raw
            .whereType<Map>()
            .map(
              (Map row) => OralMatchMessage.fromJson(
                Map<String, dynamic>.from(row),
              ),
            )
            .toList(growable: false);
    return OralMatchInbox(
      messages: messages,
      roomClosed: data['room_closed'] == true,
      peerOnline: data['peer_online'] == true,
    );
  }

  /// Shared OCR book library keyed by PDF/file sha256. Null on miss.
  Future<SharedOcrBookPack?> getSharedOcrBook({
    required String contentSha256,
  }) async {
    final String key = contentSha256.trim().toLowerCase();
    if (key.length != 64) return null;
    try {
      final Response<dynamic> response = await _dio.get(
        Endpoints.sharedOcrBooks,
        queryParameters: <String, dynamic>{'content_sha256': key},
        options: Options(
          validateStatus: (int? status) =>
              status != null &&
              ((status >= 200 && status < 300) || status == 404),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      if (response.statusCode == 404 || response.data is! Map) {
        return null;
      }
      return SharedOcrBookPack.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<SharedOcrBookUpsertResult?> putSharedOcrBook({
    required String contentSha256,
    required String plainText,
    String title = '',
    String sourceFilename = '',
    int pageCount = 0,
    String sourceOrigin = 'ocr',
  }) async {
    try {
      final Response<dynamic> response = await _dio.put(
        Endpoints.sharedOcrBooks,
        data: <String, dynamic>{
          'content_sha256': contentSha256.trim().toLowerCase(),
          'plain_text': plainText,
          'title': title,
          'source_filename': sourceFilename,
          'page_count': pageCount,
          'source_origin': sourceOrigin,
        },
      );
      if (response.data is! Map) return null;
      return SharedOcrBookUpsertResult.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } catch (_) {
      return null;
    }
  }

  /// 指纹检索：命中则复用公共课程资产，未命中由上游排队 GPU 解构。
  ///
  /// [privateOnly] 教材流：miss 只写私人课，不进公共 asset_cache；需 [licenseAck]。
  Future<FingerprintCacheSearchResult?> searchFingerprintCache({
    required String cleanedText,
    String sourceType = 'pdf_text',
    String? fileName,
    String fileType = 'pdf',
    bool createUploadTask = true,
    bool autoBindCourse = true,
    bool privateOnly = false,
    bool licenseAck = false,
  }) async {
    final String text = cleanedText.trim();
    if (text.length < 80) return null;
    try {
      final Response<dynamic> response = await _dio.post(
        Endpoints.fingerprintCacheSearch,
        data: <String, dynamic>{
          'cleaned_text': text,
          'source_type': sourceType,
          if (fileName != null && fileName.trim().isNotEmpty)
            'file_name': fileName.trim(),
          'file_type': fileType,
          'create_upload_task': createUploadTask,
          'auto_bind_course': autoBindCourse,
          'private_only': privateOnly,
          'license_ack': licenseAck,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      if (response.data is! Map) return null;
      return FingerprintCacheSearchResult.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> registerFingerprintCache({
    required String cleanedText,
    required String assetName,
    required List<Map<String, dynamic>> lessons,
    String sourceType = 'pdf_text',
    String? uploadTaskId,
    String? cefrLevel,
    String? summaryText,
    List<String> tags = const <String>[],
  }) async {
    final String text = cleanedText.trim();
    if (text.length < 80 || assetName.trim().isEmpty) return null;
    try {
      final Response<dynamic> response = await _dio.post(
        Endpoints.fingerprintCacheRegister,
        data: <String, dynamic>{
          'cleaned_text': text,
          'source_type': sourceType,
          'asset_name': assetName.trim(),
          'lessons': lessons,
          if (cefrLevel != null && cefrLevel.trim().isNotEmpty)
            'cefr_level': cefrLevel.trim(),
          if (summaryText != null && summaryText.trim().isNotEmpty)
            'summary_text': summaryText.trim(),
          'tags': tags,
          if (uploadTaskId != null && uploadTaskId.trim().isNotEmpty)
            'upload_task_id': uploadTaskId.trim(),
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 60),
        ),
      );
      if (response.data is! Map) return null;
      return Map<String, dynamic>.from(response.data as Map);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getFingerprintAsset(String assetId) async {
    final String id = assetId.trim();
    if (id.isEmpty) return null;
    try {
      final Response<dynamic> response = await _dio.get(
        Endpoints.fingerprintCacheAsset(id),
        options: Options(
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
        ),
      );
      if (response.data is! Map) return null;
      return Map<String, dynamic>.from(response.data as Map);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> listMyFingerprintCourses() async {
    try {
      final Response<dynamic> response = await _dio.get(
        Endpoints.fingerprintCacheMyCourses,
        options: Options(
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
        ),
      );
      if (response.data is! Map) return const <Map<String, dynamic>>[];
      final Object? items = (response.data as Map)['items'];
      if (items is! List) return const <Map<String, dynamic>>[];
      return <Map<String, dynamic>>[
        for (final Object? item in items)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>?> getMyFingerprintCourse(String courseId) async {
    final String id = courseId.trim();
    if (id.isEmpty) return null;
    try {
      final Response<dynamic> response = await _dio.get(
        Endpoints.fingerprintCacheMyCourse(id),
        options: Options(
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
        ),
      );
      if (response.data is! Map) return null;
      return Map<String, dynamic>.from(response.data as Map);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> patchMyFingerprintCourseLessons({
    required String courseId,
    required String action,
    List<int> lessonNos = const <int>[],
    int? splitAtChar,
    Map<String, dynamic>? lesson,
    List<Map<String, dynamic>>? lessons,
  }) async {
    final String id = courseId.trim();
    if (id.isEmpty || action.trim().isEmpty) return null;
    try {
      final Response<dynamic> response = await _dio.patch(
        Endpoints.fingerprintCacheCourseLessons(id),
        data: <String, dynamic>{
          'action': action.trim(),
          'lesson_nos': lessonNos,
          if (splitAtChar != null) 'split_at_char': splitAtChar,
          if (lesson != null) 'lesson': lesson,
          if (lessons != null) 'lessons': lessons,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      if (response.data is! Map) return null;
      return Map<String, dynamic>.from(response.data as Map);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> finalizeMyFingerprintCourse({
    required String courseId,
    String? title,
    bool licenseAck = true,
  }) async {
    final String id = courseId.trim();
    if (id.isEmpty) return null;
    try {
      final Response<dynamic> response = await _dio.post(
        Endpoints.fingerprintCacheCourseFinalize(id),
        data: <String, dynamic>{
          if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
          'license_ack': licenseAck,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
        ),
      );
      if (response.data is! Map) return null;
      return Map<String, dynamic>.from(response.data as Map);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> syncMyFingerprintCourseFromPublic(
    String courseId,
  ) async {
    final String id = courseId.trim();
    if (id.isEmpty) return null;
    try {
      final Response<dynamic> response = await _dio.post(
        Endpoints.fingerprintCacheCourseSyncPublic(id),
        options: Options(
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
        ),
      );
      if (response.data is! Map) return null;
      return Map<String, dynamic>.from(response.data as Map);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> listFingerprintNotifications() async {
    try {
      final Response<dynamic> response = await _dio.get(
        Endpoints.fingerprintCacheNotifications,
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );
      if (response.data is! Map) return const <Map<String, dynamic>>[];
      final Object? items = (response.data as Map)['items'];
      if (items is! List) return const <Map<String, dynamic>>[];
      return <Map<String, dynamic>>[
        for (final Object? item in items)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> ackFingerprintNotifications({
    List<String>? uploadTaskIds,
  }) async {
    try {
      await _dio.post(
        Endpoints.fingerprintCacheNotificationsAck,
        data: <String, dynamic>{
          if (uploadTaskIds != null) 'upload_task_ids': uploadTaskIds,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );
    } catch (_) {}
  }

  Future<FingerprintUploadTaskStatus?> getFingerprintUploadTask(
    String taskId,
  ) async {
    final String id = taskId.trim();
    if (id.isEmpty) return null;
    try {
      final Response<dynamic> response = await _dio.get(
        Endpoints.fingerprintCacheUploadTask(id),
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );
      if (response.data is! Map) return null;
      return FingerprintUploadTaskStatus.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } catch (_) {
      return null;
    }
  }

  /// Poll until success / fingerprint_match / failed, or [timeout] elapses.
  Future<FingerprintUploadTaskStatus?> pollFingerprintUploadTask(
    String taskId, {
    Duration timeout = const Duration(seconds: 90),
    Duration interval = const Duration(seconds: 2),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    FingerprintUploadTaskStatus? last;
    while (DateTime.now().isBefore(deadline)) {
      last = await getFingerprintUploadTask(taskId);
      if (last != null && last.isTerminal) return last;
      await Future<void>.delayed(interval);
    }
    return last;
  }

  Future<FingerprintCacheSearchResult?> confirmFingerprintBind({
    required String assetId,
    String? uploadTaskId,
    String? assetTitle,
  }) async {
    final String id = assetId.trim();
    if (id.isEmpty) return null;
    try {
      final Response<dynamic> response = await _dio.post(
        Endpoints.fingerprintCacheConfirmBind,
        data: <String, dynamic>{
          'asset_id': id,
          if (uploadTaskId != null && uploadTaskId.trim().isNotEmpty)
            'upload_task_id': uploadTaskId.trim(),
          if (assetTitle != null && assetTitle.trim().isNotEmpty)
            'asset_title': assetTitle.trim(),
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      if (response.data is! Map) return null;
      final Map<String, dynamic> data =
          Map<String, dynamic>.from(response.data as Map);
      final Object? assetRaw = data['asset'];
      final Object? courseRaw = data['user_course_asset'];
      return FingerprintCacheSearchResult.fromJson(<String, dynamic>{
        'hit': true,
        'message': '已确认复用疑似匹配课程',
        'asset_id': id,
        'asset': assetRaw is Map ? assetRaw : <String, dynamic>{},
        'user_course_asset':
            courseRaw is Map ? courseRaw : <String, dynamic>{},
        'upload_task_id': uploadTaskId ?? '',
      });
    } catch (_) {
      return null;
    }
  }

  /// ECS content-addressed reading TTS. Null when not pre-generated.
  Future<String?> lookupReadingSpeechUrl({
    required String text,
    String voice = '',
    String language = 'en',
  }) async {
    final String spoken = text.trim();
    if (spoken.isEmpty) return null;
    try {
      final Response<dynamic> response = await _dio.get(
        Endpoints.readingSpeechLookup,
        queryParameters: <String, dynamic>{
          'text': spoken,
          if (voice.trim().isNotEmpty) 'voice': voice.trim(),
          'language': language,
        },
        options: Options(
          validateStatus: (int? status) =>
              status != null &&
              ((status >= 200 && status < 300) || status == 404),
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      if (response.statusCode == 404 || response.data is! Map) {
        return null;
      }
      final Object? url = (response.data as Map)['audio_url'];
      final String value = '$url'.trim();
      return value.isEmpty ? null : value;
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Submit / reuse a durable ECS GPU subtitle job for one Bilibili page.
  ///
  /// Returns null when offline, unauthenticated, or the identity is invalid.
  Future<SharedSubtitleGpuJob?> enqueueSharedSubtitleJob({
    required String bvid,
    int page = 1,
  }) async {
    final String id = bvid.trim();
    if (id.isEmpty) {
      return null;
    }
    try {
      final Response<dynamic> response = await _dio.post<Object?>(
        Endpoints.sharedSubtitlesJobs,
        data: <String, Object>{'bvid': id, 'page': page < 1 ? 1 : page},
        options: Options(
          validateStatus: (int? status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      if (response.data is Map<String, dynamic>) {
        return SharedSubtitleGpuJob.fromJson(
          response.data as Map<String, dynamic>,
        );
      }
      if (response.data is Map) {
        return SharedSubtitleGpuJob.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
      }
      return SharedSubtitleGpuJob(id: '', bvid: id, page: page, state: 'queued');
    } on DioException {
      // Missing login or offline ECS must not block local fill / import.
      return null;
    } catch (_) {
      return null;
    }
  }

  /// English SRT already known → GPU EN→ZH only (no Whisper download).
  Future<SharedSubtitleGpuJob?> enqueueSharedSubtitleTranslateJob({
    required String bvid,
    required String subtitleEnSrt,
    int page = 1,
    String? title,
    int? cid,
    int? durationSec,
  }) async {
    final String id = bvid.trim();
    final String en = subtitleEnSrt.trim();
    if (id.isEmpty || en.length < 20) {
      return null;
    }
    try {
      final Response<dynamic> response = await _dio.post<Object?>(
        Endpoints.sharedSubtitlesTranslateJobs,
        data: <String, Object?>{
          'bvid': id,
          'page': page < 1 ? 1 : page,
          'subtitle_en_srt': en,
          if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(),
          if (cid != null) 'cid': cid,
          if (durationSec != null) 'duration_sec': durationSec,
        },
        options: Options(
          validateStatus: (int? status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      if (response.data is Map<String, dynamic>) {
        return SharedSubtitleGpuJob.fromJson(
          response.data as Map<String, dynamic>,
        );
      }
      if (response.data is Map) {
        return SharedSubtitleGpuJob.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
      }
      return SharedSubtitleGpuJob(id: '', bvid: id, page: page, state: 'queued');
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Returns null on 404 / network miss (shared cache optional).
  ///
  /// On miss, best-effort enqueues a cloud GPU generation job so workers can
  /// fill the shared pack for later downloads.
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
        await enqueueSharedSubtitleJob(bvid: bvid, page: page);
        return null;
      }
      return SharedBilibiliSubtitlePack.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        await enqueueSharedSubtitleJob(bvid: bvid, page: page);
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

  /// Community shared Bilibili packs (title + Chinese preview, no full SRT).
  Future<({int total, List<SharedBilibiliSubtitleListItem> items})>
      listSharedBilibiliSubtitles({
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.sharedSubtitlesBilibiliList,
      queryParameters: <String, dynamic>{
        'limit': limit,
        'offset': offset,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      },
      options: Options(
        extra: const <String, Object>{
          'dio_cache_interceptor_force_refresh': true,
        },
      ),
    );
    final Map<String, dynamic> data =
        (response.data as Map<String, dynamic>?) ?? <String, dynamic>{};
    final List<SharedBilibiliSubtitleListItem> items =
        ((data['items'] as List<dynamic>?) ?? const <dynamic>[])
            .cast<Map<String, dynamic>>()
            .map(SharedBilibiliSubtitleListItem.fromJson)
            .toList(growable: false);
    return (
      total: (data['total'] as num?)?.toInt() ?? items.length,
      items: items,
    );
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
    String? title,
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
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
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

  Future<ServerSyllabusCatalog> fetchSyllabusCatalog({
    SyllabusBookKind? kind,
    bool refresh = false,
  }) async {
    final Map<String, dynamic> query = <String, dynamic>{};
    if (kind != null) query['kind'] = kind.storageName;
    if (refresh) query['refresh'] = true;
    final Response<dynamic> response = await _dio.get(
      Endpoints.syllabusCatalog,
      queryParameters: query.isEmpty ? null : query,
    );
    final Object? data = response.data;
    if (data is Map<String, dynamic>) {
      return ServerSyllabusCatalog.fromJson(data);
    }
    if (data is Map) {
      return ServerSyllabusCatalog.fromJson(Map<String, dynamic>.from(data));
    }
    return ServerSyllabusCatalog.empty;
  }

  Future<SyllabusBook> downloadSyllabusBook(String bookId) async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.syllabusBook(bookId),
    );
    final Object? data = response.data;
    final Map<String, dynamic> json;
    if (data is Map<String, dynamic>) {
      json = data;
    } else if (data is Map) {
      json = Map<String, dynamic>.from(data);
    } else {
      throw StateError('词书响应格式错误');
    }
    final SyllabusBook book = SyllabusBook.fromJson(json, builtin: false);
    if (book.id.isEmpty || book.words.isEmpty) {
      throw StateError('词书为空或无效');
    }
    return book;
  }

  Future<FoundationMediaManifest> foundationMediaManifest({
    bool refresh = false,
  }) async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.foundationMediaManifest,
      queryParameters: refresh ? <String, dynamic>{'refresh': true} : null,
    );
    final Object? data = response.data;
    if (data is Map<String, dynamic>) {
      return FoundationMediaManifest.fromJson(data);
    }
    if (data is Map) {
      return FoundationMediaManifest.fromJson(
        Map<String, dynamic>.from(data),
      );
    }
    return FoundationMediaManifest.empty;
  }

  Future<FoundationMediaItem?> foundationMediaLookup({
    required String bookId,
    required String key,
  }) async {
    try {
      final Response<dynamic> response = await _dio.get(
        Endpoints.foundationMediaLookup,
        queryParameters: <String, dynamic>{
          'book_id': bookId,
          'key': key,
        },
      );
      final Object? data = response.data;
      if (data is Map<String, dynamic>) {
        return FoundationMediaItem.fromJson(data);
      }
      if (data is Map) {
        return FoundationMediaItem.fromJson(Map<String, dynamic>.from(data));
      }
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      rethrow;
    }
    return null;
  }

  /// ECS content media (reading / oral / course / …). Same item shape as foundation.
  Future<FoundationMediaManifest> contentMediaManifest({
    String namespace = 'reading',
    bool refresh = false,
  }) async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.contentMediaManifest,
      queryParameters: <String, dynamic>{
        'namespace': namespace,
        if (refresh) 'refresh': true,
      },
    );
    final Object? data = response.data;
    if (data is Map<String, dynamic>) {
      return FoundationMediaManifest.fromJson(data);
    }
    if (data is Map) {
      return FoundationMediaManifest.fromJson(
        Map<String, dynamic>.from(data),
      );
    }
    return FoundationMediaManifest.empty;
  }

  /// Aliyun DashScope voice catalog (`configured` false when server key missing).
  Future<Map<String, dynamic>> readingVoices() async {
    final Response<dynamic> response = await _dio.get(Endpoints.readingVoices);
    final Object? data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{
      'voices': <String>[],
      'labels': <String, String>{},
      'configured': false,
    };
  }

  String _readingSpeechCacheKey(String text, String voice) =>
      '${voice.trim()}|${text.trim()}';

  String _absoluteMediaUrl(String rawUrl) {
    final String trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return Uri.parse(
      Endpoints.normalizeBaseUrl(_dio.options.baseUrl),
    ).resolve(trimmed).toString();
  }

  void _rememberReadingSpeechUrl(String key, String url) {
    if (url.isEmpty) return;
    _readingSpeechUrlCache.remove(key);
    _readingSpeechUrlCache[key] = url;
    while (_readingSpeechUrlCache.length > _readingSpeechCacheCap) {
      _readingSpeechUrlCache.remove(_readingSpeechUrlCache.keys.first);
    }
  }

  /// Synthesize [text] with an Aliyun English voice; returns absolute audio URL
  /// cached on ECS under `/media/reading/tts/…`.
  ///
  /// Hot path: memory cache → POST (server disk cache / synth).
  /// Concurrent identical requests share one in-flight Future (prefetch-friendly).
  /// Skip client lookup-first: a 404 RTT would slow cold first taps.
  Future<String> readingSpeech(String text, String voice) {
    final String spoken = text.trim();
    if (spoken.isEmpty) {
      return Future<String>.error(StateError('empty speech text'));
    }
    final String key = _readingSpeechCacheKey(spoken, voice);
    final String? cached = _readingSpeechUrlCache[key];
    if (cached != null && cached.isNotEmpty) {
      return Future<String>.value(cached);
    }
    final Future<String>? pending = _readingSpeechInflight[key];
    if (pending != null) return pending;

    final Future<String> work = () async {
      try {
        final Response<dynamic> response = await _dio.post(
          Endpoints.readingSpeech,
          data: <String, dynamic>{
            'text': spoken,
            'voice': voice,
            'language': 'en',
          },
          options: Options(
            receiveTimeout: const Duration(seconds: 45),
            sendTimeout: const Duration(seconds: 20),
            extra: const <String, Object>{
              'dio_cache_interceptor_force_refresh': true,
            },
          ),
        );
        final Object? data = response.data;
        final Map<String, dynamic> json = data is Map<String, dynamic>
            ? data
            : Map<String, dynamic>.from(data as Map);
        final String rawUrl = (json['audio_url'] as String? ?? '').trim();
        if (rawUrl.isEmpty) {
          throw StateError('阿里云配音未返回音频地址');
        }
        final String absolute = _absoluteMediaUrl(rawUrl);
        _rememberReadingSpeechUrl(key, absolute);
        return absolute;
      } finally {
        _readingSpeechInflight.remove(key);
      }
    }();
    _readingSpeechInflight[key] = work;
    return work;
  }

  /// Fire-and-forget: queue current page TTS on ECS / 5060 Ti → shared packs.
  Future<Map<String, dynamic>?> enqueueReadingSpeechPregen({
    required String docId,
    required String text,
    required String voice,
    int pageIndex = 0,
  }) async {
    final String spoken = text.trim();
    final String id = docId.trim();
    if (spoken.isEmpty || id.isEmpty) return null;
    try {
      final Response<dynamic> response = await _dio.post(
        Endpoints.readingSpeechPregen,
        data: <String, dynamic>{
          'doc_id': id,
          'text': spoken,
          'voice': voice.trim(),
          'page_index': pageIndex,
          'language': 'en',
          'process_on_ecs': true,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
          extra: const <String, Object>{
            'dio_cache_interceptor_force_refresh': true,
          },
        ),
      );
      final Object? data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Queue a long novel for cloud TTS (5060 Ti preferred). Blocks open until ready.
  Future<Map<String, dynamic>?> enqueueReadingBookPregen({
    required String docId,
    required String text,
    required String voice,
    bool processOnEcs = false,
  }) async {
    final String spoken = text.trim();
    final String id = docId.trim();
    if (spoken.isEmpty || id.isEmpty) return null;
    try {
      final Response<dynamic> response = await _dio.post(
        Endpoints.readingSpeechBookPregen,
        data: <String, dynamic>{
          'doc_id': id,
          'text': spoken,
          'voice': voice.trim(),
          'language': 'en',
          'process_on_ecs': processOnEcs,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 60),
          extra: const <String, Object>{
            'dio_cache_interceptor_force_refresh': true,
          },
        ),
      );
      final Object? data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> readingBookPregenStatus({
    required String docId,
    required String voice,
  }) async {
    final String id = docId.trim();
    if (id.isEmpty) return null;
    try {
      final Response<dynamic> response = await _dio.get(
        Endpoints.readingSpeechBookPregen,
        queryParameters: <String, dynamic>{
          'doc_id': id,
          'voice': voice.trim(),
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 12),
          extra: const <String, Object>{
            'dio_cache_interceptor_force_refresh': true,
          },
        ),
      );
      final Object? data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> readingBookPregenFallback({
    required String docId,
    required String text,
    required String voice,
  }) async {
    final String id = docId.trim();
    if (id.isEmpty) return null;
    try {
      final Response<dynamic> response = await _dio.post(
        Endpoints.readingSpeechBookPregenFallback,
        data: <String, dynamic>{
          'doc_id': id,
          'text': text,
          'voice': voice.trim(),
          'language': 'en',
          'process_on_ecs': true,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 60),
          extra: const <String, Object>{
            'dio_cache_interceptor_force_refresh': true,
          },
        ),
      );
      final Object? data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Resolve / cache classic book jackets via Open Library on ECS.
  Future<Map<String, dynamic>?> ensureReadingCovers({
    List<Map<String, dynamic>> books = const <Map<String, dynamic>>[],
    bool seedClassics = false,
  }) async {
    try {
      final Response<dynamic> response = await _dio.post(
        Endpoints.readingCoversEnsure,
        data: <String, dynamic>{
          'books': books,
          'seed_classics': seedClassics,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 120),
          sendTimeout: const Duration(seconds: 30),
          extra: const <String, Object>{
            'dio_cache_interceptor_force_refresh': true,
          },
        ),
      );
      final Object? data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> resolveReadingCover({
    required String title,
    String author = '',
    String docId = '',
  }) async {
    try {
      final Response<dynamic> response = await _dio.get(
        Endpoints.readingCoversResolve,
        queryParameters: <String, dynamic>{
          'title': title.trim(),
          if (author.trim().isNotEmpty) 'author': author.trim(),
          if (docId.trim().isNotEmpty) 'doc_id': docId.trim(),
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 45),
          extra: const <String, Object>{
            'dio_cache_interceptor_force_refresh': true,
          },
        ),
      );
      final Object? data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<FoundationMediaItem?> contentMediaLookup({
    required String bookId,
    required String key,
    String namespace = 'reading',
  }) async {
    try {
      final Response<dynamic> response = await _dio.get(
        Endpoints.contentMediaLookup,
        queryParameters: <String, dynamic>{
          'namespace': namespace,
          'book_id': bookId,
          'key': key,
        },
      );
      final Object? data = response.data;
      if (data is Map<String, dynamic>) {
        return FoundationMediaItem.fromJson(data);
      }
      if (data is Map) {
        return FoundationMediaItem.fromJson(Map<String, dynamic>.from(data));
      }
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      rethrow;
    }
    return null;
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

  Options get _noCache => Options(
        extra: const <String, Object>{
          'dio_cache_interceptor_force_refresh': true,
        },
      );

  Future<List<CommunityPostDto>> communityFeed({
    String? kind,
    int? before,
    int? authorId,
    bool following = false,
    bool bookmarked = false,
    int limit = 40,
  }) async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.communityFeed,
      queryParameters: <String, dynamic>{
        if (kind != null && kind.isNotEmpty) 'kind': kind,
        if (before != null) 'before': before,
        if (authorId != null) 'author_id': authorId,
        if (following) 'following': true,
        if (bookmarked) 'bookmarked': true,
        'limit': limit,
      },
      options: _noCache,
    );
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(CommunityPostDto.fromJson)
        .toList(growable: false);
  }

  Future<CommunityPostDto> createCommunityPost({
    required String kind,
    String title = '',
    String body = '',
    String? linkUrl,
    String? linkTitle,
    String? linkCover,
    String? embedWord,
    double? embedTimestampSec,
    String? oralAudioUrl,
    String? oralBookId,
    String? oralKey,
    String? transcript,
    String? referenceLine,
    Map<String, dynamic>? meta,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.communityPosts,
      data: <String, dynamic>{
        'kind': kind,
        'title': title,
        'body': body,
        if (linkUrl != null) 'link_url': linkUrl,
        if (linkTitle != null) 'link_title': linkTitle,
        if (linkCover != null) 'link_cover': linkCover,
        if (embedWord != null && embedWord.trim().isNotEmpty)
          'embed_word': embedWord.trim(),
        if (embedTimestampSec != null)
          'embed_timestamp_sec': embedTimestampSec,
        if (oralAudioUrl != null && oralAudioUrl.trim().isNotEmpty)
          'oral_audio_url': oralAudioUrl.trim(),
        if (oralBookId != null && oralBookId.trim().isNotEmpty)
          'oral_book_id': oralBookId.trim(),
        if (oralKey != null && oralKey.trim().isNotEmpty)
          'oral_key': oralKey.trim(),
        if (transcript != null && transcript.trim().isNotEmpty)
          'transcript': transcript.trim(),
        if (referenceLine != null && referenceLine.trim().isNotEmpty)
          'reference_line': referenceLine.trim(),
        if (meta != null && meta.isNotEmpty) 'meta': meta,
      },
      options: _noCache,
    );
    return CommunityPostDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<CommunityPostDto> transcribeCommunityPost(int postId) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.communityPostTranscribe(postId),
      options: Options(
        extra: _noCache.extra,
        receiveTimeout: const Duration(minutes: 3),
      ),
    );
    return CommunityPostDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> uploadContentMedia({
    required List<int> bytes,
    required String filename,
    required String bookId,
    required String key,
    String namespace = 'oral',
  }) async {
    final FormData form = FormData.fromMap(<String, dynamic>{
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      'book_id': bookId,
      'key': key,
      'namespace': namespace,
    });
    final Response<dynamic> response = await _dio.post(
      Endpoints.contentMediaUpload,
      data: form,
      options: Options(
        extra: _noCache.extra,
        contentType: 'multipart/form-data',
        receiveTimeout: const Duration(minutes: 2),
        sendTimeout: const Duration(minutes: 2),
      ),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<CommunityPostDto> likeCommunityPost(int postId) async {
    final Response<dynamic> response = await _dio.post(
      '${Endpoints.communityPosts}/$postId/like',
      options: _noCache,
    );
    return CommunityPostDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<ExamAssetDto>> listExamAssets({
    String? familyId,
    String? kind,
    int limit = 40,
  }) async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.communityExamAssets,
      queryParameters: <String, dynamic>{
        if (familyId != null && familyId.isNotEmpty) 'family_id': familyId,
        if (kind != null && kind.isNotEmpty) 'kind': kind,
        'limit': limit,
      },
      options: _noCache,
    );
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(ExamAssetDto.fromJson)
        .toList(growable: false);
  }

  Future<ExamAssetDto> uploadExamAsset({
    required List<int> bytes,
    required String filename,
    required String familyId,
    required String title,
    String kind = 'other',
  }) async {
    final FormData form = FormData.fromMap(<String, dynamic>{
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      'family_id': familyId,
      'kind': kind,
      'title': title,
      'license_ack': '1',
      'meta_json': '{}',
    });
    final Response<dynamic> response = await _dio.post(
      Endpoints.communityExamAssets,
      data: form,
      options: Options(
        extra: _noCache.extra,
        contentType: 'multipart/form-data',
        receiveTimeout: const Duration(minutes: 2),
        sendTimeout: const Duration(minutes: 2),
      ),
    );
    return ExamAssetDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> reportExamAsset(int assetId, {required String reason}) async {
    await _dio.post(
      '${Endpoints.communityExamAssets}/$assetId/report',
      data: <String, dynamic>{'reason': reason},
      options: _noCache,
    );
  }

  Future<WritingGradeResult> gradeWriting({
    required String text,
    String prompt = '',
    String title = '',
    String rubric = 'generic',
    String familyId = '',
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.writingGrade,
      data: <String, dynamic>{
        'text': text,
        'prompt': prompt,
        'title': title,
        'rubric': rubric,
        'family_id': familyId,
      },
      options: Options(
        extra: _noCache.extra,
        receiveTimeout: const Duration(seconds: 90),
      ),
    );
    return WritingGradeResult.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<ExamPack> examPack(String familyId) async {
    final Response<dynamic> response = await _dio.get(
      '${Endpoints.examPacks}/$familyId',
      options: _noCache,
    );
    return ExamPack.fromJson(response.data as Map<String, dynamic>);
  }

  /// Push on-device API usage events to the server ledger (idempotent by event id).
  Future<void> syncApiUsageEvents(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) {
      return;
    }
    await _dio.post<dynamic>(
      Endpoints.usageEvents,
      data: <String, dynamic>{'events': events},
      options: _noCache,
    );
  }

  Future<void> upsertCommunityStudyStats({
    required String day,
    required int studySeconds,
    int? vocabCount,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      Endpoints.communityStudyStats,
      data: <String, dynamic>{
        'day': day,
        'study_seconds': studySeconds,
        if (vocabCount != null) 'vocab_count': vocabCount,
      },
      options: _noCache,
    );
  }

  Future<List<LeaderboardEntryDto>> communityLeaderboard({
    String metric = 'study_week',
  }) async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.communityLeaderboard,
      queryParameters: <String, dynamic>{'metric': metric},
      options: _noCache,
    );
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(LeaderboardEntryDto.fromJson)
        .toList(growable: false);
  }

  Future<CommunityPostDto> setCommunityLike(int postId, bool enabled) async {
    final Map<String, dynamic> data = await socialRequest('PUT', '/posts/$postId/like', data: <String, dynamic>{'enabled': enabled});
    return CommunityPostDto.fromJson(data);
  }

  Future<Map<String, dynamic>> moderationRequest(String method, String path, String token, {Map<String, dynamic>? data}) async {
    final Response<dynamic> response = await _dio.request<dynamic>('api/community-social/moderation$path', options: Options(method: method, headers: <String, String>{'X-Community-Admin-Token': token}, extra: _noCache.extra), data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> socialRequest(String method, String path, {Map<String, dynamic>? data}) async {
    final Response<dynamic> response = await _dio.request<dynamic>('api/community-social$path', options: Options(method: method, extra: _noCache.extra), data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> learningCardRequest(String method, String path, {Map<String, dynamic>? data}) async {
    final Response<dynamic> response = await _dio.request<dynamic>('api/learning-cards$path', options: Options(method: method, extra: _noCache.extra), data: data);
    final Map<String, dynamic> result = response.data as Map<String, dynamic>;
    if (result['public_path'] is String) result['share_url'] = Uri.parse(_dio.options.baseUrl).resolve(result['public_path'] as String).toString();
    return result;
  }

  Future<Map<String,dynamic>> assessmentStatus() async {
    final response = await _dio.get<dynamic>('api/pronunciation/status', options: _noCache);
    return response.data as Map<String,dynamic>;
  }
  Future<Map<String,dynamic>> evaluateRecording(String reference, String pcm) async {
    final response = await _dio.post<dynamic>('api/pronunciation/evaluate', data: {'reference':reference,'pcm_base64':pcm}, options: Options(receiveTimeout: const Duration(seconds:60)));
    return response.data as Map<String,dynamic>;
  }

  Future<Map<String, dynamic>> moduleProgress(String kind, {Map<String, dynamic>? upload}) async {
    final response = await _dio.request<dynamic>('api/learning-modules/$kind/progress', options: Options(method: upload == null ? 'GET' : 'PUT', extra: _noCache.extra), data: upload);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> studyPlayRequest(String method, String path, {Map<String, dynamic>? data}) async {
    final Response<dynamic> response = await _dio.request<dynamic>('api/study-play$path', options: Options(method: method, extra: _noCache.extra), data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> studyPkRequest(String method, String path, {Map<String, dynamic>? data}) async {
    final Response<dynamic> response = await _dio.request<dynamic>('api/study-pk$path', options: Options(method: method, extra: _noCache.extra), data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<void> reportChallengeEvent({
    required int postId,
    required String event,
  }) async {
    // Cafe challenge counters retired (API returns 410).
    try {
      await _dio.post(
        '${Endpoints.communityPosts}/$postId/challenge-event',
        data: <String, dynamic>{'event': event},
        options: _noCache,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 410) return;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> listCommunityPacks({
    String? cefr,
    String? topic,
    bool mine = false,
    bool recommend = false,
    String? learnerCefr,
  }) async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.communityPacks,
      queryParameters: <String, dynamic>{
        if (cefr != null && cefr.isNotEmpty) 'cefr': cefr,
        if (topic != null && topic.isNotEmpty) 'topic': topic,
        if (mine) 'mine': true,
        if (recommend) 'recommend': true,
        if (learnerCefr != null && learnerCefr.isNotEmpty)
          'learner_cefr': learnerCefr,
      },
      options: _noCache,
    );
    return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listCommunityGroups({
    bool mine = false,
  }) async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.communityGroups,
      queryParameters: <String, dynamic>{if (mine) 'mine': true},
      options: _noCache,
    );
    return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createCommunityGroup(
    Map<String, dynamic> body,
  ) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.communityGroups,
      data: body,
      options: _noCache,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> joinCommunityGroup(int groupId) async {
    final Response<dynamic> response = await _dio.post(
      '${Endpoints.communityGroups}/$groupId/join',
      options: _noCache,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listCommunityGroupTasks(int groupId) async {
    final Response<dynamic> response = await _dio.get(
      '${Endpoints.communityGroups}/$groupId/tasks',
      options: _noCache,
    );
    return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createCommunityGroupTask(
    int groupId,
    Map<String, dynamic> body,
  ) async {
    final Response<dynamic> response = await _dio.post(
      '${Endpoints.communityGroups}/$groupId/tasks',
      data: body,
      options: _noCache,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createCommunityPack(
    Map<String, dynamic> body,
  ) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.communityPacks,
      data: body,
      options: _noCache,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> forkCommunityPack(
    int packId, {
    bool syncUpstream = false,
    String? title,
  }) async {
    final Response<dynamic> response = await _dio.post(
      '${Endpoints.communityPacks}/$packId/fork',
      data: <String, dynamic>{
        'sync_upstream': syncUpstream,
        if (title != null && title.isNotEmpty) 'title': title,
      },
      options: _noCache,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> syncCommunityPackUpstream(int packId) async {
    final Response<dynamic> response = await _dio.post(
      '${Endpoints.communityPacks}/$packId/sync-upstream',
      options: _noCache,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> studyDeskRequest(String method, String path, {Map<String, dynamic>? data, Map<String, dynamic>? query}) async {
    final Response<dynamic> response = await _dio.request<dynamic>(
      'api/study-desk$path', options: Options(method: method, extra: _noCache.extra), data: data, queryParameters: query,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<List<SimilarUserDto>> communitySimilarUsers() async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.communitySimilarUsers,
      options: _noCache,
    );
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(SimilarUserDto.fromJson)
        .toList(growable: false);
  }

  Future<List<HotShareDto>> communityHotShares() async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.communityHotShares,
      options: _noCache,
    );
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(HotShareDto.fromJson)
        .toList(growable: false);
  }

  Future<List<HotCreatorDto>> communityHotCreators() async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.communityHotCreators,
      options: _noCache,
    );
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(HotCreatorDto.fromJson)
        .toList(growable: false);
  }

  Future<CommunityProfileDto> getCommunityProfile() async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.communityMe,
      options: _noCache,
    );
    return CommunityProfileDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<CommunityProfileDto> updateCommunityProfile({
    String? bio,
    bool? lookingForPartner,
    bool? showOnLeaderboard,
    String? englishLevel,
  }) async {
    final Response<dynamic> response = await _dio.put(
      Endpoints.communityMe,
      data: <String, dynamic>{
        if (bio != null) 'bio': bio,
        if (lookingForPartner != null)
          'looking_for_partner': lookingForPartner,
        if (showOnLeaderboard != null)
          'show_on_leaderboard': showOnLeaderboard,
        if (englishLevel != null) 'english_level': englishLevel,
      },
      options: _noCache,
    );
    return CommunityProfileDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<VocabPkDto> createVocabPk({required int opponentId}) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.communityPk,
      data: <String, dynamic>{'opponent_id': opponentId},
      options: _noCache,
    );
    return VocabPkDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<VocabPkDto> acceptVocabPk(int challengeId) async {
    final Response<dynamic> response = await _dio.post(
      '${Endpoints.communityPk}/$challengeId/accept',
      options: _noCache,
    );
    return VocabPkDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<VocabPkDto>> myVocabPkChallenges() async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.communityPkMine,
      options: _noCache,
    );
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(VocabPkDto.fromJson)
        .toList(growable: false);
  }

  Future<List<CommunityCommentDto>> communityComments(int postId) async {
    final Response<dynamic> response = await _dio.get(
      '${Endpoints.communityPosts}/$postId/comments',
      options: _noCache,
    );
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(CommunityCommentDto.fromJson)
        .toList(growable: false);
  }

  Future<CommunityCommentDto> createCommunityComment({
    required int postId,
    required String body,
    bool mirrorToBilibili = false,
  }) async {
    final Response<dynamic> response = await _dio.post(
      '${Endpoints.communityPosts}/$postId/comments',
      data: <String, dynamic>{
        'body': body,
        'mirror_to_bilibili': mirrorToBilibili,
      },
      options: _noCache,
    );
    return CommunityCommentDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> requestCommunityReclassify({
    required int postId,
    required String interestTag,
    required String englishLevel,
    String reason = '',
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '${Endpoints.communityPosts}/$postId/reclassify',
      data: <String, dynamic>{
        'interest_tag': interestTag,
        'english_level': englishLevel,
        'reason': reason,
      },
      options: _noCache,
    );
  }

  Future<AvatarMeDto> cosmeticsMe() async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.cosmeticsMe,
      options: _noCache,
    );
    return AvatarMeDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ReviewPointsEarnResult> earnReviewPoints({
    required String reason,
    required String clientEventId,
  }) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.cosmeticsEarn,
      data: <String, dynamic>{
        'reason': reason,
        'client_event_id': clientEventId,
      },
      options: _noCache,
    );
    return ReviewPointsEarnResult.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<AvatarMeDto> purchaseCosmetic(String sku) async {
    final Response<dynamic> response = await _dio.post(
      Endpoints.cosmeticsPurchase,
      data: <String, dynamic>{'sku': sku},
      options: _noCache,
    );
    return AvatarMeDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AvatarMeDto> equipCosmeticSet(Map<String, String> loadout) async {
    final Response<dynamic> response = await _dio.put<dynamic>('api/cosmetics/equip-set', data: <String, dynamic>{'loadout': loadout});
    return AvatarMeDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AvatarMeDto> equipCosmetic({
    required String slot,
    String? sku,
  }) async {
    final Response<dynamic> response = await _dio.put(
      Endpoints.cosmeticsEquip,
      data: <String, dynamic>{
        'slot': slot,
        'sku': sku,
      },
      options: _noCache,
    );
    return AvatarMeDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<({int wrongItemCount, int dueReviewCount})> learningSummary() async {
    final Response<dynamic> response = await _dio.get(
      Endpoints.learningSummary,
      options: _noCache,
    );
    final Map<String, dynamic> body = response.data as Map<String, dynamic>;
    return (
      wrongItemCount: (body['wrong_item_count'] as num?)?.toInt() ?? 0,
      dueReviewCount: (body['due_review_count'] as num?)?.toInt() ?? 0,
    );
  }
}
