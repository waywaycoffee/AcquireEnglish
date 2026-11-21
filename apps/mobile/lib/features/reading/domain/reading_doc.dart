enum ReadingSourceType { import, builtin, video, catalog }

class ReadingSegment {
  const ReadingSegment({
    required this.text,
    this.startMs,
    this.endMs,
  });

  final String text;
  final int? startMs;
  final int? endMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    if (startMs != null) 'startMs': startMs,
    if (endMs != null) 'endMs': endMs,
  };

  factory ReadingSegment.fromJson(Map<String, dynamic> json) => ReadingSegment(
    text: '${json['text'] ?? ''}',
    startMs: (json['startMs'] as num?)?.toInt(),
    endMs: (json['endMs'] as num?)?.toInt(),
  );
}

class ReadingDoc {
  const ReadingDoc({
    required this.id,
    required this.title,
    required this.sourceType,
    required this.plainText,
    this.level = '',
    this.segments = const <ReadingSegment>[],
    this.courseId,
    this.episodeId,
    this.courseTitle = '',
    this.episodeTitle = '',
    this.sourceLabel = '',
    this.createdAt,
    this.builtin = false,
  });

  final String id;
  final String title;
  final ReadingSourceType sourceType;
  final String level;
  final String plainText;
  final List<ReadingSegment> segments;
  final String? courseId;
  final String? episodeId;
  final String courseTitle;
  final String episodeTitle;
  final String sourceLabel;
  final DateTime? createdAt;
  final bool builtin;

  int get wordCount {
    final Iterable<String> parts = plainText
        .split(RegExp(r"\s+"))
        .where((String w) => w.trim().isNotEmpty);
    return parts.length;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'sourceType': sourceType.name,
    'level': level,
    'plainText': plainText,
    'segments': segments.map((ReadingSegment s) => s.toJson()).toList(),
    'courseId': courseId,
    'episodeId': episodeId,
    'courseTitle': courseTitle,
    'episodeTitle': episodeTitle,
    'sourceLabel': sourceLabel,
    'createdAt': createdAt?.toIso8601String(),
    'builtin': builtin,
  };

  factory ReadingDoc.fromJson(
    Map<String, dynamic> json, {
    bool builtin = false,
  }) {
    final List<ReadingSegment> segments = <ReadingSegment>[];
    final Object? rawSegs = json['segments'];
    if (rawSegs is List) {
      for (final Object? item in rawSegs) {
        if (item is Map) {
          segments.add(
            ReadingSegment.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    final String sourceName = '${json['sourceType'] ?? 'import'}';
    final ReadingSourceType sourceType = ReadingSourceType.values.firstWhere(
      (ReadingSourceType t) => t.name == sourceName,
      orElse: () => ReadingSourceType.import,
    );
    return ReadingDoc(
      id: '${json['id'] ?? ''}'.trim(),
      title: '${json['title'] ?? ''}'.trim(),
      sourceType: sourceType,
      level: '${json['level'] ?? ''}'.trim(),
      plainText: '${json['plainText'] ?? ''}',
      segments: List<ReadingSegment>.unmodifiable(segments),
      courseId: (json['courseId'] as String?)?.trim(),
      episodeId: (json['episodeId'] as String?)?.trim(),
      courseTitle: '${json['courseTitle'] ?? ''}'.trim(),
      episodeTitle: '${json['episodeTitle'] ?? ''}'.trim(),
      sourceLabel: '${json['sourceLabel'] ?? ''}'.trim(),
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
      builtin: json['builtin'] as bool? ?? builtin,
    );
  }
}

class ReadingProgress {
  const ReadingProgress({
    required this.docId,
    this.offsetChars = 0,
    this.percent = 0,
    this.lastOpenedAt,
    this.completed = false,
  });

  final String docId;
  final int offsetChars;
  final double percent;
  final DateTime? lastOpenedAt;
  final bool completed;

  ReadingProgress copyWith({
    int? offsetChars,
    double? percent,
    DateTime? lastOpenedAt,
    bool? completed,
  }) => ReadingProgress(
    docId: docId,
    offsetChars: offsetChars ?? this.offsetChars,
    percent: percent ?? this.percent,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    completed: completed ?? this.completed,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'docId': docId,
    'offsetChars': offsetChars,
    'percent': percent,
    'lastOpenedAt': lastOpenedAt?.toIso8601String(),
    'completed': completed,
  };

  factory ReadingProgress.fromJson(Map<String, dynamic> json) =>
      ReadingProgress(
        docId: '${json['docId'] ?? ''}',
        offsetChars: (json['offsetChars'] as num?)?.toInt() ?? 0,
        percent: (json['percent'] as num?)?.toDouble() ?? 0,
        lastOpenedAt: DateTime.tryParse('${json['lastOpenedAt'] ?? ''}'),
        completed: json['completed'] as bool? ?? false,
      );
}

/// Soft quota hooks for later membership SKUs.
class ReadingQuota {
  const ReadingQuota({
    this.maxImportDocs = 50,
    this.maxVideoDocs = 30,
  });

  final int maxImportDocs;
  final int maxVideoDocs;

  bool canImport(int currentImportCount) => currentImportCount < maxImportDocs;

  bool canGenerateFromVideo(int currentVideoCount) =>
      currentVideoCount < maxVideoDocs;
}
