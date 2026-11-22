/// Local course plan for PRD Ch7「当日课程化」(client-side scheduling).

enum CoursePlanType { video, reading, videoSeries }

class CoursePracticeParams {
  const CoursePracticeParams({
    this.shadow = true,
    this.quiz = false,
    this.oral = false,
  });

  factory CoursePracticeParams.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const CoursePracticeParams();
    return CoursePracticeParams(
      shadow: json['shadow'] as bool? ?? true,
      quiz: json['quiz'] as bool? ?? false,
      oral: json['oral'] as bool? ?? false,
    );
  }

  final bool shadow;
  final bool quiz;
  final bool oral;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'shadow': shadow,
        'quiz': quiz,
        'oral': oral,
      };
}

class CoursePlanParams {
  const CoursePlanParams({
    this.dailyMinutes = 10,
    this.dailySentences = 20,
    this.dailyLessons = 1,
    this.practice = const CoursePracticeParams(),
  });

  factory CoursePlanParams.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const CoursePlanParams();
    return CoursePlanParams(
      dailyMinutes: (json['dailyMinutes'] as num?)?.toInt() ?? 10,
      dailySentences: (json['dailySentences'] as num?)?.toInt() ?? 20,
      dailyLessons: ((json['dailyLessons'] as num?)?.toInt() ?? 1).clamp(1, 10),
      practice: CoursePracticeParams.fromJson(
        json['practice'] is Map
            ? Map<String, dynamic>.from(json['practice'] as Map)
            : null,
      ),
    );
  }

  final int dailyMinutes;
  final int dailySentences;

  /// How many new course units to schedule today (user-configurable).
  final int dailyLessons;
  final CoursePracticeParams practice;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'dailyMinutes': dailyMinutes,
        'dailySentences': dailySentences,
        'dailyLessons': dailyLessons,
        'practice': practice.toJson(),
      };

  CoursePlanParams copyWith({
    int? dailyMinutes,
    int? dailySentences,
    int? dailyLessons,
    CoursePracticeParams? practice,
  }) =>
      CoursePlanParams(
        dailyMinutes: dailyMinutes ?? this.dailyMinutes,
        dailySentences: dailySentences ?? this.dailySentences,
        dailyLessons: dailyLessons ?? this.dailyLessons,
        practice: practice ?? this.practice,
      );
}

/// Inclusive sentence index range [start, endExclusive) stored as [start, end].
class SentenceRange {
  const SentenceRange(this.start, this.end);

  final int start;
  final int end;

  List<int> toJsonList() => <int>[start, end];

  static SentenceRange? fromJsonList(List<dynamic>? raw) {
    if (raw == null || raw.length < 2) return null;
    return SentenceRange((raw[0] as num).toInt(), (raw[1] as num).toInt());
  }
}

class CourseQuizItem {
  const CourseQuizItem({
    required this.type,
    required this.stem,
    required this.options,
    required this.answer,
    this.explanation,
    this.evidenceSentenceIndex,
  });

  factory CourseQuizItem.fromJson(Map<String, dynamic> json) => CourseQuizItem(
        type: '${json['type'] ?? 'mcq'}',
        stem: '${json['stem'] ?? ''}',
        options: (json['options'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic e) => '$e')
            .toList(growable: false),
        answer: (json['answer'] as num?)?.toInt() ?? 0,
        explanation: json['explanation'] as String?,
        evidenceSentenceIndex: (json['evidence_sentence_index'] as num?)?.toInt(),
      );

  final String type;
  final String stem;
  final List<String> options;
  final int answer;
  final String? explanation;
  final int? evidenceSentenceIndex;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        'stem': stem,
        'options': options,
        'answer': answer,
        if (explanation != null) 'explanation': explanation,
        if (evidenceSentenceIndex != null)
          'evidence_sentence_index': evidenceSentenceIndex,
      };
}

class CourseUnit {
  const CourseUnit({
    required this.unitId,
    this.startMs,
    this.endMs,
    this.sentenceRange,
    this.sentences = const <String>[],
    this.wordIds = const <String>[],
    this.topic = '',
    this.reviewInterval = const <int>[1, 3, 7, 14],
    this.firstLearnedAt,
    this.nextDue,
    this.reviewStage = 0,
    this.episodeBvid,
    this.episodePage,
    this.goal = '',
    this.quiz = const <CourseQuizItem>[],
    this.discussPrompts = const <String>[],
    this.shadowLines = const <String>[],
    this.targetPhrases = const <String>[],
  });

