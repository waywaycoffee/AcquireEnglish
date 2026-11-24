import 'dart:math' as math;

import 'vocabulary_placement_estimate.dart';

/// Map prefs / CEFR chips → starting recognition vocabulary size.
int startingVocabEstimateForLevel(String? level) {
  final String key = (level ?? '').trim().toUpperCase();
  return switch (key) {
    '零基础' || 'ZERO' || 'BEGINNER' => 300,
    '学龄前' || 'PRESCHOOL' || 'KIDS' => 500,
    'A1' => 900,
    'A2' => 1400,
    'B1' => 2500,
    'B2' => 4800,
    'C1' => 8500,
    'C2' => 15000,
    _ => 2000,
  };
}

class PlacementQuestion {
  const PlacementQuestion({
    required this.word,
    required this.rank,
    required this.definitionCn,
    required this.choices,
    required this.bandLo,
    required this.bandHi,
  });

  final String word;
  final int rank;
  final String definitionCn;
  final List<String> choices;
  final int bandLo;
  final int bandHi;
}

class PlacementBandPool {
  PlacementBandPool({
    required this.lo,
    required this.hi,
    required this.size,
    required List<Map<String, dynamic>> rawItems,
  }) : items = rawItems
            .map((Map<String, dynamic> row) {
              final String word = (row['word'] as String? ?? '').trim();
              final String def = (row['definition_cn'] as String? ?? '').trim();
              final int rank = (row['rank'] as num?)?.toInt() ?? 0;
              if (word.isEmpty || def.isEmpty || rank <= 0) return null;
              return (word: word, rank: rank, definitionCn: def);
            })
            .whereType<({String word, int rank, String definitionCn})>()
            .toList(growable: false);

  final int lo;
  final int hi;
  final int size;
  final List<({String word, int rank, String definitionCn})> items;

  int get midRank => ((lo + hi) / 2).round();
}

/// Adaptive vocabulary placement: start from learner level, step difficulty
/// with each correct / incorrect answer, produce a snapped estimate.
class AdaptivePlacementEngine {
  AdaptivePlacementEngine({
    required this.bands,
    required int startingEstimate,
    this.maxQuestions = 12,
    math.Random? random,
  }) : estimate = startingEstimate
            .clamp(kPlacementEstimateMin, kPlacementEstimateMax)
            .toDouble(),
       _random = random ?? math.Random();

  final List<PlacementBandPool> bands;
  final int maxQuestions;
  final math.Random _random;

  double estimate;
  int asked = 0;
  final Set<String> _usedWords = <String>{};
  double? _prevEstimate;

  bool get isComplete =>
      asked >= maxQuestions ||
      (asked >= 8 && _movedLittle) ||
      _availableCount == 0;

  int get finalEstimate => estimateVocabFromPlacementScore(estimate);

  bool get _movedLittle {
    final double? prev = _prevEstimate;
    if (prev == null) return false;
    final double delta = (estimate - prev).abs();
    return delta < math.max(120, estimate * 0.04);
  }

  int get _availableCount {
    var n = 0;
    for (final PlacementBandPool band in bands) {
      for (final item in band.items) {
        if (!_usedWords.contains(item.word.toLowerCase())) n++;
      }
    }
    return n;
  }

  PlacementQuestion? nextQuestion() {
    if (isComplete) return null;
    final PlacementBandPool? band = _pickBandNearEstimate();
    if (band == null) return null;
    final candidates = band.items
        .where((item) => !_usedWords.contains(item.word.toLowerCase()))
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    final item = candidates[_random.nextInt(candidates.length)];
    final List<String> choices = _buildChoices(
      correct: item.definitionCn,
      preferred: band,
    );
    if (choices.length < 2) return null;
    return PlacementQuestion(
      word: item.word,
      rank: item.rank,
      definitionCn: item.definitionCn,
      choices: choices,
      bandLo: band.lo,
      bandHi: band.hi,
    );
  }

