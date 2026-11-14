import 'dart:io';

import 'package:common_learn_english/features/player/presentation/subtitle_file_persist.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:common_learn_english/features/subtitle_completion/subtitle_completion_queue.dart';
import 'package:common_learn_english/features/subtitle_completion/subtitle_completion_worker.dart';
import 'package:flutter_test/flutter_test.dart';

File _fakeVideo(Directory root, String name) {
  final File video = File('${root.path}/$name');
  video.writeAsBytesSync(List<int>.filled(65 * 1024, 1));
  return video;
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
}
