import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/account_storage.dart';
import '../../settings/presentation/settings_provider.dart';
import '../data/reading_catalog.dart';
import '../domain/reading_doc.dart';
import 'reading_library_provider.dart';

final readingColdStartProvider = FutureProvider<void>((ref) async {
  final account = ref.watch(studyAccountProvider);
  final base = ref.watch(learningSettingsProvider).resolvedCloudApiBaseUrl;
  ref.read(readingLibraryProvider);
  for (int i = 0; i < 40 && !ref.read(readingLibraryProvider).ready; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!ref.mounted) return;
  }
  if (!ref.mounted || !ref.read(readingLibraryProvider).ready) return;

  // Personal shelf cold-start: only ensure 绿野仙踪. Do not inject starter /
  // course-seed demo articles onto「我的书架」.
  final bool hasWizardOfOz = ref
      .read(readingLibraryProvider)
      .userDocs
      .any(
        (ReadingDoc doc) =>
            doc.id == kDefaultWizardOfOzEntry.stableDocId ||
            doc.id.toLowerCase().contains('wizard-of-oz') ||
            '${doc.title}${doc.titleZh}'.contains('绿野仙踪'),
      );
  if (hasWizardOfOz) return;
  try {
    final client = ReadingCatalogClient(apiBaseUrl: base);
    final ReadingDoc book = await client.downloadEntry(
      kind: ReadingCatalogKind.standardebooks,
      entry: kDefaultWizardOfOzEntry,
    );
    if (!ref.mounted || account != ref.read(studyAccountProvider)) return;
    await ref.read(readingLibraryProvider.notifier).addDoc(
          book,
          checkQuota: false,
        );
  } catch (_) {
    // Offline: shelf stays empty until catalog download succeeds.
  }
});
