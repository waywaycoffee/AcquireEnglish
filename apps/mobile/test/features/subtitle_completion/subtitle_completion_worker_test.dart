import 'dart:io';

import 'package:common_learn_english/features/player/presentation/subtitle_file_persist.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:common_learn_english/features/subtitle_completion/external_subtitle_fill.dart';
import 'package:common_learn_english/features/subtitle_completion/subtitle_completion_queue.dart';
import 'package:common_learn_english/features/subtitle_completion/subtitle_completion_worker.dart';
import 'package:flutter_test/flutter_test.dart';

File _fakeVideo(Directory root, String name) {
  final File video = File('${root.path}/$name');
  video.writeAsBytesSync(List<int>.filled(65 * 1024, 1));
  return video;
}

class _FakeExternalFill extends ExternalSubtitleFill {
  const _FakeExternalFill(this.enSrt);

  final String enSrt;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ExternalSubtitleFillResult?> fillMissing({
    required String videoPath,
    required String outDir,
    required bool needEnglish,
    required bool needChinese,
    String? enInPath,
    String model = 'base.en',
    String engine = 'auto',
    void Function(String label)? onProgress,
  }) async {
    await Directory(outDir).create(recursive: true);
    final File en = File('$outDir/en.srt')..writeAsStringSync(enSrt);
    return ExternalSubtitleFillResult(
      enPath: en.path,
      zhPath: null,
      engine: 'fake',
      needChineseStill: needChinese,
    );
  }
}

void main() {
  late Directory temp;
  late SubtitleCompletionQueue queue;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('ae-sub-worker-');
    queue = SubtitleCompletionQueue(appSupportDirectory: () async => temp);
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  test('chinese-only job translates EN and persists en-translation', () async {
    final File video = _fakeVideo(temp, 'a.mp4');
    final File en = File('${temp.path}/en.srt')
      ..writeAsStringSync('''
1
00:00:00,000 --> 00:00:01,000
Hello there
''');
    await queue.enqueue(
      episodeId: 'ep-zh',
      videoPath: video.path,
      enPath: en.path,
      needEnglish: false,
      needChinese: true,
    );

    String? attachedEn;
    String? attachedZh;
    final SubtitleCompletionWorker worker = SubtitleCompletionWorker(
      queue: queue,
      appSupportDirectory: () async => temp,
      translateChinese:
          ({
            required List<String> sentences,
            required LearningSettingsState settings,
          }) async {
            return sentences.map((String s) => '译:$s').toList();
          },
      onPersisted:
          ({
            required String episodeId,
            required String englishPath,
            required String chinesePath,
          }) async {
            attachedEn = englishPath;
            attachedZh = chinesePath;
          },
    );

    final bool ran = await worker.processNext(
      settings: LearningSettingsState.defaults(),
    );
    expect(ran, isTrue);
    expect(await persistedEnglishIsAsrSentences(
      episodeId: 'ep-zh',
      appSupportDirectory: () async => temp,
    ), isTrue);
    expect(
      await readPersistedEnglishOrigin(
        episodeId: 'ep-zh',
        appSupportDirectory: () async => temp,
      ),
      enTranslationOrigin,
    );
    final String zhSrt = await File(attachedZh!).readAsString();
    expect(zhSrt, contains('译:Hello there'));
    expect(attachedEn, isNotNull);
    expect((await queue.loadJobs()).single.status, SubtitleCompletionStatus.done);
  });

  test('ASR job fills remaining Chinese when ZH track is partial', () async {
    final File video = _fakeVideo(temp, 'partial.mp4');
    final File zh = File('${temp.path}/partial-zh.srt')
      ..writeAsStringSync('''
1
00:00:00,000 --> 00:00:01,000
你好
''');
    await queue.enqueue(
      episodeId: 'ep-partial-zh',
      videoPath: video.path,
      zhPath: zh.path,
      needEnglish: true,
      needChinese: true,
    );

    final List<String> translated = <String>[];
    String? attachedZh;
    final SubtitleCompletionWorker worker = SubtitleCompletionWorker(
      queue: queue,
      appSupportDirectory: () async => temp,
      externalFill: _FakeExternalFill('''
1
00:00:00,000 --> 00:00:01,000
Hello there.

2
00:00:03,000 --> 00:00:04,000
How are you?
'''),
      translateChinese:
          ({
            required List<String> sentences,
            required LearningSettingsState settings,
          }) async {
            translated.addAll(sentences);
            return sentences.map((String s) => '译:$s').toList();
          },
      onPersisted:
          ({
            required String episodeId,
            required String englishPath,
            required String chinesePath,
          }) async {
            attachedZh = chinesePath;
          },
    );

    final bool ran = await worker.processNext(
      settings: LearningSettingsState.defaults(),
    );
    expect(ran, isTrue);
    // Old every()-missing gate skipped translation whenever any ZH existed.
    expect(translated, contains('How are you?'));
    final String zhSrt = await File(attachedZh!).readAsString();
    expect(zhSrt, contains('你好'));
    expect(zhSrt, contains('译:How are you?'));
    expect(
      (await queue.loadJobs()).single.status,
      SubtitleCompletionStatus.done,
    );
  });
}
