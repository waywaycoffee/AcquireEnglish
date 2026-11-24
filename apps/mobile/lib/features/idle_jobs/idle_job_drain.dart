import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../import_course/data/netdisk_drama_reservation.dart';
import '../library/presentation/library_catalog_provider.dart';
import '../subtitle_completion/subtitle_completion_scheduler.dart';
import '../sync/presentation/cloud_catalog_sync.dart';
import '../words/data/vocab_card_enrichment_service.dart';
import '../words/domain/vocab_card_kind.dart';
import '../words/presentation/word_book_provider.dart';
import 'idle_job_queue.dart';
import 'idle_job_scheduler.dart';

bool _idleDrainRunning = false;

/// After booking a drama episode, start download now (Workmanager is backup).
void kickNetdiskDramaIdleDrain(WidgetRef ref) {
  final LibraryCatalogNotifier catalog =
      ref.read(libraryCatalogProvider.notifier);
  unawaited(() async {
    // Do not await Workmanager — it can hang and block the download kick.
    unawaited(scheduleIdleJobs());
    final List<IdleJob> dramaJobs = IdleJobQueue.shared.pending
        .where((IdleJob j) => j.kind == IdleJobKind.netdiskDrama)
        .toList(growable: false);
    for (final IdleJob job in dramaJobs) {
      await ensureReservedNetdiskDramaDownload(
        episodeId: job.key,
        catalog: catalog,
      );
    }
    if (idleJobsEnabled()) {
      await drainIdleJobs(ref);
    }
  }());
}

/// Drain pending idle jobs while the app process is alive (resume / FGS).
Future<void> drainIdleJobs(WidgetRef ref) async {
  if (_idleDrainRunning) return;
  _idleDrainRunning = true;
  try {
    final LibraryCatalogNotifier catalog =
        ref.read(libraryCatalogProvider.notifier);

    // Always process reserved drama downloads — independent of idle toggle.
    final IdleJob? drama = IdleJobQueue.shared.pending
        .where((IdleJob j) => j.kind == IdleJobKind.netdiskDrama)
        .firstOrNull;
    if (drama != null) {
      await ensureReservedNetdiskDramaDownload(
        episodeId: drama.key,
        catalog: catalog,
      );
      final bool moreDrama = IdleJobQueue.shared.pending.any(
        (IdleJob j) => j.kind == IdleJobKind.netdiskDrama,
      );
      if (moreDrama) {
        unawaited(scheduleIdleJobs());
        unawaited(
          Future<void>.delayed(const Duration(seconds: 2), () {
            unawaited(drainIdleJobs(ref));
          }),
        );
      }
    }

    if (!idleJobsEnabled()) {
      return;
    }

    final List<IdleJob> pending = IdleJobQueue.shared.pending;
    if (pending.isEmpty) {
      SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
      return;
    }

    for (final IdleJob job in pending) {
      switch (job.kind) {
        case IdleJobKind.netdiskDrama:
          continue;
        case IdleJobKind.subtitleDrain:
          SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
          await IdleJobQueue.shared.markDone(job.id);
        case IdleJobKind.modelPrefetch:
          await IdleJobQueue.shared.markDone(job.id);
        case IdleJobKind.vocabEnrich:
          await _drainVocabEnrich(ref, job);
        case IdleJobKind.cloudSync:
          try {
            await syncCloudCatalogAndFeed(ref, pushLocal: true);
            await IdleJobQueue.shared.markDone(job.id);
          } catch (error) {
            await IdleJobQueue.shared.markFailed(job.id, '$error');
          }
      }
    }
  } finally {
    _idleDrainRunning = false;
  }
}

Future<void> _drainVocabEnrich(WidgetRef ref, IdleJob job) async {
  final String word = job.key.startsWith('demo:')
      ? job.key.substring(5)
      : job.key;
  try {
    final List<WordEntry> entries = ref.read(wordBookProvider);
    WordEntry? entry;
    for (final WordEntry item in entries) {
      if (item.word == word || item.word == normalizeLexeme(word)) {
        entry = item;
        break;
      }
    }
    if (entry == null || !entry.favorite) {
      await IdleJobQueue.shared.markDone(job.id);
      return;
    }
    if (entry.enrichmentStatus == VocabEnrichmentStatus.ready &&
        (entry.mnemonicCn ?? '').trim().isNotEmpty) {
      await IdleJobQueue.shared.markDone(job.id);
      return;
    }
    final bool ok = await ref
        .read(vocabCardEnrichmentServiceProvider)
        .enrichFavorite(
          rawWord: entry.word,
          contextSentence: entry.sourceSentence,
          contextChinese: entry.sourceSentenceCn,
        );
    if (ok) {
      await IdleJobQueue.shared.markDone(job.id);
    } else {
      await IdleJobQueue.shared.markFailed(job.id, 'enrich returned false');
    }
  } catch (error) {
    await IdleJobQueue.shared.markFailed(job.id, '$error');
  }
}
