import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../words/domain/sm2_scheduler.dart';
import '../../words/presentation/word_book_provider.dart';
import 'acquire_api_client.dart';

final Provider<VocabSyncService> vocabSyncServiceProvider =
    Provider<VocabSyncService>((Ref ref) {
      return VocabSyncService(ref);
    });

/// Cloud vocab mirrors favorites **and** SM-2 scheduling fields.
class VocabSyncService {
  VocabSyncService(this._ref);

  final Ref _ref;

  Future<void> pushEntry(WordEntry entry) async {
    if (!entry.favorite) {
      return;
    }
    try {
      await _ref.read(acquireApiClientProvider).upsertVocab(
        word: entry.word,
        context: entry.occurrences.isEmpty
            ? null
            : entry.occurrences.first.sentence,
        mastery: entry.mastery.name,
        ease: entry.ease,
        intervalDays: entry.intervalDays,
        repetitions: entry.repetitions,
        dueAt: entry.dueAtMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(entry.dueAtMs!),
      );
    } catch (_) {}
  }

  /// Push every local favorite (used by settings “备份同步”).
  Future<int> pushAllFavorites() async {
    final List<WordEntry> favorites = _ref
        .read(wordBookProvider)
        .where((WordEntry e) => e.favorite)
        .toList(growable: false);
    int ok = 0;
    for (final WordEntry entry in favorites) {
      try {
        await pushEntry(entry);
        ok += 1;
      } catch (_) {}
    }
    return ok;
  }

  Future<void> pullAndMerge() async {
    try {
      final List<AcquireVocabDto> remote = await _ref
          .read(acquireApiClientProvider)
          .listVocab();
      if (remote.isEmpty) {
        return;
      }
      final WordBookNotifier book = _ref.read(wordBookProvider.notifier);
      for (final AcquireVocabDto row in remote) {
        await book.mergeRemoteSrs(
          word: row.word,
          mastery: _parseMastery(row.mastery),
          ease: row.ease,
          intervalDays: row.intervalDays,
          repetitions: row.repetitions,
          dueAtMs: row.dueAt?.millisecondsSinceEpoch,
          contextSentence: row.context,
        );
      }
    } catch (_) {}
  }

  WordMastery _parseMastery(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'learning':
        return WordMastery.learning;
      case 'known':
        return WordMastery.known;
      case 'mastered':
        return WordMastery.mastered;
      case 'new':
      case 'fresh':
      default:
        return WordMastery.fresh;
    }
  }
}
