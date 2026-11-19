import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
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

  Future<bool> pushEntry(PhraseEntry entry) async {
    try {
      await _ref.read(acquireApiClientProvider).upsertPhrase(_toDto(entry));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<({int uploaded, int failed})> pushAll() async {
    final List<PhraseEntry> rows = _ref.read(phraseBookProvider);
    final String token = _ref.read(authSessionProvider).accessToken;
    int ok = 0;
    for (final PhraseEntry entry in rows) {
      if (token.isEmpty || _ref.read(authSessionProvider).accessToken != token)
        break;
      if (await pushEntry(entry)) ok++;
    }
    return (uploaded: ok, failed: rows.length - ok);
  }

  Future<void> pullAndMerge() async {
    final String token = _ref.read(authSessionProvider).accessToken;
    if (token.isEmpty) return;
    try {
      final List<AcquirePhraseDto> remote = await _ref
          .read(acquireApiClientProvider)
          .listPhrases();
      if (remote.isEmpty ||
          _ref.read(authSessionProvider).accessToken != token) {
        return;
      }
      await _ref.read(phraseBookProvider.notifier).mergeRemotePhrases(remote);
    } catch (_) {}
  }
}
