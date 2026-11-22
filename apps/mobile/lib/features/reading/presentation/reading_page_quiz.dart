import '../../daily_path/domain/course_plan.dart';

/// Payload returned by AI伴读「出阅读理解题」before opening the quiz screen.
class ReadingPageQuizBundle {
  const ReadingPageQuizBundle({
    required this.quiz,
    required this.sentences,
    required this.topic,
    this.fromFallback = false,
  });

  final List<CourseQuizItem> quiz;
  final List<String> sentences;
  final String topic;
  final bool fromFallback;
}

/// Offline / API-failure fallback: 4 ABCD items grounded in page sentences.
List<CourseQuizItem> buildReadingPageQuizFallback({
  required List<String> sentences,
  List<String> targetWords = const <String>[],
}) {
  final List<String> lines = sentences
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);
  if (lines.length < 2) return const <CourseQuizItem>[];

  final String a = lines[0];
  final String b = lines[1];
  final String c = lines.length > 2 ? lines[2] : a;
  final String word = () {
    for (final String w in targetWords) {
      if (w.trim().length >= 2) return w.trim();
    }
    final RegExpMatch? m = RegExp(r"[A-Za-z]{4,}").firstMatch(a);
    return m?.group(0) ?? 'story';
  }();

  List<String> uniqueOptions(List<String> raw) {
    final List<String> out = <String>[];
    final Set<String> seen = <String>{};
    for (final String o in raw) {
      final String t = o.trim().isEmpty ? '—' : o.trim();
      if (seen.add(t)) out.add(t);
    }
    var n = 1;
    while (out.length < 4) {
      final String pad = '干扰项 $n';
      if (seen.add(pad)) out.add(pad);
      n += 1;
    }
    return out.take(4).toList(growable: false);
  }

  return <CourseQuizItem>[
    CourseQuizItem(
      type: 'detail',
      stem: '根据本节内容，哪一句出现在文中？',
      options: uniqueOptions(<String>[a, 'The dragon flew home alone.', 'Nobody spoke that day.', 'It was always raining.']),
      answer: 0,
      explanation: '原文首句',
      evidenceSentenceIndex: 0,
    ),
    CourseQuizItem(
      type: 'detail',
      stem: '下面哪一句也来自本节？',
      options: uniqueOptions(<String>[b, 'They bought a red car.', 'School starts at midnight.', 'The lake was empty forever.']),
      answer: 0,
      explanation: '原文第二句',
      evidenceSentenceIndex: 1,
    ),
    CourseQuizItem(
      type: 'vocabulary',
      stem: '词「$word」更可能出现在哪一句附近？',
      options: uniqueOptions(<String>[
        a.toLowerCase().contains(word.toLowerCase()) ? a : b,
        'A silent market closed early.',
        'Purple clocks never tick.',
        'Frozen music filled the room.',
      ]),
      answer: 0,
      explanation: '联系上下文理解词义',
      evidenceSentenceIndex: a.toLowerCase().contains(word.toLowerCase()) ? 0 : 1,
    ),
    CourseQuizItem(
      type: 'main_idea',
      stem: '本节大意更接近？',
      options: uniqueOptions(<String>[
        c.length > 80 ? '${c.substring(0, 77)}…' : c,
        'A cooking recipe for soup',
        'A sports match scoreboard',
        'A weather forecast only',
      ]),
      answer: 0,
      explanation: '抓住本节关键信息',
      evidenceSentenceIndex: lines.length > 2 ? 2 : 0,
    ),
  ];
}
