import 'dart:math' as math;

import 'vocabulary_placement_estimate.dart';

/// Answer kinds for ARealMe-style MCQ + 「不认识」 scoring.
enum PlacementAnswerKind {
  /// Chose the keyed meaning.
  correct,

  /// Chose a wrong meaning (evidence of guessing).
  wrong,

  /// Chose 「不认识」 (no guess).
  unknown,
}

/// One observed item for the receptive vocabulary curve.
class PlacementTrial {
  const PlacementTrial({required this.rank, required this.kind});

  final int rank;
  final PlacementAnswerKind kind;
}

/// Logistic knowledge curve: P(rank) with midpoint [m] and steepness [s].
double placementKnowProb({
  required double rank,
  required double m,
  required double s,
}) {
  final double r = rank.clamp(1.0, 1e9);
  final double mid = m.clamp(1.0, 1e9);
  final double steep = s.clamp(0.05, 10.0);
  return 1.0 / (1.0 + math.exp(steep * (math.log(r) - math.log(mid))));
}

/// Approximate counted vocabulary size V(m,s) via log-rank bins.
///
/// Mirrors ARealMe §6 without shipping the full lemma list: integrate P(r)
/// from rank 1…[maxRank] on a log grid (eligibility ≈ 1).
double placementVocabSize({
  required double m,
  required double s,
  int maxRank = kPlacementEstimateMax,
  int bins = 200,
}) {
  final double loLog = math.log(1.0);
  final double hiLog = math.log(maxRank.toDouble());
  final double step = (hiLog - loLog) / bins;
  double sum = 0;
  for (var i = 0; i < bins; i++) {
    final double a = math.exp(loLog + i * step);
    final double b = math.exp(loLog + (i + 1) * step);
    final double mid = math.sqrt(a * b);
    sum += (b - a) * placementKnowProb(rank: mid, m: m, s: s);
  }
  return sum;
}

double _logLikelihood({
  required PlacementTrial trial,
  required double m,
  required double s,
  required double g,
}) {
  final double p = placementKnowProb(
    rank: trial.rank.toDouble(),
    m: m,
    s: s,
  );
  final double guess = g.clamp(0.0, 1.0);
  const double slip = 0.03;
  final double prCorrect = p * (1 - slip) + (1 - p) * guess * 0.25;
  final double prWrong = p * slip + (1 - p) * guess * 0.75;
  final double prUnknown = (1 - p) * (1 - guess);
  switch (trial.kind) {
    case PlacementAnswerKind.correct:
      return math.log(prCorrect.clamp(1e-12, 1.0));
    case PlacementAnswerKind.wrong:
      return math.log(prWrong.clamp(1e-12, 1.0));
    case PlacementAnswerKind.unknown:
      return math.log(prUnknown.clamp(1e-12, 1.0));
  }
}

/// Posterior over (m, s, g) on a coarse grid; report median V and live m.
class PlacementBayesianScorer {
  PlacementBayesianScorer({
    double priorMedianWords = 6000,
    this.maxRank = kPlacementEstimateMax,
  }) : _priorLnM = math.log(priorMedianWords.clamp(100.0, 40000.0)) {
    medianVocab = priorMedianWords.clamp(
      kPlacementEstimateMin.toDouble(),
      maxRank.toDouble(),
    );
    medianM = medianVocab;
  }

  final int maxRank;
  final double _priorLnM;
  static const double _priorLnMSigma = 2.5;

  final List<PlacementTrial> trials = <PlacementTrial>[];

  /// Live estimate of vocabulary size (posterior median of V).
  double medianVocab = 1600;

  /// Live half-knowledge rank m (posterior mean weighted).
  double medianM = 1600;

  /// Posterior mean guessing rate.
  double meanGuess = 0.25;

  void add(PlacementTrial trial) {
    trials.add(trial);
    _recompute();
  }

  void _recompute() {
    // Grid kept modest for mobile: ~56 × 8 × 6 ≈ 2700 cells.
    const int lnMSteps = 56;
    const double lnMLo = 2.995732; // ln 20
    const double lnMHi = 12.89922; // ln 400000
    const double sLo = 0.4;
    const double sHi = 3.2;
    const double sStep = 0.4;
    const double gStep = 0.2;

    final List<double> logWeights = <double>[];
    final List<double> vs = <double>[];
    final List<double> ms = <double>[];
    final List<double> gs = <double>[];
    var maxLog = -double.infinity;

    for (var i = 0; i < lnMSteps; i++) {
      final double lnM = lnMLo + (lnMHi - lnMLo) * i / (lnMSteps - 1);
      final double m = math.exp(lnM);
      final double priorLn =
          -0.5 * math.pow((lnM - _priorLnM) / _priorLnMSigma, 2);
      for (double s = sLo; s <= sHi + 1e-9; s += sStep) {
        for (double g = 0; g <= 1.0 + 1e-9; g += gStep) {
          var logW = priorLn;
          for (final PlacementTrial trial in trials) {
            logW += _logLikelihood(trial: trial, m: m, s: s, g: g);
          }
          logWeights.add(logW);
          vs.add(placementVocabSize(m: m, s: s, maxRank: maxRank));
          ms.add(m);
          gs.add(g);
          if (logW > maxLog) maxLog = logW;
        }
      }
    }

    if (logWeights.isEmpty || maxLog.isInfinite) {
      medianVocab = math.exp(_priorLnM);
      medianM = medianVocab;
      meanGuess = 0.25;
      return;
    }

    final List<({double weight, double v, double m, double g})> cells =
        <({double weight, double v, double m, double g})>[];
    var weightSum = 0.0;
    for (var i = 0; i < logWeights.length; i++) {
      final double w = math.exp(logWeights[i] - maxLog);
      cells.add((weight: w, v: vs[i], m: ms[i], g: gs[i]));
      weightSum += w;
    }

    cells.sort((a, b) => a.v.compareTo(b.v));
    var cum = 0.0;
    var medV = cells.last.v;
    for (final cell in cells) {
      cum += cell.weight;
      if (cum >= weightSum * 0.5) {
        medV = cell.v;
        break;
      }
    }

    var mAcc = 0.0;
    var gAcc = 0.0;
    for (final cell in cells) {
      final double p = cell.weight / weightSum;
      mAcc += p * cell.m;
      gAcc += p * cell.g;
    }

    medianVocab = medV.clamp(
      kPlacementEstimateMin.toDouble(),
      maxRank.toDouble(),
    );
    medianM = mAcc.clamp(1.0, maxRank.toDouble());
    meanGuess = gAcc.clamp(0.0, 1.0);
  }
}
