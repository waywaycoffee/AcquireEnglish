import 'dart:math' as math;

/// Placement test reportable range (receptive dictionary headwords / lemmas).
///
/// Ceiling follows ARealMe counted-word scale (~38k after eligibility), not
/// raw SUBTLEX form ranks.
const int kPlacementEstimateMin = 100;
const int kPlacementEstimateMax = 38000;

/// Max MCQ definition buttons per item (not counting 「不认识」).
const int kPlacementMaxChoices = 4;

/// Snap vocabulary estimate for display / persistence.
int estimateVocabFromPlacementScore(double score) {
  final double clamped = score.clamp(
    kPlacementEstimateMin.toDouble(),
    kPlacementEstimateMax.toDouble(),
  );
  if (clamped < 10000) {
    return ((clamped / 10).round() * 10).clamp(
      kPlacementEstimateMin,
      kPlacementEstimateMax,
    );
  }
  return ((clamped / 100).round() * 100).clamp(
    kPlacementEstimateMin,
    kPlacementEstimateMax,
  );
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
