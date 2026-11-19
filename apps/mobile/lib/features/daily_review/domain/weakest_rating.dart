import 'package:fsrs/fsrs.dart' as fsrs;

/// Lower ordinal = weaker recall (Again < Hard < Good < Easy).
fsrs.Rating weakestRating(Iterable<fsrs.Rating> ratings) {
  fsrs.Rating? weakest;
  for (final fsrs.Rating rating in ratings) {
    if (weakest == null || rating.index < weakest.index) {
      weakest = rating;
    }
  }
  return weakest ?? fsrs.Rating.again;
}

fsrs.Rating ratingFromSpellResult({
  required bool correct,
  required bool hadMistake,
}) {
  if (!correct) return fsrs.Rating.again;
  return hadMistake ? fsrs.Rating.hard : fsrs.Rating.good;
}

fsrs.Rating ratingFromPronunciationScore(double? score) {
  if (score == null) return fsrs.Rating.good;
  if (score < 55) return fsrs.Rating.again;
  if (score < 70) return fsrs.Rating.hard;
  if (score < 88) return fsrs.Rating.good;
  return fsrs.Rating.easy;
}
