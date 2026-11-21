import 'daily_review.dart';

/// Catalog entries that are not owned by 单词本 / 短语库 / 词书.
///
/// Keys:
/// - `clip:{episodeId}:{startMs}:{endMs}:{slug}`
/// - `skill:cafe:{levelIndex}`
class MemoryItem {
  const MemoryItem({
    required this.key,
    required this.kind,
    required this.question,
    required this.answer,
    required this.english,
    required this.chinese,
    required this.sourceLabel,
    this.episodeId,
    this.time,
    this.startMs,
    this.endMs,
    this.skillChapter,
    this.skillLevel,
    this.origin = 'manual',
    this.createdAtMs,
  });

  factory MemoryItem.fromJson(Map<String, dynamic> json) => MemoryItem(
        key: json['key'] as String,
        kind: ReviewKind.values.firstWhere(
          (ReviewKind k) => k.name == (json['kind'] as String? ?? 'clip'),
          orElse: () => ReviewKind.clip,
        ),
        question: json['question'] as String? ?? '',
        answer: json['answer'] as String? ?? '',
        english: json['english'] as String? ?? '',
        chinese: json['chinese'] as String? ?? '',
        sourceLabel: json['sourceLabel'] as String? ?? '',
        episodeId: json['episodeId'] as String?,
        time: json['time'] as String?,
        startMs: (json['startMs'] as num?)?.toInt(),
        endMs: (json['endMs'] as num?)?.toInt(),
        skillChapter: json['skillChapter'] as String?,
        skillLevel: (json['skillLevel'] as num?)?.toInt(),
        origin: json['origin'] as String? ?? 'manual',
        createdAtMs: (json['createdAtMs'] as num?)?.toInt(),
      );

  final String key;
  final ReviewKind kind;
  final String question;
  final String answer;
  final String english;
  final String chinese;
  final String sourceLabel;
  final String? episodeId;
  final String? time;
  final int? startMs;
  final int? endMs;
  final String? skillChapter;
  final int? skillLevel;

  /// dictation | shadowing | cafe | manual
  final String origin;
  final int? createdAtMs;

  ReviewSource toSource() => ReviewSource(
        key: key,
        kind: kind,
        question: question,
        answer: answer,
        english: english,
        chinese: chinese,
        sourceLabel: sourceLabel,
        episodeId: episodeId,
        time: time,
        startMs: startMs,
        endMs: endMs,
        skillChapter: skillChapter,
        skillLevel: skillLevel,
        origin: origin,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'kind': kind.name,
        'question': question,
        'answer': answer,
        'english': english,
        'chinese': chinese,
        'sourceLabel': sourceLabel,
        'episodeId': episodeId,
        'time': time,
        'startMs': startMs,
        'endMs': endMs,
        'skillChapter': skillChapter,
        'skillLevel': skillLevel,
        'origin': origin,
        'createdAtMs': createdAtMs,
      };

  static String clipKey({
    required String episodeId,
    required int startMs,
    required int endMs,
    required String english,
  }) {
    final String slug = english
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim()
        .replaceAll(RegExp(r'^_|_$'), '');
    final String short = slug.length <= 24 ? slug : slug.substring(0, 24);
    return 'clip:$episodeId:$startMs:$endMs:$short';
  }

  static String cafeSkillKey(int levelIndex) => 'skill:cafe:$levelIndex';
}
