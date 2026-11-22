import 'dart:io';
import 'package:common_learn_english/features/learning_modules/module_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('learning-modules');
    Hive.init(dir.path);
    await Hive.openBox<String>('prefs');
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  test(
    'every lesson has a valid comprehension answer and aligned translations',
    () {
      for (final lessons in moduleLessons.values) {
        for (final l in lessons) {
          expect(l.lines.length, l.meanings.length);
          expect(l.choices.contains(l.answer), isTrue);
        }
      }
    },
  );
  test('curriculum covers British phonemes and all course tracks', () {
    expect(moduleLessons['ipa']!.length, 46);
    expect(moduleLessons['phonics']!.length, 32);
    expect(moduleLessons['chunks']!.length, 22);
    expect(moduleLessons['listening']!.length, 14);
    expect(moduleLessons['dialogue']!.length, 14);
    expect(
      moduleLessons.values.fold<int>(0, (sum, list) => sum + list.length),
      128,
    );
  });
  testWidgets('completion requires a correct answer', (tester) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ModuleScreen(kind: 'phonics')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '完成并保存进度'))
          .onPressed,
      isNull,
    );
    final Finder choice = find.ancestor(
      of: find.text('/æ/'),
      matching: find.byType(RadioListTile<String>),
    );
    expect(choice, findsOneWidget);
    await tester.ensureVisible(choice);
    await tester.tap(choice, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '完成并保存进度'))
          .onPressed,
      isNotNull,
    );
  });
  testWidgets('listening hides subtitles until requested', (tester) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ModuleScreen(kind: 'listening')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('I get up at seven.'), findsNothing);
    expect(find.text('先听一遍，再展开字幕'), findsOneWidget);
    await tester.ensureVisible(find.text('展开提示'));
    await tester.tap(find.text('展开提示'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('I get up at seven.'), findsOneWidget);
  });
}
