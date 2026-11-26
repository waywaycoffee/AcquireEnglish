import 'reading_title_zh.dart';

enum ReadingSourceType { import, builtin, video, catalog }

class ReadingSegment {
  const ReadingSegment({required this.text, this.startMs, this.endMs});

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
    this.titleZh = '',
    this.level = '',
    this.segments = const <ReadingSegment>[],
    this.courseId,
    this.episodeId,
    this.courseTitle = '',
    this.episodeTitle = '',
    this.sourceLabel = '',
    this.coverUrl = '',
    this.createdAt,
    this.builtin = false,
    this.contentHash,
    this.netdiskPath = '',
  });

  final String id;
  final String title;

  /// Optional Chinese title (e.g. 绿野仙踪). Display via [displayTitle].
  final String titleZh;
  final ReadingSourceType sourceType;
  final String level;
  final String plainText;
  final List<ReadingSegment> segments;
  final String? courseId;
  final String? episodeId;
  final String courseTitle;
  final String episodeTitle;
  final String sourceLabel;

  /// ECS-cached classic cover (`/media/reading/covers/...`), optional.
  final String coverUrl;
  final DateTime? createdAt;
  final bool builtin;

  /// sha256 of original plainText when body was stripped for cloud size limits.
  final String? contentHash;

  /// Absolute path on the user's bound Baidu drive. Empty for other sources.
  final String netdiskPath;

  /// Best-effort author for cover search (catalog stores it in [episodeTitle]).
  String get authorHint {
    final String fromEpisode = episodeTitle.trim();
    if (fromEpisode.isNotEmpty &&
        !fromEpisode.contains('http') &&
        fromEpisode.length < 80) {
      // "L. Frank Baum · 公版奇幻长篇" → author only
      final int cut = fromEpisode.indexOf('·');
      if (cut > 0) return fromEpisode.substring(0, cut).trim();
      return fromEpisode;
    }
    return '';
  }

  /// `The Wonderful Wizard of Oz（绿野仙踪）`
  String get displayTitle => readingDisplayTitle(title, titleZh: titleZh);

  /// Fill missing Chinese titles for already-saved library docs.
  ReadingDoc withEnrichedTitle() {
    final String zh = readingTitleZhFor(title, titleZh: titleZh) ?? '';
    final String display = readingDisplayTitle(title, titleZh: zh);
    if (zh == titleZh.trim() && display == title.trim()) return this;
    return copyWith(title: display, titleZh: zh);
  }

  bool get hasBody => plainText.trim().isNotEmpty;

  int get wordCount {
    final Iterable<String> parts = plainText
        .split(RegExp(r"\s+"))
        .where((String w) => w.trim().isNotEmpty);
    return parts.length;
  }

  ReadingDoc copyWith({
    String? plainText,
    String? title,
    String? titleZh,
    List<ReadingSegment>? segments,
    String? coverUrl,
    String? contentHash,
    bool clearContentHash = false,
    String? netdiskPath,
  }) => ReadingDoc(
    id: id,
    title: title ?? this.title,
    titleZh: titleZh ?? this.titleZh,
    sourceType: sourceType,
    level: level,
    plainText: plainText ?? this.plainText,
    segments: segments ?? this.segments,
    courseId: courseId,
    episodeId: episodeId,
    courseTitle: courseTitle,
    episodeTitle: episodeTitle,
    sourceLabel: sourceLabel,
    coverUrl: coverUrl ?? this.coverUrl,
    createdAt: createdAt,
    builtin: builtin,
    contentHash: clearContentHash ? null : (contentHash ?? this.contentHash),
    netdiskPath: netdiskPath ?? this.netdiskPath,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    if (titleZh.trim().isNotEmpty) 'titleZh': titleZh,
    'sourceType': sourceType.name,
    'level': level,
    'plainText': plainText,
    'segments': segments.map((ReadingSegment s) => s.toJson()).toList(),
    'courseId': courseId,
    'episodeId': episodeId,
    'courseTitle': courseTitle,
    'episodeTitle': episodeTitle,
    'sourceLabel': sourceLabel,
    if (coverUrl.trim().isNotEmpty) 'coverUrl': coverUrl,
    'createdAt': createdAt?.toIso8601String(),
    'builtin': builtin,
    if (contentHash != null && contentHash!.isNotEmpty)
      'contentHash': contentHash,
    if (netdiskPath.trim().isNotEmpty) 'netdiskPath': netdiskPath.trim(),
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
    final String? hash = (json['contentHash'] as String?)?.trim();
    return ReadingDoc(
      id: '${json['id'] ?? ''}'.trim(),
      title: '${json['title'] ?? ''}'.trim(),
      titleZh: '${json['titleZh'] ?? ''}'.trim(),
      sourceType: sourceType,
      level: '${json['level'] ?? ''}'.trim(),
      plainText: '${json['plainText'] ?? ''}',
      segments: List<ReadingSegment>.unmodifiable(segments),
      courseId: (json['courseId'] as String?)?.trim(),
      episodeId: (json['episodeId'] as String?)?.trim(),
      courseTitle: '${json['courseTitle'] ?? ''}'.trim(),
      episodeTitle: '${json['episodeTitle'] ?? ''}'.trim(),
      sourceLabel: '${json['sourceLabel'] ?? ''}'.trim(),
      coverUrl: '${json['coverUrl'] ?? json['cover_url'] ?? ''}'.trim(),
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
      builtin: json['builtin'] as bool? ?? builtin,
      contentHash: (hash == null || hash.isEmpty) ? null : hash,
      netdiskPath: '${json['netdiskPath'] ?? ''}'.trim(),
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

/// Soft quota hooks for membership / free-tier personal libraries.
/// Free promise: personal reading uploads stay ≥15 (default headroom 50).
class ReadingQuota {
  const ReadingQuota({this.maxImportDocs = 50, this.maxVideoDocs = 30});

  final int maxImportDocs;
  final int maxVideoDocs;

  bool canImport(int currentImportCount) => currentImportCount < maxImportDocs;

  bool canGenerateFromVideo(int currentVideoCount) =>
      currentVideoCount < maxVideoDocs;
}
