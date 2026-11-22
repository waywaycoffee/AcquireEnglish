import 'course_plan.dart';

class OralCoreLessonPack {
  const OralCoreLessonPack({
    this.targetPhrases = const <String>[],
    this.shadowLines = const <String>[],
    this.quiz = const <CourseQuizItem>[],
    this.discussPrompts = const <String>[],
  });

  factory OralCoreLessonPack.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const OralCoreLessonPack();
    return OralCoreLessonPack(
      targetPhrases: (json['target_phrases'] as List<dynamic>? ??
              json['targetPhrases'] as List<dynamic>? ??
              const <dynamic>[])
          .map((dynamic e) => '$e')
          .toList(growable: false),
      shadowLines: (json['shadow_lines'] as List<dynamic>? ??
              json['shadowLines'] as List<dynamic>? ??
              const <dynamic>[])
          .map((dynamic e) => '$e')
          .toList(growable: false),
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
    );
  }

  final List<String> targetPhrases;
  final List<String> shadowLines;
  final List<CourseQuizItem> quiz;
  final List<String> discussPrompts;
}

class OralCoreLesson {
  const OralCoreLesson({
    required this.lessonNo,
    required this.title,
    required this.bvid,
    required this.page,
    this.durationMs = 600000,
    this.topic = '',
    this.goal = '',
    this.subtitleEn = '',
    this.subtitleZh = '',
    this.pack = const OralCoreLessonPack(),
  });

  factory OralCoreLesson.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? media = json['media'] is Map
        ? Map<String, dynamic>.from(json['media'] as Map)
        : null;
    return OralCoreLesson(
      lessonNo: (json['lesson_no'] as num?)?.toInt() ??
          (json['lessonNo'] as num?)?.toInt() ??
          0,
      title: '${json['title'] ?? ''}',
      bvid: '${json['bvid'] ?? 'BV1CS4y1v7sQ'}',
      page: (json['page'] as num?)?.toInt() ?? 1,
      durationMs: (json['duration_ms'] as num?)?.toInt() ??
          (json['durationMs'] as num?)?.toInt() ??
          600000,
      topic: '${json['topic'] ?? json['title'] ?? ''}',
      goal: '${json['goal'] ?? ''}',
      subtitleEn: '${media?['subtitle_en'] ?? ''}',
      subtitleZh: '${media?['subtitle_zh'] ?? ''}',
      pack: OralCoreLessonPack.fromJson(
        json['pack'] is Map
            ? Map<String, dynamic>.from(json['pack'] as Map)
            : null,
      ),
    );
  }

  final int lessonNo;
  final String title;
  final String bvid;
  final int page;
  final int durationMs;
  final String topic;
  final String goal;
  final String subtitleEn;
  final String subtitleZh;
  final OralCoreLessonPack pack;

  String get unitId => 'l${lessonNo.toString().padLeft(2, '0')}';

  CourseUnit toCourseUnit() {
    final List<String> sentences = pack.shadowLines.isNotEmpty
        ? pack.shadowLines
        : pack.targetPhrases;
    return CourseUnit(
      unitId: unitId,
      startMs: 0,
      endMs: durationMs,
      sentences: sentences,
      wordIds: pack.targetPhrases
          .map((String p) => p.toLowerCase().replaceAll(' ', '_'))
          .toList(growable: false),
      topic: topic.isEmpty ? title : topic,
      episodeBvid: bvid,
      episodePage: page,
      goal: goal,
      quiz: pack.quiz,
      discussPrompts: pack.discussPrompts,
      shadowLines: pack.shadowLines,
      targetPhrases: pack.targetPhrases,
    );
  }
}

class OralCoreSeries {
  const OralCoreSeries({
    required this.seriesId,
    required this.title,
    required this.bvid,
    required this.pageCount,
    required this.lessons,
  });

  factory OralCoreSeries.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? source = json['source'] is Map
        ? Map<String, dynamic>.from(json['source'] as Map)
        : null;
    return OralCoreSeries(
      seriesId: '${json['series_id'] ?? json['seriesId'] ?? ''}',
      title: '${json['title'] ?? ''}',
      bvid: '${source?['bvid'] ?? 'BV1CS4y1v7sQ'}',
      pageCount: (source?['page_count'] as num?)?.toInt() ??
          (json['lessons'] as List<dynamic>?)?.length ??
          0,
      lessons: (json['lessons'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dynamic e) =>
                OralCoreLesson.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(growable: false),
    );
  }

  final String seriesId;
  final String title;
  final String bvid;
  final int pageCount;
  final List<OralCoreLesson> lessons;

  static const String kSeriesId = 'oral_core_9000';
  static const String kAssetPath = 'assets/courses/manifest.json';

  CoursePlan toCoursePlan({
    int dailyLessons = 1,
    bool quiz = true,
    bool oral = true,
    bool shadow = true,
  }) {
    return CoursePlan(
      courseId: kSeriesId,
      type: CoursePlanType.videoSeries,
      sourceId: kSeriesId,
      title: title,
      unitSize: dailyLessons,
      params: CoursePlanParams(
        dailyMinutes: 10,
        dailySentences: 20,
        dailyLessons: dailyLessons,
        practice: CoursePracticeParams(
          shadow: shadow,
          quiz: quiz,
          oral: oral,
        ),
      ),
      active: true,
      units: lessons.map((OralCoreLesson l) => l.toCourseUnit()).toList(),
      createdAt: DateTime.now(),
    );
  }
}
