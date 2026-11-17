import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:common_learn_english/features/player/data/dub_session_store.dart';
import 'package:common_learn_english/features/player/data/pronunciation_providers.dart';
import 'package:common_learn_english/features/player/domain/pronunciation_assessment.dart';
import 'package:common_learn_english/features/player/presentation/widgets/pronunciation_assessment_dialog.dart';
import 'package:common_learn_english/features/settings/data/pronunciation_credentials.dart';
import 'pronunciation_dialog_flow_test.dart' as fixture;
class Paths extends fixture.ReviewPaths {
  Paths(super.directory);
  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
}
void main() {
  for (final bool timeout in <bool>[false, true]) {
  testWidgets('episode dialog persists recording; scoring timeout=$timeout', (WidgetTester tester) async {
    final Directory dir = Directory.systemTemp.createTempSync('shadow-dialog-');
    final PathProviderPlatform previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = Paths(dir.path);
    addTearDown(() { PathProviderPlatform.instance = previous; dir.deleteSync(recursive: true); });
    final fixture.ReviewMicrophone mic = fixture.ReviewMicrophone();
    final fixture.ReviewService service = fixture.ReviewService();
    if (!timeout) service.pending.complete(const PronunciationAssessmentResult(suggestedScore: 86));
    await tester.pumpWidget(ProviderScope(overrides: [
      pronunciationAudioExtractorProvider.overrideWithValue(fixture.ReviewExtractor(dir)),
      pronunciationMicrophoneFactoryProvider.overrideWithValue(() => mic),
      pronunciationPreviewPlayerFactoryProvider.overrideWithValue(() => fixture.ReviewPreview()),
      pronunciationCredentialStoreProvider.overrideWithValue(fixture.ReviewStore()),
      tencentPronunciationServiceProvider.overrideWithValue(service),
    ], child: const MaterialApp(home: Scaffold(body: PronunciationAssessmentDialog(
      episodeId: 'test-episode', target: PronunciationAssessmentTarget(text: 'Take a break.',
        videoSource: '/fixture.mp4', startMs: 600, endMs: 1551, videoDuration: Duration(milliseconds: 5393)),
    )))));
    for (int i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 50)); await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10))); }
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    mic.stream.add(fixture.speech().bytes);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    for (int i = 0; i < 200; i++) { await tester.pump(const Duration(milliseconds: 50)); await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10))); }
    expect(service.calls, 1);
    if (timeout) { await tester.pump(const Duration(seconds: 21)); await tester.pump(); }
    final List<DubTake> takes = await tester.runAsync(() => DubSessionStore.instance.loadTakes('test-episode')) ?? [];
    expect(takes.single.scorePercent, timeout ? isNull : 86);
    expect(takes.single.fileExists, isTrue);
    expect(find.byKey(const ValueKey<String>('shadowing-own-recording-replay')), findsOneWidget);
    if (timeout) { expect(find.textContaining('评分超时'), findsOneWidget); }
    else { expect(find.text('已评分'), findsOneWidget); }
    await tester.pumpWidget(const SizedBox());
  });
  }
}