  void recordAnswer({
    required PlacementQuestion question,
    required bool correct,
  }) {
    _usedWords.add(question.word.toLowerCase());
    _prevEstimate = estimate;
    asked += 1;
    if (correct) {
      if (question.rank >= estimate) {
        // Harder word known → push estimate up toward / past that rank.
        final double target = question.rank * 1.12;
        estimate += (target - estimate) * 0.55;
      } else {
        // Easy word known → tiny confidence bump only (never pull down).
        estimate *= 1.02;
      }
    } else {
      if (question.rank <= estimate * 1.25) {
        // Missed a word at/below current level → drop.
        final double target = question.rank * 0.55;
        estimate += (target - estimate) * 0.6;
      } else {
        // Missed a stretch word → mild drop.
        estimate *= 0.97;
      }
    }
    estimate = estimate.clamp(
      kPlacementEstimateMin.toDouble(),
      kPlacementEstimateMax.toDouble(),
    );
  }

  PlacementBandPool? _pickBandNearEstimate() {
    if (bands.isEmpty) return null;
    PlacementBandPool? best;
    var bestScore = double.infinity;
    // Prefer bands slightly above current estimate (informative i+1 probes).
    final double aim = estimate * 1.08;
    for (final PlacementBandPool band in bands) {
      final bool hasUnused = band.items.any(
        (item) => !_usedWords.contains(item.word.toLowerCase()),
      );
      if (!hasUnused) continue;
      final double dist = (band.midRank - aim).abs();
      final double score = dist + _random.nextDouble() * 80;
      if (score < bestScore) {
        bestScore = score;
        best = band;
      }
    }
    return best;
  }

  List<String> _buildChoices({
    required String correct,
    required PlacementBandPool preferred,
  }) {
    final Set<String> pool = <String>{correct};
    void absorb(PlacementBandPool band) {
      for (final item in band.items) {
        if (item.definitionCn.isNotEmpty) pool.add(item.definitionCn);
      }
    }

    absorb(preferred);
    // Neighbor bands for distractors when the preferred band is thin.
    final int idx = bands.indexOf(preferred);
    if (idx > 0) absorb(bands[idx - 1]);
    if (idx >= 0 && idx + 1 < bands.length) absorb(bands[idx + 1]);
    for (final PlacementBandPool band in bands) {
      if (pool.length >= 8) break;
      absorb(band);
    }
    return buildPlacementChoices(
          correctDefinition: correct,
          candidateDefinitions: pool,
          maxChoices: kPlacementMaxChoices,
          random: _random,
        ) ??
        <String>[];
  }
}

/// Parse API `/public-lexicon/placement` payload into band pools.
List<PlacementBandPool> parsePlacementBands(List<Map<String, dynamic>> raw) {
  // Keep API order: each row is one frequency band with `size` + `items`.
  // Reconstruct lo/hi from cumulative sizes when ranks are present.
  final List<PlacementBandPool> out = <PlacementBandPool>[];
  for (final Map<String, dynamic> band in raw) {
    final List<Map<String, dynamic>> items =
        (band['items'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
    if (items.isEmpty) continue;
    final int size = (band['size'] as num?)?.toInt() ?? items.length;
    final ranks = items
        .map((Map<String, dynamic> row) => (row['rank'] as num?)?.toInt() ?? 0)
        .where((int r) => r > 0)
        .toList(growable: false);
    final int lo =
        (band['lo'] as num?)?.toInt() ??
        (ranks.isEmpty ? 1 : ranks.reduce(math.min));
    final int hi =
        (band['hi'] as num?)?.toInt() ??
        (ranks.isEmpty ? size : ranks.reduce(math.max));
    out.add(
      PlacementBandPool(
        lo: lo,
        hi: hi,
        size: size,
        rawItems: items,
      ),
    );
  }
  return out;
}
