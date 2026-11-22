import 'course_plan.dart';
import 'course_word_extract.dart';

/// Split plain text into sentences, protecting Mr./e.g./decimals.
List<String> splitReadingSentences(String text) {
  final String normalized = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();
  if (normalized.isEmpty) return const <String>[];

  // Protect common abbreviations / decimals before splitting on .?! 
  final Map<String, String> holders = <String, String>{};
  int hold = 0;
  String work = normalized;
  work = work.replaceAllMapped(
    RegExp(
      r'\b(?:Mr|Mrs|Ms|Dr|Prof|Sr|Jr|vs|etc|e\.g|i\.e|U\.S|U\.K)\.',
      caseSensitive: false,
    ),
    (Match m) {
      final String key = '⟦AB$hold⟧';
      hold += 1;
      holders[key] = m.group(0)!;
      return key;
    },
  );
  work = work.replaceAllMapped(RegExp(r'(\d)\.(\d)'), (Match m) {
    final String key = '⟦N$hold⟧';
    hold += 1;
    holders[key] = m.group(0)!;
    return key;
  });

  final List<String> out = <String>[];
  final StringBuffer buf = StringBuffer();
  for (int i = 0; i < work.length; i++) {
    final String ch = work[i];
    buf.write(ch);
    final bool endPunct = ch == '.' || ch == '!' || ch == '?';
    if (!endPunct) continue;
    final bool nextIsBoundary = i + 1 >= work.length ||
        work[i + 1] == ' ' ||
        work[i + 1] == '\n' ||
        work[i + 1] == '"' ||
        work[i + 1] == "'";
    if (!nextIsBoundary) continue;
    String piece = buf.toString().trim();
    buf.clear();
    if (piece.isEmpty) continue;
    holders.forEach((String k, String v) {
      piece = piece.replaceAll(k, v);
    });
    out.add(piece);
  }
  String rest = buf.toString().trim();
  if (rest.isNotEmpty) {
    holders.forEach((String k, String v) {
      rest = rest.replaceAll(k, v);
    });
    out.add(rest);
  }
  return out;
}

List<CourseUnit> splitReadingIntoUnits({
  required String plainText,
  int dailySentences = 20,
}) {
  final List<String> sentences = splitReadingSentences(plainText);
  if (sentences.isEmpty) return const <CourseUnit>[];

  final int size = dailySentences.clamp(5, 60);
  // Short article: single unit.
  if (sentences.length < 20) {
    return <CourseUnit>[
      _readingUnit(
        index: 0,
        start: 0,
        end: sentences.length,
        sentences: sentences,
      ),
    ];
  }

  final List<CourseUnit> units = <CourseUnit>[];
  for (int i = 0; i < sentences.length; i += size) {
    final int end = (i + size).clamp(0, sentences.length);
    units.add(
      _readingUnit(
        index: units.length,
        start: i,
        end: end,
        sentences: sentences.sublist(i, end),
      ),
    );
  }
  return units;
}

CourseUnit _readingUnit({
  required int index,
  required int start,
  required int end,
  required List<String> sentences,
}) {
  final String topic = sentences.isEmpty
      ? '阅读块 ${index + 1}'
      : (sentences.first.length > 36
          ? '${sentences.first.substring(0, 36)}…'
          : sentences.first);
  return CourseUnit(
    unitId: 'r${(index + 1).toString().padLeft(2, '0')}',
    sentenceRange: SentenceRange(start, end),
    sentences: List<String>.from(sentences),
    wordIds: extractCourseWordIds(sentences),
    topic: topic,
  );
}
