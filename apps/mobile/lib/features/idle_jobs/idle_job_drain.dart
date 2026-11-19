import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../subtitle_completion/subtitle_completion_scheduler.dart';
import '../sync/presentation/cloud_catalog_sync.dart';
import '../words/data/vocab_card_enrichment_service.dart';
import '../words/domain/vocab_card_kind.dart';
import '../words/presentation/word_book_provider.dart';
import 'idle_job_queue.dart';

/// Drain pending idle jobs while the app process is alive (resume / FGS).
Future<void> drainIdleJobs(WidgetRef ref) async {
  if (!idleJobsEnabled()) return;
  final List<IdleJob> pending = IdleJobQueue.shared.pending;
  if (pending.isEmpty) {
    SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
    return;
  }

  for (final IdleJob job in pending) {
    switch (job.kind) {
      case IdleJobKind.subtitleDrain:
        SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
        await IdleJobQueue.shared.markDone(job.id);
      case IdleJobKind.modelPrefetch:
        await IdleJobQueue.shared.markDone(job.id);
      case IdleJobKind.vocabEnrich:
        await _drainVocabEnrich(ref, job);
      case IdleJobKind.cloudSync:
        try {
          await syncCloudCatalogAndFeed(ref);
          await IdleJobQueue.shared.markDone(job.id);
        } catch (error) {
          await IdleJobQueue.shared.markFailed(job.id, '$error');
        }
    }
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
