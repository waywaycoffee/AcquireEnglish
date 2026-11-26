/// Structured ZH/awkward → idiomatic English diagnosis (live-correction style).
class OralExpressionDiagnosis {
  const OralExpressionDiagnosis({
    required this.source,
    required this.literalEn,
    required this.idiomaticEn,
    this.tip = '',
  });

  factory OralExpressionDiagnosis.fromJson(Map<String, dynamic> json) {
    return OralExpressionDiagnosis(
      source: '${json['source'] ?? json['source_zh'] ?? ''}'.trim(),
      literalEn: '${json['literal_en'] ?? json['literal'] ?? ''}'.trim(),
      idiomaticEn:
          '${json['idiomatic_en'] ?? json['idiomatic'] ?? ''}'.trim(),
      tip: '${json['tip'] ?? json['note'] ?? ''}'.trim(),
    );
  }

  factory OralExpressionDiagnosis.fallback({
    required String source,
    String literalEn = '',
    String idiomaticEn = '',
    String tip = '',
  }) {
    return OralExpressionDiagnosis(
      source: source.trim(),
      literalEn: literalEn.trim().isEmpty ? idiomaticEn.trim() : literalEn.trim(),
      idiomaticEn: idiomaticEn.trim().isEmpty
          ? literalEn.trim()
          : idiomaticEn.trim(),
      tip: tip.trim().isEmpty
          ? '先按住再说一次地道英文，再说给对方听。'
          : tip.trim(),
    );
  }

  final String source;
  final String literalEn;
  final String idiomaticEn;
  final String tip;

  /// Clear-English rewrite differs from what the learner said.
  bool get hasLiteralFix =>
      literalEn.isNotEmpty && !_sameUtterance(source, literalEn);

  /// More natural spoken English differs from clear/literal English (or source).
  bool get hasIdiomaticPolish {
    if (idiomaticEn.isEmpty) return false;
    if (literalEn.isNotEmpty) {
      return !_sameUtterance(literalEn, idiomaticEn);
    }
    return !_sameUtterance(source, idiomaticEn);
  }

  /// Show strike-through / green rewrite theatre only when text actually changes.
  bool get needsCorrectionUi =>
      transcriptLooksChineseHeavy(source) || hasLiteralFix || hasIdiomaticPolish;

  /// Worth interrupting the chat to practice a rewrite.
  bool get isUseful {
    if (source.isEmpty) return false;
    if (transcriptLooksChineseHeavy(source)) {
      return literalEn.isNotEmpty || idiomaticEn.isNotEmpty || tip.isNotEmpty;
    }
    // English already matches the suggested line — do not pretend to "correct".
    return hasLiteralFix || hasIdiomaticPolish;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'source': source,
    'literal_en': literalEn,
    'idiomatic_en': idiomaticEn,
    'tip': tip,
  };
}

bool transcriptLooksChineseHeavy(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) return false;
  final int han = RegExp(r'[\u4e00-\u9fff]').allMatches(text).length;
  if (han == 0) return false;
  final int letters = RegExp(r'[A-Za-z]').allMatches(text).length;
  return han >= 2 && han >= letters;
}

String normalizeOralUtterance(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[’`]'), "'")
      .replaceAll(RegExp("[^a-z0-9\\u4e00-\\u9fff\\s']"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool _sameUtterance(String a, String b) {
  final String left = normalizeOralUtterance(a);
  final String right = normalizeOralUtterance(b);
  if (left.isEmpty || right.isEmpty) return false;
  return left == right;
}
