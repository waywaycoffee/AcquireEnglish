import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../phrases/presentation/phrase_book_provider.dart';
import 'acquire_api_client.dart';

final Provider<PhraseSyncService> phraseSyncServiceProvider =
    Provider<PhraseSyncService>((Ref ref) {
      return PhraseSyncService(ref);
    });

class PhraseSyncService {
  PhraseSyncService(this._ref);

  final Ref _ref;

  AcquirePhraseDto _toDto(PhraseEntry entry) => AcquirePhraseDto(
    clientId: entry.id,
    english: entry.english,
    chinese: entry.chinese,
    course: entry.course,
    episode: entry.episode,
    time: entry.time,
    courseId: entry.courseId,
    episodeId: entry.episodeId,
    startTime: entry.startTime,
    endTime: entry.endTime,
    note: entry.note,
    rating: entry.rating,
    needsReview: entry.needsReview,
    reviewCount: entry.reviewCount,
    lapseCount: entry.lapseCount,
    collectedAt: DateTime.tryParse(entry.collectedAt ?? ''),
    lastReviewedAt: DateTime.tryParse(entry.lastReviewedAt ?? ''),
    nextReviewAt: DateTime.tryParse(entry.nextReviewAt ?? ''),
  );

  Future<void> pushEntry(PhraseEntry entry) async {
    try {
      await _ref.read(acquireApiClientProvider).upsertPhrase(_toDto(entry));
    } catch (_) {}
  }

  Future<int> pushAll() async {
    final List<PhraseEntry> rows = _ref.read(phraseBookProvider);
    int ok = 0;
    for (final PhraseEntry entry in rows) {
      try {
        await pushEntry(entry);
        ok += 1;
      } catch (_) {}
    }
    return ok;
  }

  Future<void> pullAndMerge() async {
    try {
      final List<AcquirePhraseDto> remote =
          await _ref.read(acquireApiClientProvider).listPhrases();
      if (remote.isEmpty) {
        return;
      }
      await _ref.read(phraseBookProvider.notifier).mergeRemotePhrases(remote);
    } catch (_) {}
  }
}
