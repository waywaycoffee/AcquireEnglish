import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../words/presentation/word_book_provider.dart';
import 'acquire_api_client.dart';

final Provider<VocabSyncService> vocabSyncServiceProvider =
    Provider<VocabSyncService>((Ref ref) {
      return VocabSyncService(ref);
    });

/// Cloud vocab is a **favorite mirror** only.
/// Local FSRS daily review remains the source of truth for scheduling.
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
        // Keep API fields populated for older clients, but do not drive local SRS.
        mastery: 'new',
        ease: 2.5,
        intervalDays: 0,
        repetitions: 0,
        dueAt: null,
      );
    } catch (_) {}
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
        await book.mergeRemoteFavorite(
          word: row.word,
          contextSentence: row.context,
        );
      }
    } catch (_) {}
  }
}
