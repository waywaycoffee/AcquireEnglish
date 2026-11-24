import 'dart:math' as math;

/// Placement test reportable range (word forms).
const int kPlacementEstimateMin = 100;
const int kPlacementEstimateMax = 60000;

/// Max MCQ definition buttons per item (not counting 「不认识」).
const int kPlacementMaxChoices = 4;

/// Convert weighted placement score → snapped vocabulary estimate.
///
/// Score is the sum of `band.size / itemsInBand` for each correct item.
/// Always reports at least [kPlacementEstimateMin] after a finished test so
/// beginner levels are visible; caps above 20k when high bands are cleared.
int estimateVocabFromPlacementScore(double score) {
  final int rounded = (score / 100).round() * 100;
  return rounded.clamp(kPlacementEstimateMin, kPlacementEstimateMax);
}

/// Build MCQ options: correct + up to 3 distractors ([kPlacementMaxChoices] total).
///
/// Returns null when there is no usable correct answer or no distractor.
List<String>? buildPlacementChoices({
  required String correctDefinition,
  required Iterable<String> candidateDefinitions,
  int maxChoices = kPlacementMaxChoices,
  math.Random? random,
}) {
  final String correct = correctDefinition.trim();
  if (correct.isEmpty || maxChoices < 2) {
    return null;
  }
  final math.Random rng = random ?? math.Random();
  final List<String> distractors = candidateDefinitions
      .map((String value) => value.trim())
      .where((String value) => value.isNotEmpty && value != correct)
      .toSet()
      .toList()
    ..shuffle(rng);
  if (distractors.isEmpty) {
    return null;
  }
  final int distractorCount = (maxChoices - 1).clamp(1, distractors.length);
  return <String>[correct, ...distractors.take(distractorCount)]..shuffle(rng);
}