  factory CourseUnit.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? ep = json['episode_ref'] is Map
        ? Map<String, dynamic>.from(json['episode_ref'] as Map)
        : (json['episodeRef'] is Map
            ? Map<String, dynamic>.from(json['episodeRef'] as Map)
            : null);
    return CourseUnit(
      unitId: '${json['unit_id'] ?? json['unitId'] ?? ''}',
      startMs: (json['start_ms'] as num?)?.toInt() ??
          (json['startMs'] as num?)?.toInt(),
      endMs:
          (json['end_ms'] as num?)?.toInt() ?? (json['endMs'] as num?)?.toInt(),
      sentenceRange: SentenceRange.fromJsonList(
        json['sentence_range'] as List<dynamic>? ??
            json['sentenceRange'] as List<dynamic>?,
      ),
      sentences: (json['sentences'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic e) => '$e')
          .toList(growable: false),
      wordIds: (json['word_ids'] as List<dynamic>? ??
              json['wordIds'] as List<dynamic>? ??
              const <dynamic>[])
          .map((dynamic e) => '$e')
          .toList(growable: false),
      topic: '${json['topic'] ?? ''}',
      reviewInterval: (json['review_interval'] as List<dynamic>? ??
              json['reviewInterval'] as List<dynamic>? ??
              const <dynamic>[1, 3, 7, 14])
          .map((dynamic e) => (e as num).toInt())
          .toList(growable: false),
      firstLearnedAt:
          _parseDate(json['first_learned_at'] ?? json['firstLearnedAt']),
      nextDue: _parseDate(json['next_due'] ?? json['nextDue']),
      reviewStage: (json['review_stage'] as num?)?.toInt() ??
          (json['reviewStage'] as num?)?.toInt() ??
          0,
      episodeBvid: ep == null
          ? (json['episode_bvid'] as String? ?? json['episodeBvid'] as String?)
          : '${ep['bvid'] ?? ''}',
      episodePage: ep == null
          ? ((json['episode_page'] as num?)?.toInt() ??
              (json['episodePage'] as num?)?.toInt())
          : (ep['page'] as num?)?.toInt(),
      goal: '${json['goal'] ?? ''}',
      quiz: (json['quiz'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dynamic e) =>
                CourseQuizItem.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(growable: false),
      discussPrompts: (json['discuss_prompts'] as List<dynamic>? ??
              json['discussPrompts'] as List<dynamic>? ??
              const <dynamic>[])
          .map((dynamic e) => '$e')
          .toList(growable: false),
      shadowLines: (json['shadow_lines'] as List<dynamic>? ??
              json['shadowLines'] as List<dynamic>? ??
              const <dynamic>[])
          .map((dynamic e) => '$e')
          .toList(growable: false),
      targetPhrases: (json['target_phrases'] as List<dynamic>? ??
              json['targetPhrases'] as List<dynamic>? ??
              const <dynamic>[])
          .map((dynamic e) => '$e')
          .toList(growable: false),
    );
  }

  final String unitId;
  final int? startMs;
  final int? endMs;
  final SentenceRange? sentenceRange;
  final List<String> sentences;
  final List<String> wordIds;
  final String topic;
  final List<int> reviewInterval;
  final DateTime? firstLearnedAt;
  final DateTime? nextDue;
  final int reviewStage;
  final String? episodeBvid;
  final int? episodePage;
  final String goal;
  final List<CourseQuizItem> quiz;
  final List<String> discussPrompts;
  final List<String> shadowLines;
  final List<String> targetPhrases;

