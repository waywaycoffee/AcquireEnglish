import 'k12_textbook_media.dart';

/// Map PDF page numbers (1-based) onto textbook lesson [seq] values.
class K12PdfAudioSyncMap {
  const K12PdfAudioSyncMap({
    required this.pageToSeq,
    required this.seqToStartPage,
  });

  final Map<int, int> pageToSeq;
  final Map<int, int> seqToStartPage;

  bool get isEmpty => pageToSeq.isEmpty;

  int? seqForPage(int page) => pageToSeq[page];

  /// Lessons that begin exactly on [page], in seq order.
  List<int> seqsStartingOnPage(int page) {
    final List<int> out = <int>[
      for (final MapEntry<int, int> e in seqToStartPage.entries)
        if (e.value == page) e.key,
    ]..sort();
    return out;
  }
}

String _norm(String raw) => raw
    .toLowerCase()
    .replaceAll('’', "'")
    .replaceAll('‘', "'")
    .replaceAll(RegExp(r'[\u2000-\u200b\ufeff]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Parse `Unit N … {printedPage}` rows from a Contents page.
///
/// Real PEP PDFs often put the printed page on the **next line**:
/// ```
/// Unit 1  Making friends
/// 2
/// ```
Map<int, int> parseUnitPrintedStarts(String contentsText) {
  final String text = contentsText.replaceAll(RegExp(r'[\u2000-\u200b]'), ' ');
  final RegExp sameLine = RegExp(
    r'Unit\s+(\d+)\s+[A-Za-z][A-Za-z \-]*?\s+(\d+)\b',
    caseSensitive: false,
  );
  final RegExp nextLine = RegExp(
    r'Unit\s+(\d+)\s+[A-Za-z][A-Za-z \-]*?\s*\n\s*(\d+)\b',
    caseSensitive: false,
  );
  final Map<int, int> out = <int, int>{};
  for (final RegExp re in <RegExp>[sameLine, nextLine]) {
    for (final RegExpMatch m in re.allMatches(text)) {
      final int? unit = int.tryParse(m.group(1)!);
      final int? page = int.tryParse(m.group(2)!);
      if (unit != null && page != null) out.putIfAbsent(unit, () => page);
    }
  }
  return out;
}

int? parseRevisionPrintedStart(String contentsText) {
  final String text = contentsText.replaceAll(RegExp(r'[\u2000-\u200b]'), ' ');
  final RegExpMatch? same = RegExp(
    r'Revision\s+[A-Za-z][A-Za-z \-]*?\s+(\d+)\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (same != null) return int.tryParse(same.group(1)!);
  final RegExpMatch? next = RegExp(
    r'Revision\s+[A-Za-z][A-Za-z \-]*?\s*\n\s*(\d+)\b',
    caseSensitive: false,
  ).firstMatch(text);
  return next == null ? null : int.tryParse(next.group(1)!);
}

/// Infer PDF page − printed page offset (PEP books often use +5).
int inferPrintedPageOffset(List<String> pageTexts, Map<int, int> unitPrinted) {
  final int? unit1Printed = unitPrinted[1];
  if (unit1Printed == null) return 5;
  for (int i = 0; i < pageTexts.length; i++) {
    final String t = pageTexts[i];
    if (t.contains('Contents') || t.contains('目录')) continue;
    if (!RegExp(r'Unit\s+1\b', caseSensitive: false).hasMatch(t)) continue;
    if (i < 3) continue;
    // Prefer the unit opener (title page), not a later activity page.
    return (i + 1) - unit1Printed;
  }
  return 5;
}

String _activityPhrase(K12TextbookLesson lesson) {
  final String src = _norm(
    lesson.sourceName.isNotEmpty
        ? lesson.sourceName
        : '${lesson.audioKey}.mp3',
  );
  final RegExpMatch? m =
      RegExp(r'unit\s+\d+(?:\s+[abc])?\s+(.+)\.mp3$').firstMatch(src);
  if (m != null) return _norm(m.group(1)!);
  return _norm(lesson.title);
}

List<String> _markersFor(K12TextbookLesson lesson) {
  final String phrase = _activityPhrase(lesson);
  final List<String> marks = <String>[phrase, _norm(lesson.title)];
  if (phrase.contains('circle')) {
    marks
      ..add('letters and sounds')
      ..add('can you read the words');
  }
  if (phrase.contains('project')) {
    marks.add('project');
  }
  if (phrase.contains('start to read')) {
    marks.add('start to read');
  }
  if (phrase.contains("let's talk") || phrase.contains('lets talk')) {
    marks.add("let's talk");
  }
  if (phrase.contains('listen and do')) {
    marks.add('listen and do');
  }
  return marks.where((String m) => m.length >= 4).toSet().toList(growable: false);
}

K12PdfAudioSyncMap _proportionalFallback(List<K12TextbookLesson> lessons, int pageCount) {
  if (lessons.isEmpty || pageCount <= 0) {
    return const K12PdfAudioSyncMap(
      pageToSeq: <int, int>{},
      seqToStartPage: <int, int>{},
    );
  }
  final List<K12TextbookLesson> ordered = List<K12TextbookLesson>.from(lessons)
    ..sort((K12TextbookLesson a, K12TextbookLesson b) => a.seq.compareTo(b.seq));
  // Skip likely front matter (~6 pages) when spreading lessons.
  final int start = pageCount > 12 ? 7 : 1;
  final int usable = (pageCount - start + 1).clamp(1, pageCount);
  final Map<int, int> seqToStart = <int, int>{};
  final Map<int, int> pageToSeq = <int, int>{};
  for (int i = 0; i < ordered.length; i++) {
    final int page =
        (start + ((i * usable) / ordered.length).floor()).clamp(1, pageCount);
    seqToStart[ordered[i].seq] = page;
  }
  for (int p = 1; p <= pageCount; p++) {
    int? bestSeq;
    int bestStart = -1;
    for (final MapEntry<int, int> e in seqToStart.entries) {
      if (e.value <= p && e.value >= bestStart) {
        bestStart = e.value;
        bestSeq = e.key;
      }
    }
    if (bestSeq != null) pageToSeq[p] = bestSeq;
  }
  return K12PdfAudioSyncMap(
    pageToSeq: Map<int, int>.unmodifiable(pageToSeq),
    seqToStartPage: Map<int, int>.unmodifiable(seqToStart),
  );
}

/// Build page→lesson sync from extracted PDF page texts (index 0 = page 1).
K12PdfAudioSyncMap buildK12PdfAudioSyncMap({
  required List<K12TextbookLesson> lessons,
  required List<String> pageTexts,
}) {
  if (lessons.isEmpty || pageTexts.isEmpty) {
    return const K12PdfAudioSyncMap(
      pageToSeq: <int, int>{},
      seqToStartPage: <int, int>{},
    );
  }

  String contents = '';
  for (int i = 0; i < pageTexts.length && i < 12; i++) {
    final String t = pageTexts[i];
    if ((t.contains('Contents') || t.contains('目录')) &&
        RegExp(r'Unit\s+1', caseSensitive: false).hasMatch(t)) {
      contents = t;
      break;
    }
  }
  if (contents.isEmpty) {
    contents = pageTexts.length > 4 ? pageTexts[4] : pageTexts.first;
  }

  final Map<int, int> unitPrinted = parseUnitPrintedStarts(contents);
  if (unitPrinted.isEmpty) {
    return _proportionalFallback(lessons, pageTexts.length);
  }
  final int? revPrinted = parseRevisionPrintedStart(contents);
  final int offset = inferPrintedPageOffset(pageTexts, unitPrinted);
  final int pageCount = pageTexts.length;

  int pdfOf(int printed) => (printed + offset).clamp(1, pageCount + 1);

  final List<int> units = unitPrinted.keys.toList()..sort();
  final Map<int, (int start, int end)> ranges = <int, (int, int)>{};
  for (int i = 0; i < units.length; i++) {
    final int u = units[i];
    final int start = pdfOf(unitPrinted[u]!);
    final int end = i + 1 < units.length
        ? pdfOf(unitPrinted[units[i + 1]]!)
        : pdfOf(revPrinted ?? (unitPrinted[u]! + 12));
    ranges[u] = (start, end.clamp(start + 1, pageCount + 1));
  }

  final Map<int, K12TextbookLesson> bySeq = <int, K12TextbookLesson>{
    for (final K12TextbookLesson l in lessons) l.seq: l,
  };
  final Map<int, int> seqToStart = <int, int>{};
  for (final MapEntry<int, (int start, int end)> range in ranges.entries) {
    final int unit = range.key;
    final int start = range.value.$1;
    final int end = range.value.$2;
    final List<K12TextbookLesson> unitLessons = lessons
        .where((K12TextbookLesson l) => l.unit == unit)
        .toList(growable: false);
    int cursor = start;
    for (int idx = 0; idx < unitLessons.length; idx++) {
      final K12TextbookLesson lesson = unitLessons[idx];
      final List<String> marks = _markersFor(lesson);
      int? best;
      int bestScore = 0;
      final int mid = (start + end) ~/ 2;
      final String sec = lesson.section.toUpperCase();
      for (int p = cursor; p < end && p <= pageCount; p++) {
        final String nt = _norm(pageTexts[p - 1]);
        int score = 0;
        for (final String k in marks) {
          if (nt.contains(k)) score += 12 + k.length;
        }
        if (sec == 'A' && p < mid) score += 4;
        if (sec == 'B' && p >= mid - 2) score += 4;
        if (sec == 'C' && p >= mid) score += 4;
        if (score > bestScore) {
          bestScore = score;
          best = p;
        }
        if (score >= 24) break;
      }
      final int assigned =
          (best ?? cursor.clamp(start, end - 1)).clamp(1, pageCount);
      seqToStart[lesson.seq] = assigned;
      bool nextStay = false;
      if (idx + 1 < unitLessons.length) {
        final String nextPhrase = _activityPhrase(unitLessons[idx + 1]);
        if (nextPhrase.isNotEmpty &&
            _norm(pageTexts[assigned - 1]).contains(nextPhrase)) {
          nextStay = true;
        }
      }
      cursor = nextStay ? assigned : assigned + 1;
    }
  }

  final Map<int, int> pageToSeq = <int, int>{};
  for (int p = 1; p <= pageCount; p++) {
    int? unit;
    for (final MapEntry<int, (int start, int end)> e in ranges.entries) {
      if (p >= e.value.$1 && p < e.value.$2) {
        unit = e.key;
        break;
      }
    }
    if (unit == null) continue;
    final int unitId = unit;
    final List<MapEntry<int, int>> pool = seqToStart.entries
        .where(
          (MapEntry<int, int> e) =>
              bySeq[e.key]?.unit == unitId && e.value <= p,
        )
        .toList(growable: false);
    if (pool.isEmpty) {
      K12TextbookLesson? first;
      for (final K12TextbookLesson l in lessons) {
        if (l.unit != unitId) continue;
        if (first == null || l.seq < first.seq) first = l;
      }
      if (first != null) pageToSeq[p] = first.seq;
      continue;
    }
    pool.sort((MapEntry<int, int> a, MapEntry<int, int> b) {
      final int byPage = a.value.compareTo(b.value);
      if (byPage != 0) return byPage;
      return a.key.compareTo(b.key);
    });
    final List<MapEntry<int, int>> onPage =
        pool.where((MapEntry<int, int> e) => e.value == p).toList();
    pageToSeq[p] = (onPage.isNotEmpty ? onPage.first : pool.last).key;
  }

  if (pageToSeq.isEmpty) {
    return _proportionalFallback(lessons, pageCount);
  }

  return K12PdfAudioSyncMap(
    pageToSeq: Map<int, int>.unmodifiable(pageToSeq),
    seqToStartPage: Map<int, int>.unmodifiable(seqToStart),
  );
}
