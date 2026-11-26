import 'dart:math' as math;

import 'vocabulary_placement_estimate.dart';
import 'vocabulary_placement_scoring.dart';

/// Map prefs / CEFR chips → starting recognition vocabulary size.
///
/// Conservative priors: self-reported CEFR often overshoots; the Bayesian
/// prior uses this as median of ln(m).
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

/// Adaptive vocabulary placement with ARealMe-style Bayesian scoring.
///
/// Keeps MCQ + 「不认识」. Wrong choices inform guessing rate *g*; 「不认识」
/// does not. Live estimate is the posterior median of V(m,s).
class AdaptivePlacementEngine {
  AdaptivePlacementEngine({
    required this.bands,
    required int startingEstimate,
    this.maxQuestions = 40,
    math.Random? random,
  }) : _startEstimate = startingEstimate
           .clamp(kPlacementEstimateMin, kPlacementEstimateMax)
           .toDouble(),
       _random = random ?? math.Random(),
       _scorer = PlacementBayesianScorer(
         priorMedianWords: startingEstimate.toDouble(),
         maxRank: kPlacementEstimateMax,
       ) {
    estimate = _scorer.medianVocab;
  }

  final List<PlacementBandPool> bands;
  final int maxQuestions;
  final math.Random _random;
  final double _startEstimate;
  final PlacementBayesianScorer _scorer;

  late double estimate;
  int asked = 0;
  final Set<String> _usedWords = <String>{};
  double? _prevEstimate;

  /// Highest frequency-rank correctly answered (rarer = higher rank).
  int? maxCorrectRank;

  /// Lowest rank missed via wrong choice (not 「不认识」).
  int? minIncorrectRank;

  /// How many items were asked near/above the live estimate (stretch probes).
  int stretchProbes = 0;

  /// Consecutive corrects that were clearly below the live estimate.
  int easyCorrectStreak = 0;

  /// Posterior mean guessing rate (0–1).
  double get meanGuessRate => _scorer.meanGuess;

  bool get isComplete {
    if (_availableCount == 0) return true;
    if (asked >= maxQuestions) return true;
    // Stabilize after enough evidence + stretch probes.
    if (asked >= 24 && stretchProbes >= 3 && _movedLittle) return true;
    if (asked >= 20 &&
        stretchProbes >= 2 &&
        minIncorrectRank != null &&
        _movedLittle) {
      return true;
    }
    return false;
  }

  /// Soft cap so easy-only evidence cannot keep an inflated CEFR prior.
  double get _evidenceCeiling {
    final int? proven = maxCorrectRank;
    if (proven == null) {
      return math.max(300, _startEstimate * 0.55);
    }
    if (stretchProbes < 2) {
      return proven * 1.35;
    }
    if (stretchProbes < 3) {
      return proven * 1.55;
    }
    return kPlacementEstimateMax.toDouble();
  }

  int get finalEstimate {
    final double value = math.min(_scorer.medianVocab, _evidenceCeiling);
    return estimateVocabFromPlacementScore(value);
  }

  bool get _movedLittle {
    final double? prev = _prevEstimate;
    if (prev == null) return false;
    final double delta = (estimate - prev).abs();
    return delta < math.max(120, estimate * 0.03);
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
    required PlacementAnswerKind kind,
  }) {
    _usedWords.add(question.word.toLowerCase());
    _prevEstimate = estimate;
    asked += 1;
    final bool isStretch = question.rank >= estimate * 0.9;
    if (isStretch) {
      stretchProbes += 1;
    }

    switch (kind) {
      case PlacementAnswerKind.correct:
        maxCorrectRank = maxCorrectRank == null
            ? question.rank
            : math.max(maxCorrectRank!, question.rank);
        if (question.rank < estimate * 0.55) {
          easyCorrectStreak += 1;
        } else {
          easyCorrectStreak = 0;
        }
      case PlacementAnswerKind.wrong:
        easyCorrectStreak = 0;
        minIncorrectRank = minIncorrectRank == null
            ? question.rank
            : math.min(minIncorrectRank!, question.rank);
      case PlacementAnswerKind.unknown:
        easyCorrectStreak = 0;
    }

    _scorer.add(PlacementTrial(rank: question.rank, kind: kind));
    estimate = math
        .min(_scorer.medianVocab, _evidenceCeiling)
        .clamp(
          kPlacementEstimateMin.toDouble(),
          kPlacementEstimateMax.toDouble(),
        );
  }

  /// Backward-compatible helper used by older call sites / tests.
  void recordAnswerCorrectness({
    required PlacementQuestion question,
    required bool correct,
  }) {
    recordAnswer(
      question: question,
      kind: correct
          ? PlacementAnswerKind.correct
          : PlacementAnswerKind.wrong,
    );
  }

  bool get _shouldForceStretch =>
      asked >= 1 && (asked % 2 == 1 || easyCorrectStreak >= 2);

  PlacementBandPool? _pickBandNearEstimate() {
    if (bands.isEmpty) return null;
    PlacementBandPool? best;
    var bestScore = double.infinity;
    // Aim near half-knowledge rank m from the posterior when available.
    final double aimBase = _scorer.trials.isEmpty
        ? estimate
        : _scorer.medianM;
    final double aim = _shouldForceStretch ? aimBase * 1.45 : aimBase * 1.08;
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
      final double belowPenalty =
          _shouldForceStretch && band.hi < aimBase * 0.85 ? 900 : 0;
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
