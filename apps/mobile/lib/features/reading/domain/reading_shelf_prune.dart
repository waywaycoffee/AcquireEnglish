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

/// Drop demo seeds; keep 绿野仙踪、哈利波特等真实导入/书目。
List<ReadingDoc> dropGeneratedTestReadingDocs(Iterable<ReadingDoc> docs) {
  return docs.where((ReadingDoc d) => !isGeneratedTestReadingDoc(d)).toList();
}

/// Prefer a single Oz entry when duplicates exist (catalog_… vs se:…).
List<ReadingDoc> dedupeWizardOfOz(Iterable<ReadingDoc> docs) {
  final List<ReadingDoc> list = docs.toList();
  final List<ReadingDoc> oz = list.where(isWizardOfOzReadingDoc).toList();
  if (oz.length <= 1) return list;
  final String preferredId = kDefaultWizardOfOzEntry.stableDocId;
  ReadingDoc keep = oz.first;
  for (final ReadingDoc doc in oz) {
    if (doc.id == preferredId) {
      keep = doc;
      break;
    }
  }
  return <ReadingDoc>[
    for (final ReadingDoc doc in list)
      if (!isWizardOfOzReadingDoc(doc) || doc.id == keep.id) doc,
  ];
}

List<ReadingDoc> prunePersonalReadingShelf(Iterable<ReadingDoc> docs) {
  return dedupeWizardOfOz(dropGeneratedTestReadingDocs(docs));
}
