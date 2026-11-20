import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:common_learn_english/features/community/presentation/community_preview_screen.dart';

void main() {
  testWidgets('preview is marked and likes and bookmarks toggle locally', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CommunityPreviewScreen()));
    expect(find.textContaining('人物、内容和数字均为 mock'), findsOneWidget);
    expect(find.text('返回真实社区'), findsOneWidget);
    await tester.ensureVisible(find.text('128'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('128'));
    await tester.pump();
    expect(find.text('129'), findsOneWidget);
    await tester.tap(find.text('129'));
    await tester.pump();
    expect(find.text('128'), findsOneWidget);
    await tester.tap(find.text('收藏').first);
    await tester.pump();
    expect(find.text('已收藏'), findsOneWidget);
    await tester.tap(find.text('已收藏'));
    await tester.pump();
    expect(find.text('已收藏'), findsNothing);
  });
}
