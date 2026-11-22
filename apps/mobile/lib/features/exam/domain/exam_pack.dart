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

class ExamClozePassage {
  const ExamClozePassage({
    required this.id,
    required this.title,
    required this.passage,
    required this.questions,
  });

  final String id;
  final String title;
  final String passage;
  final List<ExamMcq> questions;
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
    this.grammar = const <ExamMcq>[],
    this.cloze = const <ExamClozePassage>[],
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

    final List<ExamMcq> vocab =
        asMaps('vocab').map(ExamMcq.fromJson).toList(growable: false);
    final List<ExamReadingItem> reading = asMaps(
      'reading',
    ).map(ExamReadingItem.fromJson).toList(growable: false);
    final List<ExamMcq> grammarRaw =
        asMaps('grammar').map(ExamMcq.fromJson).toList(growable: false);
    final List<ExamClozePassage> clozeRaw = asMaps('cloze')
        .map(
          (Map<String, dynamic> e) => ExamClozePassage(
            id: '${e['id'] ?? ''}',
            title: '${e['title'] ?? 'Cloze'}',
            passage: '${e['passage'] ?? ''}',
            questions: (e['questions'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map>()
                .map(
                  (Map q) => ExamMcq.fromJson(Map<String, dynamic>.from(q)),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false);

    return ExamPack(
      familyId: '${json['family_id'] ?? json['requested_family_id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      cefr: '${json['cefr'] ?? ''}',
      vocab: vocab,
      listening: asMaps(
        'listening',
      ).map(ExamListeningItem.fromJson).toList(growable: false),
      reading: reading,
      writing: asMaps(
        'writing',
      ).map(ExamWritingPrompt.fromJson).toList(growable: false),
      speaking: asMaps(
        'speaking',
      ).map(ExamSpeakingPrompt.fromJson).toList(growable: false),
      grammar: grammarRaw.isNotEmpty
          ? grammarRaw
          : _deriveGrammar(vocab),
      cloze: clozeRaw.isNotEmpty ? clozeRaw : _deriveCloze(reading),
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
  final List<ExamMcq> grammar;
  final List<ExamListeningItem> listening;
  final List<ExamReadingItem> reading;
  final List<ExamClozePassage> cloze;
  final List<ExamWritingPrompt> writing;
  final List<ExamSpeakingPrompt> speaking;
  final List<String> mockSections;
  final int mockMinutes;
  final String resolvedFrom;
  final bool missing;
}

bool _looksLikeGrammarMcq(ExamMcq q) {
  final String p = q.prompt.toLowerCase();
  if (p.contains('___') || p.contains('____') || p.contains('（  ）')) {
    return true;
  }
  return RegExp(
    r'\b(tense|grammar|which of the following|is closest|fill in|choose the best)\b',
    caseSensitive: false,
  ).hasMatch(q.prompt);
}

List<ExamMcq> _deriveGrammar(List<ExamMcq> vocab) {
  final List<ExamMcq> hit =
      vocab.where(_looksLikeGrammarMcq).toList(growable: false);
  if (hit.length >= 8) return hit;
  // Fallback: take a slice so grammar skill is never empty when vocab exists.
  return vocab.take(40).toList(growable: false);
}

List<ExamClozePassage> _deriveCloze(List<ExamReadingItem> reading) {
  final List<ExamClozePassage> out = <ExamClozePassage>[];
  for (final ExamReadingItem item in reading) {
    final bool blanksInPassage =
        item.passage.contains('_') || item.passage.contains('____');
    final bool blankPrompts = item.questions.any(
      (ExamMcq q) =>
          q.prompt.toLowerCase().contains('blank') ||
          RegExp(r'第?\s*\d+\s*空').hasMatch(q.prompt),
    );
    if (blanksInPassage || blankPrompts) {
      out.add(
        ExamClozePassage(
          id: item.id,
          title: item.title,
          passage: item.passage,
          questions: item.questions,
        ),
      );
    }
  }
  return out;
}

String grammarTagForPrompt(String prompt) {
  final String p = prompt.toLowerCase();
  if (RegExp(
    r'\b(was|were|been|had|will|would|tense|ago|yesterday|tomorrow|since|for\s+\d)\b',
  ).hasMatch(p)) {
    return '时态';
  }
  if (RegExp(r'\b(who|which|that|whom|whose)\b').hasMatch(p)) {
    return '从句';
  }
  if (RegExp(r'\b(to\s+\w+ing|non-?finite|infinitive|gerund)\b').hasMatch(p) ||
      (p.contains('___') && RegExp(r'\b(doing|to do|done)\b').hasMatch(p))) {
    return '非谓语';
  }
  if (p.contains('___') && RegExp(r'\b(a|an|the)\b').hasMatch(p)) {
    return '冠词';
  }
  if (RegExp(r'\b(is|are|am)\b').hasMatch(p) && p.contains('___')) {
    return '主谓一致';
  }
  return '综合语法';
}
