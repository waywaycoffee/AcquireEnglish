/// ECS-hosted licensed textbook package (PDF + lesson audio).
class K12TextbookLesson {
  const K12TextbookLesson({
    required this.seq,
    required this.unitLabel,
    required this.kind,
    required this.title,
    required this.audioKey,
    required this.audioUrl,
    this.unit,
    this.lesson,
  });

  final int seq;
  final int? unit;
  final String unitLabel;
  final int? lesson;
  final String kind;
  final String title;
  final String audioKey;
  final String audioUrl;

  String get displayTitle {
    if (kind == 'letters') {
      return 'Letters and Sounds · $title';
    }
    if (lesson != null) {
      return 'Lesson $lesson · $title';
    }
    return title;
  }

  factory K12TextbookLesson.fromJson(Map<String, dynamic> json) =>
      K12TextbookLesson(
        seq: (json['seq'] as num?)?.toInt() ?? 0,
        unit: (json['unit'] as num?)?.toInt(),
        unitLabel: '${json['unit_label'] ?? ''}'.trim(),
        lesson: (json['lesson'] as num?)?.toInt(),
        kind: '${json['kind'] ?? 'lesson'}'.trim(),
        title: '${json['title'] ?? ''}'.trim(),
        audioKey: '${json['audio_key'] ?? ''}'.trim(),
        audioUrl: '${json['audio_url'] ?? ''}'.trim(),
      );
}

class K12TextbookMedia {
  const K12TextbookMedia({
    required this.bookId,
    required this.catalogId,
    required this.title,
    required this.titleZh,
    required this.edition,
    required this.publisher,
    required this.gradeId,
    required this.volume,
    required this.pdfUrl,
    required this.lessons,
    this.level = 'A1',
  });

  final String bookId;
  final String catalogId;
  final String title;
  final String titleZh;
  final String edition;
  final String publisher;
  final String gradeId;
  final String volume;
  final String level;
  final String pdfUrl;
  final List<K12TextbookLesson> lessons;

  String get displayTitle {
    final String zh = titleZh.trim();
    if (zh.isEmpty) return title;
    if (title.trim().isEmpty) return zh;
    return '$title（$zh）';
  }

  factory K12TextbookMedia.fromJson(Map<String, dynamic> json) {
    final List<K12TextbookLesson> lessons = <K12TextbookLesson>[];
    final Object? raw = json['lessons'];
    if (raw is List) {
      for (final Object? row in raw) {
        if (row is Map) {
          lessons.add(
            K12TextbookLesson.fromJson(Map<String, dynamic>.from(row)),
          );
        }
      }
    }
    return K12TextbookMedia(
      bookId: '${json['book_id'] ?? ''}'.trim(),
      catalogId: '${json['catalog_id'] ?? ''}'.trim(),
      title: '${json['title'] ?? ''}'.trim(),
      titleZh: '${json['title_zh'] ?? ''}'.trim(),
      edition: '${json['edition'] ?? ''}'.trim(),
      publisher: '${json['publisher'] ?? ''}'.trim(),
      gradeId: '${json['grade_id'] ?? ''}'.trim(),
      volume: '${json['volume'] ?? ''}'.trim(),
      level: '${json['level'] ?? 'A1'}'.trim(),
      pdfUrl: '${json['pdf_url'] ?? ''}'.trim(),
      lessons: List<K12TextbookLesson>.unmodifiable(lessons),
    );
  }
}

/// Stable ECS book_id for a catalog shelf entry, e.g. beijing-g4-b.
String? k12TextbookMediaBookId(String catalogId) {
  // k12-textbook:beijing:k12_g4:b → beijing-g4-b
  final List<String> parts = catalogId.split(':');
  if (parts.length < 4 || parts.first != 'k12-textbook') return null;
  final String edition = parts[1].trim();
  final String grade = parts[2].trim(); // k12_g4
  final String volume = parts[3].trim(); // a|b|full
  if (edition.isEmpty || grade.isEmpty || volume.isEmpty) return null;
  final String gradeShort = grade.replaceFirst(RegExp(r'^k12_'), '');
  return '$edition-$gradeShort-$volume';
}
