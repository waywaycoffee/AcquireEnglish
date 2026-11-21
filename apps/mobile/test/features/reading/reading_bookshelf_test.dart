import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:common_learn_english/features/reading/domain/reading_doc.dart';
import 'package:common_learn_english/features/reading/presentation/reading_bookshelf.dart';
import 'package:common_learn_english/features/reading/presentation/reading_bookshelf_view.dart';

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
    expect(find.text('＋'), findsNothing);
    expect(find.byIcon(Icons.file_download_outlined), findsWidgets);
    expect(find.text('ACQUIRE ENGLISH'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('footer formats book and word counts', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReadingBookshelfFooter(
            bookCount: 10,
            totalWords: 1860,
          ),
        ),
      ),
    );
    expect(find.textContaining('10 本'), findsOneWidget);
    expect(find.textContaining('1,860 词'), findsOneWidget);
    expect(find.text('10 本 · 1,860 词'), findsOneWidget);
    expect(find.text('◇'), findsNWidgets(2));
  });

  testWidgets('bookshelf view shows centered title, search, import and stats', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadingBookshelfHubLayout(
            books: const <ReadingDoc>[],
            bookCount: 0,
            totalWords: 0,
            onOpen: (_) {},
            onImport: () {},
            onSearch: () {},
          ),
        ),
      ),
    );
    expect(find.text('我的书架'), findsOneWidget);
    expect(find.text('封面朝外 · 点书继续读'), findsNothing);
    final Offset titleCenter = tester.getCenter(find.text('我的书架'));
    expect(titleCenter.dx, closeTo(tester.view.physicalSize.width / tester.view.devicePixelRatio / 2, 1));
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.textContaining('0 本'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);
  });
}
