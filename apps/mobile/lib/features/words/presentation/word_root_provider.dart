import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/word_root_catalog.dart';
import '../domain/word_root_models.dart';

final FutureProvider<WordRootCatalog> wordRootCatalogProvider =
    FutureProvider<WordRootCatalog>((Ref ref) => WordRootCatalog.load());

final wordRootDetailProvider =
    Provider.family<WordRootDetail?, String>((Ref ref, String word) {
  final AsyncValue<WordRootCatalog> catalog = ref.watch(wordRootCatalogProvider);
  return catalog.maybeWhen(
    data: (WordRootCatalog c) => c.queryWordDetail(word),
    orElse: () => null,
  );
});
