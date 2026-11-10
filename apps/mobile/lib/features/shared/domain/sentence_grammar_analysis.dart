class SentenceGrammarPoint {
  const SentenceGrammarPoint({
    required this.title,
    required this.explanation,
  });

  factory SentenceGrammarPoint.fromJson(Map<dynamic, dynamic> json) {
    return SentenceGrammarPoint(
      title: (json['title'] as String? ?? '').trim(),
      explanation: (json['explanation'] as String? ?? '').trim(),
    );
  }

  final String title;
  final String explanation;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'explanation': explanation,
      };
}

class SentenceGrammarPhrase {
  const SentenceGrammarPhrase({
    required this.phrase,
    required this.explanation,
  });

  factory SentenceGrammarPhrase.fromJson(Map<dynamic, dynamic> json) {
    return SentenceGrammarPhrase(
      phrase: (json['phrase'] as String? ?? '').trim(),
      explanation: (json['explanation'] as String? ?? '').trim(),
    );
  }

  final String phrase;
  final String explanation;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'phrase': phrase,
        'explanation': explanation,
      };
}

class SentenceGrammarAnalysis {
  const SentenceGrammarAnalysis({
    required this.sentence,
    required this.translationCn,
    required this.structureCn,
    required this.grammarPoints,
    required this.keyPhrases,
    required this.paraphraseEn,
    required this.learningTipCn,
    required this.sourceLabel,
    this.errorMessage,
  });

  factory SentenceGrammarAnalysis.fromJson(
    Map<dynamic, dynamic> json, {
    required String fallbackSentence,
    String sourceLabel = 'API',
  }) {
    final List<dynamic> pointsRaw =
        json['grammarPoints'] as List<dynamic>? ?? const <dynamic>[];
    final List<dynamic> phrasesRaw =
        json['keyPhrases'] as List<dynamic>? ?? const <dynamic>[];
    return SentenceGrammarAnalysis(
      sentence: (json['sentence'] as String? ?? fallbackSentence).trim(),
      translationCn: (json['translationCn'] as String? ?? '').trim(),
      structureCn: (json['structureCn'] as String? ?? '').trim(),
      grammarPoints: pointsRaw
          .whereType<Map<dynamic, dynamic>>()
          .map(SentenceGrammarPoint.fromJson)
          .where(
            (SentenceGrammarPoint point) =>
                point.title.isNotEmpty || point.explanation.isNotEmpty,
          )
          .toList(growable: false),
      keyPhrases: phrasesRaw
          .whereType<Map<dynamic, dynamic>>()
          .map(SentenceGrammarPhrase.fromJson)
          .where(
            (SentenceGrammarPhrase phrase) =>
                phrase.phrase.isNotEmpty || phrase.explanation.isNotEmpty,
          )
          .toList(growable: false),
      paraphraseEn: (json['paraphraseEn'] as String? ?? '').trim(),
      learningTipCn: (json['learningTipCn'] as String? ?? '').trim(),
      sourceLabel: sourceLabel,
    );
  }

  factory SentenceGrammarAnalysis.unavailable({
    required String sentence,
    required String message,
  }) {
    return SentenceGrammarAnalysis(
      sentence: sentence,
      translationCn: '',
      structureCn: '',
      grammarPoints: const <SentenceGrammarPoint>[],
      keyPhrases: const <SentenceGrammarPhrase>[],
      paraphraseEn: '',
      learningTipCn: '',
      sourceLabel: '未配置',
      errorMessage: message,
    );
  }

  final String sentence;
  final String translationCn;
  final String structureCn;
  final List<SentenceGrammarPoint> grammarPoints;
  final List<SentenceGrammarPhrase> keyPhrases;
  final String paraphraseEn;
  final String learningTipCn;
  final String sourceLabel;
  final String? errorMessage;

  bool get isAvailable => errorMessage == null || errorMessage!.isEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sentence': sentence,
        'translationCn': translationCn,
        'structureCn': structureCn,
        'grammarPoints': grammarPoints
            .map((SentenceGrammarPoint point) => point.toJson())
            .toList(growable: false),
        'keyPhrases': keyPhrases
            .map((SentenceGrammarPhrase phrase) => phrase.toJson())
            .toList(growable: false),
        'paraphraseEn': paraphraseEn,
        'learningTipCn': learningTipCn,
        'sourceLabel': sourceLabel,
        'errorMessage': errorMessage,
      };
}
