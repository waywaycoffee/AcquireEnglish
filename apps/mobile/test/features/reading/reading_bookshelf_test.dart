import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:common_learn_english/features/reading/domain/reading_doc.dart';
import 'package:common_learn_english/features/reading/presentation/reading_bookshelf.dart';

void main() {
  testWidgets('bookshelf shows cover-facing books on ledges with import slot', (
    WidgetTester tester,
  ) async {
    final List<ReadingDoc> books = <ReadingDoc>[
      ReadingDoc(
        id: 'a',
        title: 'A Morning Walk',
        sourceType: ReadingSourceType.builtin,
        plainText: 'hello world ' * 40,
        createdAt: DateTime(2024),
        level: 'A1',
      ),
      ReadingDoc(
        id: 'b',
        title: 'The Lost Key',
        sourceType: ReadingSourceType.builtin,
        plainText: 'hello world ' * 40,
        createdAt: DateTime(2024),
        level: 'A2',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 640,
            child: ReadingBookshelf(
              books: books,
              bookCount: 2,
              totalWords: 160,
              onOpenBook: (_) {},
              onImport: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('A Morning Walk'), findsOneWidget);
    expect(find.text('The Lost Key'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('footer formats book and word counts', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReadingBookshelfFooter(
            bookCount: 10,
            totalWords: 1860,
            hint: '书架上的书 · 非卡片网格',
          ),
        ),
      ),
    );
    expect(find.textContaining('10 本'), findsOneWidget);
    expect(find.textContaining('1,860 词'), findsOneWidget);
    expect(find.text('书架上的书 · 非卡片网格'), findsOneWidget);
  });
}
