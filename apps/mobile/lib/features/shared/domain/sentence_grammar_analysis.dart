class SentenceGrammarPoint {
  const SentenceGrammarPoint({
    required this.title,
    required this.explanation,
  });

  factory SentenceGrammarPoint.fromJson(Map<dynamic, dynamic> json) {
    return SentenceGrammarPoint(
      title: _asPlainText(json['title'] ?? json['name'] ?? json['point']),
      explanation: _asPlainText(
        json['explanation'] ?? json['detail'] ?? json['desc'],
      ),
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
      phrase: _asPlainText(json['phrase'] ?? json['text'] ?? json['title']),
      explanation: _asPlainText(
        json['explanation'] ?? json['detail'] ?? json['desc'],
      ),
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
    this.tenseVoiceCn = '',
    this.partsOfSpeechCn = '',
    this.svoCn = '',
    this.predicateVerb = '',
    this.clausesCn = '',
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
    final Object? pointsRaw =
        json['grammarPoints'] ??
        json['grammar_points'] ??
        json['points'] ??
        json['grammarPoints/keyPhrases'];
    final Object? phrasesRaw =
        json['keyPhrases'] ?? json['key_phrases'] ?? json['phrases'];
    final String cachedSource = _asPlainText(json['source']);
    return SentenceGrammarAnalysis(
      sentence: _asPlainText(
        json['sentence'] ?? json['text'] ?? fallbackSentence,
        fallback: fallbackSentence,
      ),
      translationCn: _asPlainText(
        json['translationCn'] ?? json['translation'] ?? json['zh'],
      ),
      structureCn: _asStructureText(
        json['structureCn'] ?? json['structure'] ?? json['structure_cn'],
      ),
      tenseVoiceCn: _asPlainText(
        json['tenseVoiceCn'] ??
            json['tense'] ??
            json['tense_voice'] ??
            json['时态语态'],
      ),
      partsOfSpeechCn: _asPlainText(
        json['partsOfSpeechCn'] ??
            json['partsOfSpeech'] ??
            json['pos'] ??
            json['词性'],
      ),
      svoCn: _asPlainText(
        json['svoCn'] ?? json['svo'] ?? json['subjectVerbObject'] ?? json['主谓宾'],
      ),
      predicateVerb: _asPlainText(
        json['predicateVerb'] ?? json['predicate'] ?? json['谓语动词'],
      ),
      clausesCn: _asPlainText(
        json['clausesCn'] ??
            json['clauses'] ??
            json['mainSubordinate'] ??
            json['主从句'],
      ),
      grammarPoints: _parseGrammarPoints(pointsRaw),
      keyPhrases: _parseKeyPhrases(phrasesRaw),
      paraphraseEn: _asPlainText(
        json['paraphraseEn'] ?? json['paraphrase'] ?? json['rewriteEn'],
      ),
      learningTipCn: _asPlainText(
        json['learningTipCn'] ?? json['tip'] ?? json['learningTip'],
      ),
      sourceLabel: cachedSource.isNotEmpty ? cachedSource : sourceLabel,
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
      tenseVoiceCn: '',
      partsOfSpeechCn: '',
      svoCn: '',
      predicateVerb: '',
      clausesCn: '',
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
  final String tenseVoiceCn;
  final String partsOfSpeechCn;
  final String svoCn;
  final String predicateVerb;
  final String clausesCn;
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
        'tenseVoiceCn': tenseVoiceCn,
        'partsOfSpeechCn': partsOfSpeechCn,
        'svoCn': svoCn,
        'predicateVerb': predicateVerb,
        'clausesCn': clausesCn,
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

String _asPlainText(Object? value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  if (value is String) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }
  if (value is num || value is bool) {
    return '$value';
  }
  if (value is List) {
    final String joined = value
        .map((Object? item) => _asPlainText(item))
        .where((String item) => item.isNotEmpty)
        .join('；');
    return joined.isEmpty ? fallback : joined;
  }
  if (value is Map) {
    return _asStructureText(value);
  }
  final String text = '$value'.trim();
  return text.isEmpty ? fallback : text;
}

String _asStructureText(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is String) {
    return value.trim();
  }
  if (value is List) {
    return value
        .map((Object? item) {
          if (item is Map) {
            final String title = _asPlainText(
              item['title'] ?? item['name'] ?? item['part'],
            );
            final String explanation = _asPlainText(
              item['explanation'] ??
                  item['detail'] ??
                  item['desc'] ??
                  item['text'],
            );
            if (title.isEmpty) {
              return explanation;
            }
            if (explanation.isEmpty) {
              return title;
            }
            return '$title → $explanation';
          }
          return _asPlainText(item);
        })
        .where((String item) => item.isNotEmpty)
        .join('\n');
  }
  if (value is Map) {
    final String title = _asPlainText(
      value['title'] ?? value['name'] ?? value['pattern'],
    );
    final String explanation = _asPlainText(
      value['explanation'] ?? value['detail'] ?? value['desc'],
    );
    if (title.isEmpty) {
      return explanation;
    }
    if (explanation.isEmpty) {
      return title;
    }
    return '$title：$explanation';
  }
  return '$value'.trim();
}

List<SentenceGrammarPoint> _parseGrammarPoints(Object? raw) {
  if (raw is! List) {
    if (raw is String && raw.trim().isNotEmpty) {
      return <SentenceGrammarPoint>[
        SentenceGrammarPoint(title: raw.trim(), explanation: ''),
      ];
    }
    return const <SentenceGrammarPoint>[];
  }
  return raw
      .map((Object? item) {
        if (item is Map) {
          return SentenceGrammarPoint.fromJson(item);
        }
        final String text = _asPlainText(item);
        if (text.isEmpty) {
          return null;
        }
        return SentenceGrammarPoint(title: text, explanation: '');
      })
      .whereType<SentenceGrammarPoint>()
      .where(
        (SentenceGrammarPoint point) =>
            point.title.isNotEmpty || point.explanation.isNotEmpty,
      )
      .toList(growable: false);
}

List<SentenceGrammarPhrase> _parseKeyPhrases(Object? raw) {
  if (raw is! List) {
    if (raw is String && raw.trim().isNotEmpty) {
      return <SentenceGrammarPhrase>[
        SentenceGrammarPhrase(phrase: raw.trim(), explanation: ''),
      ];
    }
    return const <SentenceGrammarPhrase>[];
  }
  return raw
      .map((Object? item) {
        if (item is Map) {
          return SentenceGrammarPhrase.fromJson(item);
        }
        final String text = _asPlainText(item);
        if (text.isEmpty) {
          return null;
        }
        return SentenceGrammarPhrase(phrase: text, explanation: '');
      })
      .whereType<SentenceGrammarPhrase>()
      .where(
        (SentenceGrammarPhrase phrase) =>
            phrase.phrase.isNotEmpty || phrase.explanation.isNotEmpty,
      )
      .toList(growable: false);
}
