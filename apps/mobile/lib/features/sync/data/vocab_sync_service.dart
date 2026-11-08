import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../words/domain/sm2_scheduler.dart';
import '../../words/presentation/word_book_provider.dart';
import 'acquire_api_client.dart';

final Provider<VocabSyncService> vocabSyncServiceProvider =
    Provider<VocabSyncService>((Ref ref) {
      return VocabSyncService(ref);
    });

class VocabSyncService {
  VocabSyncService(this._ref);

  final Ref _ref;

  Future<void> pushEntry(WordEntry entry) async {
    try {
      await _ref.read(acquireApiClientProvider).upsertVocab(
        word: entry.word,
        context: entry.occurrences.isEmpty
            ? null
            : entry.occurrences.first.sentence,
        mastery: _masteryToApi(entry.mastery),
        ease: entry.ease,
        intervalDays: entry.intervalDays,
        repetitions: entry.repetitions,
        dueAt: entry.dueAtMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(entry.dueAtMs!),
      );
    } catch (_) {}
  }

  static String _masteryToApi(WordMastery mastery) {
    switch (mastery) {
      case WordMastery.fresh:
        return 'new';
      case WordMastery.learning:
        return 'learning';
      case WordMastery.known:
        return 'known';
      case WordMastery.mastered:
        return 'mastered';
    }
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
          mastery: Sm2Scheduler.masteryFromName(row.mastery),
          ease: row.ease,
          intervalDays: row.intervalDays,
          repetitions: row.repetitions,
          dueAtMs: row.dueAt?.millisecondsSinceEpoch,
          contextSentence: row.context,
        );
      }
    } catch (_) {}
  }
}
