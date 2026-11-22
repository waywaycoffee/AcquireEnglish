/// Placement test reportable range (word forms).
const int kPlacementEstimateMin = 100;
const int kPlacementEstimateMax = 60000;

/// Convert weighted placement score → snapped vocabulary estimate.
///
/// Score is the sum of `band.size / itemsInBand` for each correct item.
/// Always reports at least [kPlacementEstimateMin] after a finished test so
/// beginner levels are visible; caps above 20k when high bands are cleared.
int estimateVocabFromPlacementScore(double score) {
  final int rounded = (score / 100).round() * 100;
  return rounded.clamp(kPlacementEstimateMin, kPlacementEstimateMax);
}
