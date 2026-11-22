import 'dart:io';

import 'package:common_learn_english/features/import_course/domain/android_import_picker.dart';
import 'package:common_learn_english/features/import_course/presentation/widgets/import_course_flow.dart';
import 'package:common_learn_english/features/library/presentation/library_catalog_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('import screen follows the redesigned three-step import flow', (
    WidgetTester tester,
  ) async {
    final Directory root = Directory.systemTemp.createTempSync('import-course-test-');
    addTearDown(() => root.deleteSync(recursive: true));

    final Directory videoFolder = Directory('${root.path}/videos')..createSync();
    final Directory subtitleFolder = Directory('${root.path}/subs')..createSync();
    File('${videoFolder.path}/lesson1.mp4')
        .writeAsBytesSync(List<int>.filled(65 * 1024, 1));
    File('${subtitleFolder.path}/lesson1.srt').writeAsStringSync(
      '1\n00:00:00,000 --> 00:00:01,000\nHello\n',
    );
    File('${subtitleFolder.path}/lesson1.zh.srt').writeAsStringSync(
      '1\n00:00:00,000 --> 00:00:01,000\n你好\n',
    );

    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ImportCourseFlow(
              onCancel: () {},
              onImportCompleted: () {},
              pickVideoFolder: () => Future<String?>.value(videoFolder.path),
              pickSubtitleFolder: () => Future<String?>.value(subtitleFolder.path),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('导入影视'), findsOneWidget);
    expect(find.text('把本地视频和字幕整理成新的学习片库。'), findsOneWidget);
    expect(find.textContaining('选择视频文件夹'), findsWidgets);
    expect(find.text('确认导入并建立课程'), findsNothing);

    await tester.tap(find.textContaining('选择视频文件夹').last);
    await tester.pumpAndSettle();

    expect(find.text('选择字幕文件夹并开始解析'), findsOneWidget);
    expect(find.text('开始解析'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '开始解析'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '选择字幕文件夹'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '开始解析'));
    await tester.pump();
    expect(find.text('正在分析视频和字幕...'), findsOneWidget);
    await _waitForParsing(tester);

    expect(find.textContaining('智能解析匹配剧集'), findsWidgets);
    expect(find.byTooltip('返回上一步'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '确认导入并建立课程'));
    await _waitForImportSuccess(tester);

    expect(find.textContaining('导入成功：'), findsOneWidget);
  });

  testWidgets('import screen no longer shows cover generation progress while importing', (
    WidgetTester tester,
  ) async {
    final Directory root = Directory.systemTemp.createTempSync('import-course-progress-');
    addTearDown(() => root.deleteSync(recursive: true));

    final Directory videoFolder = Directory('${root.path}/videos')..createSync();
    final Directory subtitleFolder = Directory('${root.path}/subs')..createSync();
    File('${videoFolder.path}/lesson1.mp4')
        .writeAsBytesSync(List<int>.filled(65 * 1024, 1));
    File('${subtitleFolder.path}/lesson1.srt').writeAsStringSync(
      '1\n00:00:00,000 --> 00:00:01,000\nHello\n',
    );

    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ImportCourseFlow(
              onCancel: () {},
              onImportCompleted: () {},
              pickVideoFolder: () => Future<String?>.value(videoFolder.path),
              pickSubtitleFolder: () => Future<String?>.value(subtitleFolder.path),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('选择视频文件夹').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '选择字幕文件夹'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '开始解析'));
    await _waitForParsing(tester);

    await tester.tap(find.widgetWithText(FilledButton, '确认导入并建立课程'));
    await _waitForImportSuccess(tester);

    expect(find.textContaining('正在生成封面'), findsNothing);
  });

  testWidgets('android import uses picked folder name instead of first episode name', (
    WidgetTester tester,
  ) async {
    final Directory root = Directory.systemTemp.createTempSync('import-course-android-');
    addTearDown(() => root.deleteSync(recursive: true));

    final File video = File('${root.path}/01.mp4')
      ..writeAsBytesSync(List<int>.filled(65 * 1024, 1));
    final File subtitle = File('${root.path}/01.srt')
      ..writeAsStringSync('1\n00:00:00,000 --> 00:00:01,000\nHello\n');

    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ImportCourseFlow(
              onCancel: () {},
              onImportCompleted: () {},
              pickAndroidVideoDirectory: () async => AndroidImportDirectorySelection(
                folderName: 'Friends',
                label: 'Friends（1 个文件）',
                files: <String>[video.path],
                sourceUris: const <String, String>{},
              ),
              pickAndroidSubtitleDirectory: () async => AndroidImportDirectorySelection(
                folderName: 'Friends Subs',
                label: 'Friends Subs（1 个文件）',
                files: <String>[subtitle.path],
                sourceUris: const <String, String>{},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('选择视频文件夹').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '选择字幕文件夹'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '开始解析'));
    await _waitForParsing(tester);
    await tester.tap(find.widgetWithText(FilledButton, '确认导入并建立课程'));
    await _waitForImportSuccess(tester);

    expect(container.read(libraryCatalogProvider).first.title, 'Friends');
  });
}

// Background file scanning runs on a real isolate, outside the widget fake clock.
Future<void> _waitForParsing(WidgetTester tester) async {
  final Stopwatch timeout = Stopwatch()..start();
  while (find.textContaining('智能解析匹配剧集').evaluate().isEmpty) {
    if (timeout.elapsed > const Duration(seconds: 10)) {
      fail('Background import parsing did not complete');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _waitForImportSuccess(WidgetTester tester) async {
  final Stopwatch timeout = Stopwatch()..start();
  while (find.textContaining('导入成功').evaluate().isEmpty &&
      find.textContaining('该课程已导入').evaluate().isEmpty) {
    if (timeout.elapsed > const Duration(seconds: 15)) {
      fail('Import did not finish');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 100));
}
