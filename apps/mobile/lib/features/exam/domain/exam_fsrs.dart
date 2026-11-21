import '../../words/domain/syllabus_book.dart';
import 'exam_registry.dart';

/// Stable tag prefix written onto word-book entries for exam-mode filtering.
String examTagForFamily(String familyId) => 'exam:$familyId';

/// Whether a syllabus book belongs to the selected exam family.
bool syllabusMatchesExamFamily(SyllabusBook book, ExamFamily family) {
  final String tag = book.examTag.trim().toUpperCase();
  if (tag.isEmpty) return false;
  for (final String candidate in family.syllabusExamTags) {
    if (tag == candidate.toUpperCase() || tag.contains(candidate.toUpperCase())) {
      return true;
    }
  }
  // Fallback: family id fragment (e.g. CET4 / IELTS).
  final String id = family.id.toUpperCase();
  if (tag.contains(id.replaceAll('_', ''))) return true;
  if (id.startsWith('K12') && (tag.contains('K12') || tag.contains('PRIMARY'))) {
    return true;
  }
  return false;
}

List<SyllabusBook> filterSyllabusForExam(
  Iterable<SyllabusBook> books,
  ExamFamily? family,
) {
  if (family == null) return books.toList(growable: false);
  return books
      .where((SyllabusBook b) => syllabusMatchesExamFamily(b, family))
      .toList(growable: false);
}

/// Word-book entry tags considered part of an exam FSRS session.
bool entryHasExamTag(Iterable<String> tags, String familyId) {
  final String want = examTagForFamily(familyId);
  final String upperFamily = familyId.toUpperCase();
  for (final String raw in tags) {
    final String t = raw.trim();
    if (t == want) return true;
    if (t.toUpperCase() == upperFamily) return true;
    if (t.toUpperCase().startsWith('EXAM:') &&
        t.toUpperCase().endsWith(upperFamily)) {
      return true;
    }
  }
  return false;
}
