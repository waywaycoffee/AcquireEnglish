import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:common_learn_english/features/reading/presentation/reading_stats_row.dart';

void main() {
  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0]) {
      testWidgets('six statistics stay on one row: dark=$dark width=$width', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: const ReadingStatsRow(
                    values: {
                      '藏书': 10,
                      '已打开': 3,
                      '读完': 0,
                      '约读词': 123456,
                      '已会词': 12345,
                      '重点词': 1,
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        final ys = [
          '藏书',
          '已打开',
          '读完',
          '约读词',
          '已会词',
          '重点词',
        ].map((label) => tester.getCenter(find.text(label)).dy).toList();
        expect(ys.every((y) => (y - ys.first).abs() < 1), isTrue);
        expect(
          tester.getSize(find.byType(ReadingStatsRow)).height,
          lessThan(64),
        );
        expect(find.text('12.3万'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
