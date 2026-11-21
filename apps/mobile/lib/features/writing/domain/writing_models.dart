class WritingDraft {
  const WritingDraft({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAtMs,
    this.prompt = '',
  });

  factory WritingDraft.fromJson(Map<String, dynamic> json) => WritingDraft(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        body: '${json['body'] ?? ''}',
        prompt: '${json['prompt'] ?? ''}',
        updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String title;
  final String body;
  final String prompt;
  final int updatedAtMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'body': body,
        'prompt': prompt,
        'updatedAtMs': updatedAtMs,
      };

  WritingDraft copyWith({
    String? title,
    String? body,
    String? prompt,
    int? updatedAtMs,
  }) =>
      WritingDraft(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        prompt: prompt ?? this.prompt,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      );

  int get wordCount {
    final Iterable<RegExpMatch> en =
        RegExp(r"[A-Za-z']+").allMatches(body);
    final Iterable<RegExpMatch> zh =
        RegExp(r'[\u4e00-\u9fff]').allMatches(body);
    return en.length + zh.length;
  }
}

class WritingIssue {
  const WritingIssue({
    required this.type,
    required this.excerpt,
    required this.suggestion,
    this.rewrite = '',
  });

  factory WritingIssue.fromJson(Map<String, dynamic> json) => WritingIssue(
        type: '${json['type'] ?? 'clarity'}',
        excerpt: '${json['excerpt'] ?? ''}',
        suggestion: '${json['suggestion'] ?? ''}',
        rewrite: '${json['rewrite'] ?? ''}',
      );

  final String type;
  final String excerpt;
  final String suggestion;
  final String rewrite;
}

class WritingGradeResult {
  const WritingGradeResult({
    required this.summary,
    required this.issues,
    this.rewriteFull = '',
    this.source = 'local',
    this.rubric = 'generic',
    this.scores = const <String, dynamic>{},
  });

  factory WritingGradeResult.fromJson(Map<String, dynamic> json) =>
      WritingGradeResult(
        summary: '${json['summary'] ?? ''}',
        rewriteFull: '${json['rewrite_full'] ?? json['rewriteFull'] ?? ''}',
        source: '${json['source'] ?? 'api'}',
        rubric: '${json['rubric'] ?? 'generic'}',
        scores: json['scores'] is Map
            ? Map<String, dynamic>.from(json['scores'] as Map)
            : const <String, dynamic>{},
        issues: ((json['issues'] as List<dynamic>?) ?? const <dynamic>[])
            .whereType<Map>()
            .map(
              (Map e) => WritingIssue.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList(growable: false),
      );

  final String summary;
  final List<WritingIssue> issues;
  final String rewriteFull;
  final String source;
  final String rubric;
  final Map<String, dynamic> scores;
}
