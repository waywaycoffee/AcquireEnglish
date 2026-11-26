import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/data/acquire_api_client.dart';
import '../data/reading_cover_cache.dart';
import '../domain/reading_doc.dart';
import 'reading_library_provider.dart';

/// Background Open Library cover resolve for shelf books missing [coverUrl],
/// then pin jackets into Documents/reading_covers for local paint.
final readingCoverSyncProvider = Provider.autoDispose<void>((Ref ref) {
  final ReadingLibraryState library = ref.watch(readingLibraryProvider);
  if (!library.ready) return;

  unawaited(_syncCovers(ref, library.all));
});

Future<void> _syncCovers(Ref ref, List<ReadingDoc> all) async {
  final ReadingLibraryNotifier library =
      ref.read(readingLibraryProvider.notifier);

  // 1) Instant backfill for featured classics already seeded on ECS.
  for (final ReadingDoc d in all) {
    if (d.coverUrl.trim().isNotEmpty) continue;
    final String? relative = featuredReadingCoverRelativeForTitle(d.title);
    if (relative == null) continue;
    await library.updateCoverUrl(d.id, relative);
  }
  if (!ref.mounted) return;

  final ReadingLibraryState afterBackfill = ref.read(readingLibraryProvider);
  final List<ReadingDoc> missing = afterBackfill.all
      .where(
        (ReadingDoc d) =>
            d.coverUrl.trim().isEmpty && d.title.trim().isNotEmpty,
      )
      .take(24)
      .toList(growable: false);

  // 2) Ask API for any still-missing jackets.
  if (missing.isNotEmpty) {
    final AcquireApiClient api = ref.read(acquireApiClientProvider);
    final List<Map<String, dynamic>> books = <Map<String, dynamic>>[
      for (final ReadingDoc d in missing)
        <String, dynamic>{
          'doc_id': d.id,
          'title': d.title,
          'author': d.authorHint,
        },
    ];
    final Map<String, dynamic>? result = await api.ensureReadingCovers(
      books: books,
      seedClassics: true,
    );
    if (result != null && ref.mounted) {
      final Object? raw = result['covers'];
      if (raw is List) {
        for (final Object? item in raw) {
          if (item is! Map) continue;
          final Map<String, dynamic> row = Map<String, dynamic>.from(item);
          final String url = '${row['cover_url'] ?? ''}'.trim();
          if (url.isEmpty) continue;
          final String docId = '${row['doc_id'] ?? ''}'.trim();
          if (docId.isNotEmpty) {
            final bool matched = afterBackfill.all.any(
              (ReadingDoc d) => d.id == docId,
            );
            if (matched) {
              await library.updateCoverUrl(docId, url);
              continue;
            }
          }
          // Seed rows use se:… ids while catalog downloads use catalog_<hash>.
          final String title = '${row['title'] ?? ''}'.trim().toLowerCase();
          if (title.isEmpty) continue;
          for (final ReadingDoc d in ref.read(readingLibraryProvider).all) {
            if (d.coverUrl.trim().isNotEmpty) continue;
            final String local = d.title
                .replaceAll(RegExp(r'[\(（][^\)）]*[\)）]'), '')
                .trim()
                .toLowerCase();
            if (local == title ||
                local.contains(title) ||
                title.contains(local)) {
              await library.updateCoverUrl(d.id, url);
              break;
            }
          }
        }
      }
    }
  }

  if (!ref.mounted) return;

  // 3) Download every known jacket into Documents/reading_covers.
  final List<String> urls = ref
      .read(readingLibraryProvider)
      .all
      .map((ReadingDoc d) => d.coverUrl.trim())
      .where((String u) => u.isNotEmpty)
      .toList(growable: false);
  await prefetchReadingCovers(urls);
}
