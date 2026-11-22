import '../../reading/domain/reading_study_mode.dart';
import 'vocab_entry.dart';

/// Maps recognition vocabulary size → reading/video hard-word frontier.
///
/// Gloss / highlight words rarer than this rank (1 = most common). The frontier
/// tracks the learner so inline help and i+1 picks move with real level.
int freqThresholdForVocabEstimate(int? estimate) {
  final int e = (estimate ?? kReadingDefaultFreqThreshold).clamp(800, 30000);
  return nearestReadingFreqBand(e);
}

/// Snap any rank to the nearest UI band used by the reading slider.
int nearestReadingFreqBand(int rank) {
  final int r = rank.clamp(1, 50000);
  int best = kReadingFreqThresholdBands.first;
  int bestDist = (r - best).abs();
  for (final int band in kReadingFreqThresholdBands) {
    final int dist = (r - band).abs();
    if (dist < bestDist) {
      best = band;
      bestDist = dist;
    }
  }
  return best;
}

String cefrForVocabEstimate(int? estimate) {
  final int e = estimate ?? 3000;
  if (e < 800) return 'A1';
  if (e < 1500) return 'A2';
  if (e < 3000) return 'B1';
  if (e < 6000) return 'B2';
  if (e < 10000) return 'C1';
  return 'C2';
}

String cefrForFreqThreshold(int threshold) =>
    cefrFromFreqRank(threshold) ?? cefrForVocabEstimate(threshold);

/// i+1 efficiency for **new** learning: prefer lemmas just past the frontier.
///
/// Returns 0–1. Favorites / due reviews should bypass this and stay first.
double iPlus1LearnScore({
  required int? freqRank,
  required int threshold,
}) {
  if (freqRank == null || freqRank <= 0) {
    // Outside top-20k: stretch material, not the first pick.
    return 0.28;
  }
  final double t = threshold.toDouble().clamp(500, 30000);
  final double r = freqRank.toDouble();
  if (r <= t * 0.45) return 0.08; // far too easy
  if (r <= t * 0.85) return 0.32; // likely already known
  if (r <= t * 1.15) return 0.72; // frontier
  if (r <= t * 2.2) return 1.0; // sweet spot (classic i+1)
  if (r <= t * 3.5) return 0.55; // stretch
  return 0.18; // too hard for efficient new learning
}

/// Whether a lemma is in the efficient new-learn window for [threshold].
bool isIPlus1LearnTarget({
  required int? freqRank,
  required int threshold,
}) =>
    iPlus1LearnScore(freqRank: freqRank, threshold: threshold) >= 0.55;

int compareByIPlus1LearnPriority({
  required int? rankA,
  required int? rankB,
  required int threshold,
  int orderA = 0,
  int orderB = 0,
}) {
  final double scoreA = iPlus1LearnScore(freqRank: rankA, threshold: threshold);
  final double scoreB = iPlus1LearnScore(freqRank: rankB, threshold: threshold);
  final int byScore = scoreB.compareTo(scoreA);
  if (byScore != 0) return byScore;
  // Within the same band, easier (lower rank) first.
  final int ra = rankA ?? 1 << 20;
  final int rb = rankB ?? 1 << 20;
  final int byRank = ra.compareTo(rb);
  if (byRank != 0) return byRank;
  return orderA.compareTo(orderB);
}