  bool get isLearned => firstLearnedAt != null;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'unit_id': unitId,
        if (startMs != null) 'start_ms': startMs,
        if (endMs != null) 'end_ms': endMs,
        if (sentenceRange != null)
          'sentence_range': sentenceRange!.toJsonList(),
        'sentences': sentences,
        'word_ids': wordIds,
        'topic': topic,
        'review_interval': reviewInterval,
        'first_learned_at': firstLearnedAt?.toIso8601String(),
        'next_due': nextDue?.toIso8601String(),
        'review_stage': reviewStage,
        if (episodeBvid != null || episodePage != null)
          'episode_ref': <String, Object?>{
            if (episodeBvid != null) 'bvid': episodeBvid,
            if (episodePage != null) 'page': episodePage,
          },
        'goal': goal,
        'quiz': quiz.map((CourseQuizItem q) => q.toJson()).toList(),
        'discuss_prompts': discussPrompts,
        'shadow_lines': shadowLines,
        'target_phrases': targetPhrases,
      };

  CourseUnit copyWith({
    DateTime? firstLearnedAt,
    DateTime? nextDue,
    int? reviewStage,
    bool clearNextDue = false,
  }) =>
      CourseUnit(
        unitId: unitId,
        startMs: startMs,
        endMs: endMs,
        sentenceRange: sentenceRange,
        sentences: sentences,
        wordIds: wordIds,
        topic: topic,
        reviewInterval: reviewInterval,
        firstLearnedAt: firstLearnedAt ?? this.firstLearnedAt,
        nextDue: clearNextDue ? null : (nextDue ?? this.nextDue),
        reviewStage: reviewStage ?? this.reviewStage,
        episodeBvid: episodeBvid,
        episodePage: episodePage,
        goal: goal,
        quiz: quiz,
        discussPrompts: discussPrompts,
        shadowLines: shadowLines,
        targetPhrases: targetPhrases,
      );

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    final String s = '$raw'.trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}

CoursePlanType _parsePlanType(String raw) {
  switch (raw) {
    case 'video':
      return CoursePlanType.video;
    case 'video_series':
    case 'videoSeries':
      return CoursePlanType.videoSeries;
    default:
      return CoursePlanType.reading;
  }
}

String _planTypeToJson(CoursePlanType type) {
  switch (type) {
    case CoursePlanType.video:
      return 'video';
    case CoursePlanType.videoSeries:
      return 'video_series';
    case CoursePlanType.reading:
      return 'reading';
  }
}

class CoursePlan {
  const CoursePlan({
    required this.courseId,
    required this.type,
    required this.sourceId,
    required this.title,
    this.unitSize = 600,
    this.params = const CoursePlanParams(),
    this.active = true,
    this.units = const <CourseUnit>[],
    this.createdAt,
    this.stoppedAdding = false,
  });

  factory CoursePlan.fromJson(Map<String, dynamic> json) {
    final String typeRaw = '${json['type'] ?? 'reading'}';
    return CoursePlan(
      courseId: '${json['course_id'] ?? json['courseId'] ?? ''}',
      type: _parsePlanType(typeRaw),
      sourceId: '${json['source_id'] ?? json['sourceId'] ?? ''}',
      title: '${json['title'] ?? ''}',
      unitSize: (json['unit_size'] as num?)?.toInt() ??
          (json['unitSize'] as num?)?.toInt() ??
          600,
      params: CoursePlanParams.fromJson(
        json['params'] is Map
            ? Map<String, dynamic>.from(json['params'] as Map)
            : null,
      ),
      active: json['active'] as bool? ?? true,
      units: (json['units'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dynamic e) =>
                CourseUnit.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(growable: false),
      createdAt: CourseUnit._parseDate(json['created_at'] ?? json['createdAt']),
      stoppedAdding: json['stopped_adding'] as bool? ??
          json['stoppedAdding'] as bool? ??
          false,
    );
  }

  final String courseId;
  final CoursePlanType type;
  final String sourceId;
  final String title;
  final int unitSize;
  final CoursePlanParams params;
  final bool active;
  final List<CourseUnit> units;
  final DateTime? createdAt;
  final bool stoppedAdding;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'course_id': courseId,
        'type': _planTypeToJson(type),
        'source_id': sourceId,
        'title': title,
        'unit_size': unitSize,
        'params': params.toJson(),
        'active': active,
        'units': units.map((CourseUnit u) => u.toJson()).toList(),
        'created_at': createdAt?.toIso8601String(),
        'stopped_adding': stoppedAdding,
      };

  CoursePlan copyWith({
    bool? active,
    List<CourseUnit>? units,
    bool? stoppedAdding,
    CoursePlanParams? params,
    String? title,
    int? unitSize,
  }) =>
      CoursePlan(
        courseId: courseId,
        type: type,
        sourceId: sourceId,
        title: title ?? this.title,
        unitSize: unitSize ?? this.unitSize,
        params: params ?? this.params,
        active: active ?? this.active,
        units: units ?? this.units,
        createdAt: createdAt,
        stoppedAdding: stoppedAdding ?? this.stoppedAdding,
      );

  CourseUnit? unitById(String id) {
    for (final CourseUnit u in units) {
      if (u.unitId == id) return u;
    }
    return null;
  }
}
