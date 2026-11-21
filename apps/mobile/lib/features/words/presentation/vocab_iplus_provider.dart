import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/vocab_entry.dart';
import 'word_book_provider.dart';

const List<String> _cefrOrder = <String>[
  'A1',
  'A2',
  'B1',
  'B2',
  'C1',
  'C2',
];

/// Suggest a library CEFR filter from the learner's active word book (i+1).
final Provider<String?> suggestedLibraryCefrProvider = Provider<String?>((
  Ref ref,
) {
  final List<WordEntry> active = ref
      .watch(wordBookProvider)
      .where((WordEntry e) => e.isSchedulable)
      .toList(growable: false);
  if (active.isEmpty) return null;
  final Map<String, int> counts = <String, int>{};
  for (final WordEntry entry in active) {
    final String? cefr = entry.cefr ?? cefrFromFreqRank(entry.freqRank);
    if (cefr == null) continue;
    counts[cefr] = (counts[cefr] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  String? best;
  int bestCount = -1;
  for (final String level in _cefrOrder) {
    final int n = counts[level] ?? 0;
    if (n > bestCount) {
      best = level;
      bestCount = n;
    }
  }
  if (best == null) return null;
  // i+1: nudge one band harder when the peak is already solid.
  final int idx = _cefrOrder.indexOf(best);
  if (idx >= 0 && idx < _cefrOrder.length - 1 && bestCount >= 20) {
    return _cefrOrder[idx + 1];
  }
  return best;
});
