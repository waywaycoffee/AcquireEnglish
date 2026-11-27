import 'package:common_learn_english/features/reading/presentation/k12_reading_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('grade article opens its questions and reveals evidence', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final Map<String, dynamic> item = <String, dynamic>{
      'id': 'k12-reading:k12_j1:01',
      'grade_id': 'k12_j1',
      'collection': 'official_k12_reading',
      'review_status': 'ai_reviewed',
      'level': '初中（中考）',
      'article': <String, dynamic>{
        'title_zh': '校园义卖',
        'passage': 'The students sold books to help the library.',
        'word_count': 9,
      },
      'questions': <Map<String, dynamic>>[
        for (int n = 1; n <= 4; n++)
          <String, dynamic>{
            'q_no': n,
            'question': 'Question $n?',
            'options': <String, String>{
              'D': 'Shoes',
              'C': 'Pencils',
              'B': 'Books',
              'A': 'Toys',
            },
            'answer': 'B',
            'analysis': '他们卖的是书。',
            'evidence_quote': 'The students sold books to help the library.',
          },
      ],
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          k12ReadingCatalogProvider.overrideWith(
            (Ref ref) async => <Map<String, dynamic>>[item],
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: K12ReadingSection(gradeId: 'k12_j1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始答题'));
    await tester.pumpAndSettle();

    expect(find.text('答题 1/4'), findsOneWidget);
    expect(find.text('Question 1?'), findsOneWidget);
    expect(find.text('他们卖的是书。'), findsNothing);
    await tester.tap(find.text('Books'));
    await tester.pump();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.text('他们卖的是书。'), findsOneWidget);
    expect(
      find.text('证据：The students sold books to help the library.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
