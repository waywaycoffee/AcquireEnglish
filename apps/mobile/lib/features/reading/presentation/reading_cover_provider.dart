import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/data/acquire_api_client.dart';
import '../domain/reading_doc.dart';
import 'reading_library_provider.dart';

/// Background Open Library cover resolve for shelf books missing [coverUrl].
final readingCoverSyncProvider = Provider.autoDispose<void>((Ref ref) {
  final ReadingLibraryState library = ref.watch(readingLibraryProvider);
  if (!library.ready) return;

  final List<ReadingDoc> missing = library.all
      .where((ReadingDoc d) => d.coverUrl.trim().isEmpty && d.title.trim().isNotEmpty)
      .take(24)
      .toList(growable: false);
  if (missing.isEmpty) return;

  unawaited(_ensureCovers(ref, missing));
});

Future<void> _ensureCovers(Ref ref, List<ReadingDoc> docs) async {
  final AcquireApiClient api = ref.read(acquireApiClientProvider);
  final List<Map<String, dynamic>> books = <Map<String, dynamic>>[
    for (final ReadingDoc d in docs)
      <String, dynamic>{
        'doc_id': d.id,
        'title': d.title,
        'author': d.authorHint,
      },
  ];
  // Also seed featured classics so empty shelves still get jackets ready.
  final Map<String, dynamic>? result = await api.ensureReadingCovers(
    books: books,
    seedClassics: true,
  );
  if (result == null || !ref.mounted) return;
  final Object? raw = result['covers'];
  if (raw is! List) return;
  final ReadingLibraryNotifier library =
      ref.read(readingLibraryProvider.notifier);
  for (final Object? item in raw) {
    if (item is! Map) continue;
    final Map<String, dynamic> row = Map<String, dynamic>.from(item);
    final String url = '${row['cover_url'] ?? ''}'.trim();
    if (url.isEmpty) continue;
    final String docId = '${row['doc_id'] ?? ''}'.trim();
    if (docId.isNotEmpty) {
      await library.updateCoverUrl(docId, url);
      continue;
    }
    // Match by normalized title when doc_id missing (classic seed rows).
    final String title = '${row['title'] ?? ''}'.trim().toLowerCase();
    if (title.isEmpty) continue;
    for (final ReadingDoc d in ref.read(readingLibraryProvider).all) {
      if (d.coverUrl.trim().isNotEmpty) continue;
      final String local = d.title
          .replaceAll(RegExp(r'[\(（][^\)）]*[\)）]'), '')
          .trim()
          .toLowerCase();
      if (local == title || local.contains(title) || title.contains(local)) {
        await library.updateCoverUrl(d.id, url);
        break;
      }
    }
  }
}
