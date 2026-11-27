import '../data/reading_catalog.dart';
import 'reading_doc.dart';

/// True for Wizard of Oz shelf entries (catalog hash id or SE path id).
bool isWizardOfOzReadingDoc(ReadingDoc doc) {
  final String id = doc.id.trim().toLowerCase();
  if (id == kDefaultWizardOfOzEntry.stableDocId.toLowerCase()) return true;
  if (id.contains('wizard-of-oz') || id.contains('wizard_of_oz')) return true;
  final String title =
      '${doc.title} ${doc.titleZh}'.toLowerCase().replaceAll('·', ' ');
  return title.contains('绿野仙踪') || title.contains('wizard of oz');
}

/// Free-trial / demo seeds that should not clutter「我的书架」.
bool isGeneratedTestReadingDoc(ReadingDoc doc) {
  final String id = doc.id.trim();
  if (id.startsWith('starter-')) return true;
  if (id.startsWith('course-seed-')) return true;
  if (id.startsWith('import_') && doc.title.toLowerCase().contains('sample')) {
    return true;
  }
  return false;
}

/// Keep only Wizard of Oz (dedupe if both catalog_… and se:… exist).
List<ReadingDoc> keepOnlyWizardOfOz(Iterable<ReadingDoc> docs) {
  final List<ReadingDoc> oz = docs.where(isWizardOfOzReadingDoc).toList();
  if (oz.isEmpty) return const <ReadingDoc>[];
  // Prefer the Standard Ebooks stable catalog id when both exist.
  final String preferredId = kDefaultWizardOfOzEntry.stableDocId;
  for (final ReadingDoc doc in oz) {
    if (doc.id == preferredId) return <ReadingDoc>[doc];
  }
  return <ReadingDoc>[oz.first];
}
