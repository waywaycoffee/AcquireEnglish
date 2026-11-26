import 'package:common_learn_english/features/reading/domain/k12_pdf_audio_sync.dart';
import 'package:common_learn_english/features/reading/domain/k12_textbook_media.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('contents parser finds unit printed pages', () {
    const String contents = '''
Contents
Unit 1 Making friends 2
Unit 2 Different families 14
Unit 3 Our animal friends 26
Revision Being a good guest 74
''';
    expect(parseUnitPrintedStarts(contents), <int, int>{
      1: 2,
      2: 14,
      3: 26,
    });
    expect(parseRevisionPrintedStart(contents), 74);
  });

  test('contents parser handles PEP next-line page numbers', () {
    const String contents = '''
Contents
Unit 1  Making friends
2
Unit 2  Different families
14
Unit 3  Our animal friends
26
Revision  Being a good guest
74
''';
    expect(parseUnitPrintedStarts(contents), <int, int>{
      1: 2,
      2: 14,
      3: 26,
    });
    expect(parseRevisionPrintedStart(contents), 74);
  });

  test('offset skips Contents page that also mentions Unit 1', () {
    final List<String> pages = <String>[
      'cover',
      'title',
      'copyright',
      'welcome',
      'Contents\nUnit 1 Making friends\n2\nUnit 2 Different families\n14',
      'characters',
      'Making friends\nHow do we make friends?\nUnit 1\n2',
    ];
    expect(
      inferPrintedPageOffset(pages, <int, int>{1: 2, 2: 14}),
      5,
    );
  });

  test('page map follows unit audio activities', () {
    final List<K12TextbookLesson> lessons = <K12TextbookLesson>[
      _lesson(1, 1, '', 'Listen and chant', '01_Unit 1 Listen and chant.mp3'),
      _lesson(2, 1, '', 'Listen and sing', '02_Unit 1 Listen and sing.mp3'),
      _lesson(3, 1, 'A', "Let's talk", "03_Unit 1 A Let's talk.mp3"),
      _lesson(4, 1, 'A', 'Listen and do', '04_Unit 1 A Listen and do.mp3'),
      _lesson(
        5,
        1,
        'A',
        'Listen, repeat and chant',
        '05_Unit 1 A Listen, repeat and chant.mp3',
      ),
      _lesson(
        6,
        1,
        'A',
        'Listen and circle the first sound',
        '06_Unit 1 A Listen and circle the first sound.mp3',
      ),
      _lesson(7, 1, 'B', "Let's talk", "07_Unit 1 B Let's talk.mp3"),
      _lesson(8, 1, 'B', 'Listen and chant', '08_Unit 1 B Listen and chant.mp3'),
      _lesson(9, 1, 'B', 'Start to read', '09_Unit 1 B Start to read.mp3'),
      _lesson(10, 1, 'C', 'Project', '10_Unit 1 C Project.mp3'),
      _lesson(11, 2, '', 'Listen and chant', '11_Unit 2 Listen and chant.mp3'),
    ];

    // Fake PDF: 5 front pages + unit pages with activity labels.
    final List<String> pages = <String>[
      'cover',
      'title',
      'copyright',
      'welcome',
      'Contents\nUnit 1 Making friends 2\nUnit 2 Different families 14\nRevision Being a good guest 74',
      'characters',
      'Unit 1 Making friends Big Question 2', // pdf 7 = printed 2
      "Let's chant Let's sing Listen and chant Listen and sing", // 8
      "Let's talk Hello I'm Mike", // 9
      'Listen and do Wave your hand', // 10
      'Letters and sounds Can you read the words Listen, repeat and chant Listen and circle the first sound', // 11
      "B Let's talk We can share", // 12
      'Listen and chant Am I a good friend', // 13
      'Start to read I listen I smile', // 14
      'Project: Make a mind map', // 15
      'check',
      'reading',
      'reading2',
      'Unit 2 Different families 14', // 19
      'Listen and chant Listen and sing', // 20
    ];

    final K12PdfAudioSyncMap sync = buildK12PdfAudioSyncMap(
      lessons: lessons,
      pageTexts: pages,
    );
    expect(sync.seqForPage(8), 1);
    expect(sync.seqForPage(9), 3);
    expect(sync.seqForPage(10), 4);
    expect(sync.seqForPage(11), anyOf(5, 6));
    expect(sync.seqForPage(12), 7);
    expect(sync.seqForPage(14), 9);
    expect(sync.seqForPage(15), 10);
    expect(sync.seqsStartingOnPage(8), <int>[1, 2]);
  });
}

K12TextbookLesson _lesson(
  int seq,
  int unit,
  String section,
  String title,
  String sourceName,
) => K12TextbookLesson(
  seq: seq,
  unit: unit,
  unitLabel: 'Unit $unit${section.isEmpty ? '' : ' $section'}',
  kind: 'activity',
  title: title,
  audioKey: 'k$seq',
  audioUrl: 'https://example.com/$seq.mp3',
  section: section,
  sourceName: sourceName,
);
