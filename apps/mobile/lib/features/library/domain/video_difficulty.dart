/// Offline CEFR estimate from English subtitle text + top-N frequency lexicon.
library;

const List<String> kCefrLevels = <String>[
  'A1',
  'A2',
  'B1',
  'B2',
  'C1',
  'C2',
];

final RegExp _tokenRe = RegExp(r"[A-Za-z]+(?:['’-][A-Za-z]+)*");

class VideoDifficultyEstimate {
  const VideoDifficultyEstimate({
    required this.cefr,
    required this.top3000Coverage,
    required this.tokenCount,
    required this.typeCount,
    required this.fingerprint,
    required this.computedAtMs,
  });

  factory VideoDifficultyEstimate.fromJson(Map<String, dynamic> json) {
    return VideoDifficultyEstimate(
      cefr: (json['cefr'] as String? ?? 'B1').toUpperCase(),
      top3000Coverage: (json['top3000Coverage'] as num?)?.toDouble() ?? 0,
      tokenCount: (json['tokenCount'] as num?)?.toInt() ?? 0,
      typeCount: (json['typeCount'] as num?)?.toInt() ?? 0,
      fingerprint: json['fingerprint'] as String? ?? '',
      computedAtMs: (json['computedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  final String cefr;
  final double top3000Coverage;
  final int tokenCount;
  final int typeCount;
  final String fingerprint;
  final int computedAtMs;

  String get displayLabel => '约 $cefr';

  int get rank => cefrRank(cefr);

  Map<String, Object?> toJson() => <String, Object?>{
        'cefr': cefr,
        'top3000Coverage': top3000Coverage,
        'tokenCount': tokenCount,
        'typeCount': typeCount,
        'fingerprint': fingerprint,
        'computedAtMs': computedAtMs,
      };
}

int cefrRank(String cefr) {
  final int index = kCefrLevels.indexOf(cefr.toUpperCase());
  return index < 0 ? 2 : index;
}

String? parseCefrLevel(String? raw) {
  if (raw == null) return null;
  final String text = raw.trim();
  if (text.isEmpty) return null;
  final Match? m = RegExp(
    r'\b(A1|A2|B1|B2|C1|C2)\b',
    caseSensitive: false,
  ).firstMatch(text);
  return m?.group(1)?.toUpperCase();
}

List<String> tokenizeEnglish(String text) {
  final List<String> out = <String>[];
  for (final RegExpMatch m in _tokenRe.allMatches(text)) {
    final String w = m.group(0)!.toLowerCase().replaceAll('’', "'");
    if (w.length >= 2) {
      out.add(w);
    }
  }
  return out;
}

/// Map top-3000 token coverage (+ light length / rarity signals) to CEFR.
String cefrFromCoverage({
  required double coverage,
  required double avgTokenLength,
  required double rareTypeRate,
}) {
  double score = coverage;
  // Longer words and many rare types push difficulty up (lower score).
  if (avgTokenLength >= 5.8) score -= 0.03;
  if (avgTokenLength >= 6.4) score -= 0.03;
  if (rareTypeRate >= 0.35) score -= 0.03;
  if (rareTypeRate >= 0.45) score -= 0.04;

  if (score >= 0.96) return 'A1';
  if (score >= 0.92) return 'A2';
  if (score >= 0.86) return 'B1';
  if (score >= 0.80) return 'B2';
  if (score >= 0.72) return 'C1';
  return 'C2';
}

VideoDifficultyEstimate estimateVideoDifficulty({
  required String englishText,
  required Set<String> topFrequencyWords,
  required String fingerprint,
  int? computedAtMs,
}) {
  final List<String> tokens = tokenizeEnglish(englishText);
  if (tokens.isEmpty || topFrequencyWords.isEmpty) {
    return VideoDifficultyEstimate(
      cefr: 'B1',
      top3000Coverage: 0,
      tokenCount: 0,
      typeCount: 0,
      fingerprint: fingerprint,
      computedAtMs: computedAtMs ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  final Map<String, int> types = <String, int>{};
  int commonTokens = 0;
  int totalLen = 0;
  for (final String token in tokens) {
    types[token] = (types[token] ?? 0) + 1;
    totalLen += token.length;
    if (topFrequencyWords.contains(token)) {
      commonTokens += 1;
    }
  }

  final double coverage = commonTokens / tokens.length;
  final double avgLen = totalLen / tokens.length;
  int rareTypes = 0;
  for (final String type in types.keys) {
    if (!topFrequencyWords.contains(type)) {
      rareTypes += 1;
    }
  }
  final double rareTypeRate = rareTypes / types.length;
  final String cefr = cefrFromCoverage(
    coverage: coverage,
    avgTokenLength: avgLen,
    rareTypeRate: rareTypeRate,
  );

  return VideoDifficultyEstimate(
    cefr: cefr,
    top3000Coverage: coverage,
    tokenCount: tokens.length,
    typeCount: types.length,
    fingerprint: fingerprint,
    computedAtMs: computedAtMs ?? DateTime.now().millisecondsSinceEpoch,
  );
}

String difficultyFingerprint(Iterable<String> episodeKeys) {
  final List<String> keys = episodeKeys.toList(growable: false)..sort();
  return keys.join('|');
}

/// Dual-dimension label: CEFR + 入门/中考/高考/雅思 band for K12 + adult.
String examBandFromCefr(String cefr) {
  switch (cefr.toUpperCase()) {
    case 'A1':
    case 'A2':
      return '入门';
    case 'B1':
      return '中考';
    case 'B2':
      return '高考';
    case 'C1':
    case 'C2':
      return '雅思';
    default:
      return '中考';
  }
}

String dualDifficultyLabel(String cefr) {
  final String level = cefr.toUpperCase();
  return '$level · ${examBandFromCefr(level)}';
}

/// Lightweight per-sentence CEFR using the same coverage math as course scan.
VideoDifficultyEstimate estimateSentenceDifficulty({
  required String englishText,
  required Set<String> topFrequencyWords,
}) {
  return estimateVideoDifficulty(
    englishText: englishText,
    topFrequencyWords: topFrequencyWords,
    fingerprint: 'sentence:${englishText.hashCode}',
  );
}
