import 'dart:math' as math;

import 'vocabulary_placement_estimate.dart';

/// Map prefs / CEFR chips → starting recognition vocabulary size.
///
/// Conservative priors: self-reported CEFR often overshoots; the test must
/// climb with evidence rather than inherit an inflated ceiling.
int startingVocabEstimateForLevel(String? level) {
  final String key = (level ?? '').trim().toUpperCase();
  return switch (key) {
    '零基础' || 'ZERO' || 'BEGINNER' => 300,
    '学龄前' || 'PRESCHOOL' || 'KIDS' => 500,
    'A1' => 800,
    'A2' => 1200,
    'B1' => 2200,
    'B2' => 3800,
    'C1' => 6000,
    'C2' => 10000,
    _ => 1600,
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
    this.maxQuestions = 16,
    math.Random? random,
  }) : estimate = startingEstimate
            .clamp(kPlacementEstimateMin, kPlacementEstimateMax)
            .toDouble(),
       _startEstimate = startingEstimate
           .clamp(kPlacementEstimateMin, kPlacementEstimateMax)
           .toDouble(),
       _random = random ?? math.Random();

  final List<PlacementBandPool> bands;
  final int maxQuestions;
  final math.Random _random;
  final double _startEstimate;

  double estimate;
  int asked = 0;
  final Set<String> _usedWords = <String>{};
  double? _prevEstimate;

  /// Highest frequency-rank correctly answered (rarer = higher rank).
  int? maxCorrectRank;

  /// Lowest rank missed (easy miss is strong negative evidence).
  int? minIncorrectRank;

  /// How many items were asked near/above the live estimate (stretch probes).
  int stretchProbes = 0;

  /// Consecutive corrects that were clearly below the live estimate.
  int easyCorrectStreak = 0;

  bool get isComplete {
    if (_availableCount == 0) return true;
    if (asked >= maxQuestions) return true;
    // Need enough items + at least two stretch probes before early stop.
    if (asked >= 10 && stretchProbes >= 2 && _movedLittle) return true;
    // Stabilized with a miss: can stop a bit earlier.
    if (asked >= 8 &&
        stretchProbes >= 2 &&
        minIncorrectRank != null &&
        _movedLittle) {
      return true;
    }
    return false;
  }

  int get finalEstimate {
    double value = estimate;
    // Never report far above the hardest word the learner actually knew.
    final int? proven = maxCorrectRank;
    if (proven != null) {
      value = math.min(value, proven * 1.28);
    } else {
      // Zero corrects → stay near the conservative floor of the start.
      value = math.min(value, math.max(300, _startEstimate * 0.55));
    }
    // Without stretch probes, high self-report priors stay unvalidated.
    if (stretchProbes < 2 && proven != null) {
      value = math.min(value, proven * 1.18);
    }
    // If they never missed but also never cleared hard stretch items, trim.
    if (minIncorrectRank == null && stretchProbes < 3 && proven != null) {
      value = math.min(value, math.max(proven * 1.12, proven + 400.0));
    }
    return estimateVocabFromPlacementScore(value);
  }

  bool get _movedLittle {
    final double? prev = _prevEstimate;
    if (prev == null) return false;
    final double delta = (estimate - prev).abs();
    return delta < math.max(150, estimate * 0.035);
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
    // Prefer rarer items inside the band when stretching.
    candidates.sort((a, b) => a.rank.compareTo(b.rank));
    final ({String word, int rank, String definitionCn}) item;
    if (_shouldForceStretch && candidates.length > 1) {
      final int from = (candidates.length * 0.45).floor().clamp(
        0,
        candidates.length - 1,
      );
      final List<({String word, int rank, String definitionCn})> hardSlice =
          candidates.sublist(from);
      item = hardSlice[_random.nextInt(hardSlice.length)];
    } else {
      item = candidates[_random.nextInt(candidates.length)];
    }
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
    final bool isStretch = question.rank >= estimate * 0.9;
    if (isStretch) {
      stretchProbes += 1;
    }

    if (correct) {
      maxCorrectRank = maxCorrectRank == null
          ? question.rank
          : math.max(maxCorrectRank!, question.rank);
      if (question.rank >= estimate * 0.9) {
        easyCorrectStreak = 0;
        // Informative correct: climb toward / past that rank.
        final double target = question.rank * 1.18;
        estimate += (target - estimate) * 0.5;
      } else if (question.rank < estimate * 0.55) {
        // Too easy for the claimed level — shrink the unvalidated prior,
        // but keep enough headroom so later stretch probes still run.
        easyCorrectStreak += 1;
        final double evidenceCeiling = question.rank * 1.65;
        estimate = estimate * 0.9 + evidenceCeiling * 0.1;
        if (easyCorrectStreak >= 3) {
          final double softFloor = math.max(evidenceCeiling * 2.0, estimate * 0.78);
          estimate = math.min(estimate, softFloor);
        }
      } else {
        easyCorrectStreak = 0;
        estimate *= 1.015;
      }
    } else {
      easyCorrectStreak = 0;
      minIncorrectRank = minIncorrectRank == null
          ? question.rank
          : math.min(minIncorrectRank!, question.rank);
      if (question.rank <= estimate * 1.2) {
        // Missed at/below claimed level → drop hard.
        final double target = question.rank * 0.5;
        estimate += (target - estimate) * 0.65;
      } else {
        // Missed a stretch word → mild drop, keep probing.
        estimate *= 0.94;
      }
    }
    estimate = estimate.clamp(
      kPlacementEstimateMin.toDouble(),
      kPlacementEstimateMax.toDouble(),
    );
  }

  bool get _shouldForceStretch =>
      asked >= 1 && (asked % 2 == 1 || easyCorrectStreak >= 2);

  PlacementBandPool? _pickBandNearEstimate() {
    if (bands.isEmpty) return null;
    PlacementBandPool? best;
    var bestScore = double.infinity;
    // Stretch aims above the live estimate so hard words actually appear.
    final double aim = _shouldForceStretch
        ? estimate * 1.45
        : estimate * 1.08;
    final double maxAvailableMid = bands
        .where(
          (PlacementBandPool band) => band.items.any(
            (item) => !_usedWords.contains(item.word.toLowerCase()),
          ),
        )
        .fold<double>(0, (double m, PlacementBandPool b) {
          return math.max(m, b.midRank.toDouble());
        });
    final double clampedAim =
        maxAvailableMid <= 0 ? aim : math.min(aim, maxAvailableMid);

    for (final PlacementBandPool band in bands) {
      final bool hasUnused = band.items.any(
        (item) => !_usedWords.contains(item.word.toLowerCase()),
      );
      if (!hasUnused) continue;
      final double dist = (band.midRank - clampedAim).abs();
      // Soft preference for bands above estimate when stretching.
      final double belowPenalty =
          _shouldForceStretch && band.hi < estimate * 0.85 ? 900 : 0;
      final double score = dist + belowPenalty + _random.nextDouble() * 60;
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
