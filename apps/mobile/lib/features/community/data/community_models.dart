class CommunityProfileDto {
  const CommunityProfileDto({
    required this.bio,
    required this.lookingForPartner,
    required this.showOnLeaderboard,
    required this.vocabCount,
    this.englishLevel,
  });

  factory CommunityProfileDto.fromJson(Map<String, dynamic> json) =>
      CommunityProfileDto(
        bio: (json['bio'] as String?) ?? '',
        lookingForPartner: json['looking_for_partner'] == true,
        showOnLeaderboard: json['show_on_leaderboard'] != false,
        englishLevel: json['english_level'] as String?,
        vocabCount: (json['vocab_count'] as num?)?.toInt() ?? 0,
      );

  final String bio;
  final bool lookingForPartner;
  final bool showOnLeaderboard;
  final String? englishLevel;
  final int vocabCount;
}

class CommunityPostDto {
  const CommunityPostDto({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.likeCount,
    required this.likedByMe,
    required this.authorName,
    required this.authorId,
    required this.createdAt,
    this.linkUrl,
    this.linkTitle,
    this.linkCover,
    this.authorLevel,
  });

  factory CommunityPostDto.fromJson(Map<String, dynamic> json) =>
      CommunityPostDto(
        id: json['id'] as int,
        kind: (json['kind'] as String?) ?? 'method',
        title: (json['title'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
        linkUrl: json['link_url'] as String?,
        linkTitle: json['link_title'] as String?,
        linkCover: json['link_cover'] as String?,
        likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
        likedByMe: json['liked_by_me'] == true,
        authorName: (json['author_name'] as String?) ?? '学员',
        authorId: (json['author_id'] as num?)?.toInt() ?? 0,
        authorLevel: json['author_level'] as String?,
        createdAt: DateTime.tryParse((json['created_at'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  final int id;
  final String kind;
  final String title;
  final String body;
  final String? linkUrl;
  final String? linkTitle;
  final String? linkCover;
  final int likeCount;
  final bool likedByMe;
  final String authorName;
  final int authorId;
  final String? authorLevel;
  final DateTime createdAt;

  bool get isShareLink => kind == 'share_link';
}

class LeaderboardEntryDto {
  const LeaderboardEntryDto({
    required this.rank,
    required this.userId,
    required this.displayName,
    required this.value,
    required this.isMe,
    this.englishLevel,
  });

  factory LeaderboardEntryDto.fromJson(Map<String, dynamic> json) =>
      LeaderboardEntryDto(
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        userId: (json['user_id'] as num?)?.toInt() ?? 0,
        displayName: (json['display_name'] as String?) ?? '学员',
        value: (json['value'] as num?)?.toInt() ?? 0,
        englishLevel: json['english_level'] as String?,
        isMe: json['is_me'] == true,
      );

  final int rank;
  final int userId;
  final String displayName;
  final int value;
  final String? englishLevel;
  final bool isMe;
}

class SimilarUserDto {
  const SimilarUserDto({
    required this.userId,
    required this.displayName,
    required this.sharedTags,
    required this.lookingForPartner,
    required this.vocabCount,
    required this.overlapScore,
    this.englishLevel,
  });

  factory SimilarUserDto.fromJson(Map<String, dynamic> json) => SimilarUserDto(
        userId: (json['user_id'] as num?)?.toInt() ?? 0,
        displayName: (json['display_name'] as String?) ?? '学员',
        englishLevel: json['english_level'] as String?,
        sharedTags: ((json['shared_tags'] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList(growable: false),
        lookingForPartner: json['looking_for_partner'] == true,
        vocabCount: (json['vocab_count'] as num?)?.toInt() ?? 0,
        overlapScore: (json['overlap_score'] as num?)?.toInt() ?? 0,
      );

  final int userId;
  final String displayName;
  final String? englishLevel;
  final List<String> sharedTags;
  final bool lookingForPartner;
  final int vocabCount;
  final int overlapScore;
}

class HotShareDto {
  const HotShareDto({
    required this.linkUrl,
    required this.shareCount,
    this.linkTitle,
    this.linkCover,
    this.latestBody,
  });

  factory HotShareDto.fromJson(Map<String, dynamic> json) => HotShareDto(
        linkUrl: (json['link_url'] as String?) ?? '',
        linkTitle: json['link_title'] as String?,
        linkCover: json['link_cover'] as String?,
        shareCount: (json['share_count'] as num?)?.toInt() ?? 0,
        latestBody: json['latest_body'] as String?,
      );

  final String linkUrl;
  final String? linkTitle;
  final String? linkCover;
  final int shareCount;
  final String? latestBody;
}

class HotCreatorDto {
  const HotCreatorDto({
    required this.source,
    required this.creatorId,
    required this.displayName,
    required this.followerCount,
    this.profileUrl,
  });

  factory HotCreatorDto.fromJson(Map<String, dynamic> json) => HotCreatorDto(
        source: (json['source'] as String?) ?? 'bilibili',
        creatorId: (json['creator_id'] as String?) ?? '',
        displayName: (json['display_name'] as String?) ?? '',
        profileUrl: json['profile_url'] as String?,
        followerCount: (json['follower_count'] as num?)?.toInt() ?? 0,
      );

  final String source;
  final String creatorId;
  final String displayName;
  final String? profileUrl;
  final int followerCount;
}

class VocabPkDto {
  const VocabPkDto({
    required this.id,
    required this.status,
    required this.challengerId,
    required this.challengerName,
    required this.opponentId,
    required this.opponentName,
    required this.challengerVocab,
    required this.opponentVocab,
    required this.createdAt,
    this.winnerId,
    this.iAmOpponent = false,
    this.iAmChallenger = false,
  });

  factory VocabPkDto.fromJson(Map<String, dynamic> json) => VocabPkDto(
        id: json['id'] as int,
        status: (json['status'] as String?) ?? 'pending',
        challengerId: (json['challenger_id'] as num?)?.toInt() ?? 0,
        challengerName: (json['challenger_name'] as String?) ?? '学员',
        opponentId: (json['opponent_id'] as num?)?.toInt() ?? 0,
        opponentName: (json['opponent_name'] as String?) ?? '学员',
        challengerVocab: (json['challenger_vocab'] as num?)?.toInt() ?? 0,
        opponentVocab: (json['opponent_vocab'] as num?)?.toInt() ?? 0,
        winnerId: (json['winner_id'] as num?)?.toInt(),
        createdAt: DateTime.tryParse((json['created_at'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        iAmOpponent: json['i_am_opponent'] == true,
        iAmChallenger: json['i_am_challenger'] == true,
      );

  final int id;
  final String status;
  final int challengerId;
  final String challengerName;
  final int opponentId;
  final String opponentName;
  final int challengerVocab;
  final int opponentVocab;
  final int? winnerId;
  final DateTime createdAt;
  final bool iAmOpponent;
  final bool iAmChallenger;
}
