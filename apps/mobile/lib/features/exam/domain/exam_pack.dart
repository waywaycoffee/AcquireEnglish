class ExamMcq {
  const ExamMcq({
    required this.id,
    required this.prompt,
    required this.options,
    required this.answer,
    this.explain = '',
  });

  factory ExamMcq.fromJson(Map<String, dynamic> json) => ExamMcq(
        id: '${json['id'] ?? ''}',
        prompt: '${json['prompt'] ?? ''}',
        options: (json['options'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic e) => '$e')
            .toList(growable: false),
        answer: '${json['answer'] ?? ''}',
        explain: '${json['explain'] ?? ''}',
      );

  final String id;
  final String prompt;
  final List<String> options;
  final String answer;
  final String explain;
}

class ExamListeningItem {
  const ExamListeningItem({
    required this.id,
    required this.title,
    required this.script,
    required this.questions,
    this.audioUrl = '',
  });

  factory ExamListeningItem.fromJson(Map<String, dynamic> json) =>
      ExamListeningItem(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? 'Listening'}',
        script: '${json['script'] ?? ''}',
        audioUrl: '${json['audio_url'] ?? ''}',
        questions: (json['questions'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map e) => ExamMcq.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
      );

  final String id;
  final String title;
  final String script;
  final String audioUrl;
  final List<ExamMcq> questions;
}

class ExamReadingItem {
  const ExamReadingItem({
    required this.id,
    required this.title,
    required this.passage,
    required this.questions,
  });

  factory ExamReadingItem.fromJson(Map<String, dynamic> json) => ExamReadingItem(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? 'Reading'}',
        passage: '${json['passage'] ?? ''}',
        questions: (json['questions'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map e) => ExamMcq.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
      );

  final String id;
  final String title;
  final String passage;
  final List<ExamMcq> questions;
}

class ExamWritingPrompt {
  const ExamWritingPrompt({
    required this.id,
    required this.prompt,
    required this.rubric,
    this.minWords = 120,
  });

  factory ExamWritingPrompt.fromJson(Map<String, dynamic> json) =>
      ExamWritingPrompt(
        id: '${json['id'] ?? ''}',
        prompt: '${json['prompt'] ?? ''}',
        rubric: '${json['rubric'] ?? 'generic'}',
        minWords: (json['min_words'] as num?)?.toInt() ?? 120,
      );

  final String id;
  final String prompt;
  final String rubric;
  final int minWords;
}

class ExamSpeakingPrompt {
  const ExamSpeakingPrompt({
    required this.id,
    required this.prompt,
    this.tips = '',
  });

  factory ExamSpeakingPrompt.fromJson(Map<String, dynamic> json) =>
      ExamSpeakingPrompt(
        id: '${json['id'] ?? ''}',
        prompt: '${json['prompt'] ?? ''}',
        tips: '${json['tips'] ?? ''}',
      );

  final String id;
  final String prompt;
  final String tips;
}

class ExamPack {
  const ExamPack({
    required this.familyId,
    required this.title,
    required this.cefr,
    required this.vocab,
    required this.listening,
    required this.reading,
    required this.writing,
    required this.speaking,
    required this.mockSections,
    required this.mockMinutes,
    this.resolvedFrom = '',
    this.missing = false,
  });

  factory ExamPack.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> sections = json['sections'] is Map
        ? Map<String, dynamic>.from(json['sections'] as Map)
        : <String, dynamic>{};
    final Map<String, dynamic> mock = json['mock'] is Map
        ? Map<String, dynamic>.from(json['mock'] as Map)
        : <String, dynamic>{};
    List<Map<String, dynamic>> asMaps(String key) =>
        (sections[key] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map e) => Map<String, dynamic>.from(e))
            .toList(growable: false);

    return ExamPack(
      familyId: '${json['family_id'] ?? json['requested_family_id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      cefr: '${json['cefr'] ?? ''}',
      vocab: asMaps('vocab').map(ExamMcq.fromJson).toList(growable: false),
      listening: asMaps(
        'listening',
      ).map(ExamListeningItem.fromJson).toList(growable: false),
      reading: asMaps(
        'reading',
      ).map(ExamReadingItem.fromJson).toList(growable: false),
      writing: asMaps(
        'writing',
      ).map(ExamWritingPrompt.fromJson).toList(growable: false),
      speaking: asMaps(
        'speaking',
      ).map(ExamSpeakingPrompt.fromJson).toList(growable: false),
      mockSections: (mock['sections'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic e) => '$e')
          .toList(growable: false),
      mockMinutes: (mock['duration_minutes'] as num?)?.toInt() ?? 60,
      resolvedFrom: '${json['resolved_from'] ?? ''}',
      missing: json['missing'] == true,
    );
  }

  final String familyId;
  final String title;
  final String cefr;
  final List<ExamMcq> vocab;
  final List<ExamListeningItem> listening;
  final List<ExamReadingItem> reading;
  final List<ExamWritingPrompt> writing;
  final List<ExamSpeakingPrompt> speaking;
  final List<String> mockSections;
  final int mockMinutes;
  final String resolvedFrom;
  final bool missing;
}
