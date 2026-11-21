import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'learned_vocabulary_provider.dart';
import 'vocabulary_placement_provider.dart';

/// Live vocabulary-size estimate for the review hub.
///
/// Uses placement baseline when available, then folds in locally learned lemmas
/// (收藏 + FSRS + 词书熟词) without double-counting placement `learnedWords`.
final Provider<int?> estimatedVocabularyProvider = Provider<int?>((Ref ref) {
  final PlacementRow profile = ref.watch(vocabularyPlacementProvider);
  final int? estimate = profile['estimate'] as int?;
  final Set<String> afterTest = <String>{
    for (final dynamic item
        in profile['learnedWords'] as List<dynamic>? ?? const <dynamic>[])
      '$item'.trim().toLowerCase(),
  }..remove('');
  final Set<String> local = ref.watch(learnedVocabularyProvider);
  final Set<String> combined = <String>{...afterTest, ...local}..remove('');
  if (estimate == null) {
    return combined.isEmpty ? null : combined.length;
  }
  return estimate + combined.length;
});
