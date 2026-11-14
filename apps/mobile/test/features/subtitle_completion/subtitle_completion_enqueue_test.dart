import 'dart:io';

import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/subtitle_file_persist.dart';
import 'package:common_learn_english/features/player/presentation/subtitle_sentence_merge.dart';
import 'package:common_learn_english/features/subtitle_completion/subtitle_completion_enqueue.dart';
import 'package:common_learn_english/features/subtitle_completion/subtitle_completion_queue.dart';
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
    temp = Directory.systemTemp.createTempSync('ae-sub-enq-');
    queue = SubtitleCompletionQueue(appSupportDirectory: () async => temp);
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  test('missing EN with ZH enqueues needEnglish', () async {
    final File video = _fakeVideo(temp, 'a.mp4');
    final File zh = File('${temp.path}/zh.srt')
      ..writeAsStringSync('1\n00:00:00,000 --> 00:00:01,000\n你好\n');
    await enqueueSubtitleCompletionForEpisode(
      episodeId: 'ep-1',
      videoPath: video.path,
      zhSubtitlePath: zh.path,
      enSubtitlePath: null,
      queue: queue,
      appSupportDirectory: () async => temp,
    );
    final SubtitleCompletionJob job = (await queue.loadJobs()).single;
    expect(job.needEnglish, isTrue);
    expect(job.needChinese, isFalse);
    expect(job.zhPath, zh.path);
  });

  test('reliable EN without ZH enqueues needChinese only', () async {
    final File video = _fakeVideo(temp, 'b.mp4');
    final File en = File('${temp.path}/official/en.srt')
      ..createSync(recursive: true)
      ..writeAsStringSync('1\n00:00:00,000 --> 00:00:01,000\nHello\n');
    await enqueueSubtitleCompletionForEpisode(
      episodeId: 'ep-2',
      videoPath: video.path,
      zhSubtitlePath: null,
      enSubtitlePath: en.path,
      queue: queue,
      appSupportDirectory: () async => temp,
    );
    final SubtitleCompletionJob job = (await queue.loadJobs()).single;
    expect(job.needEnglish, isFalse);
    expect(job.needChinese, isTrue);
    expect(job.enPath, en.path);
  });

  test('both official sides skip enqueue', () async {
    final File video = _fakeVideo(temp, 'c.mp4');
    final File en = File('${temp.path}/official/en.srt')
      ..createSync(recursive: true)
      ..writeAsStringSync('1\n00:00:00,000 --> 00:00:01,000\nHello\n');
    final File zh = File('${temp.path}/official/zh.srt')
      ..createSync(recursive: true)
      ..writeAsStringSync('1\n00:00:00,000 --> 00:00:01,000\n你好\n');
    await enqueueSubtitleCompletionForEpisode(
      episodeId: 'ep-3',
      videoPath: video.path,
      zhSubtitlePath: zh.path,
      enSubtitlePath: en.path,
      queue: queue,
      appSupportDirectory: () async => temp,
    );
    expect(await queue.loadJobs(), isEmpty);
  });

  test('empty ZH file still enqueues needChinese', () async {
    final File video = _fakeVideo(temp, 'empty-zh.mp4');
    final File en = File('${temp.path}/official/en.srt')
      ..createSync(recursive: true)
      ..writeAsStringSync('1\n00:00:00,000 --> 00:00:01,000\nHello\n');
    final File zh = File('${temp.path}/official/zh.srt')
      ..createSync(recursive: true)
      ..writeAsStringSync('');
    await enqueueSubtitleCompletionForEpisode(
      episodeId: 'ep-empty-zh',
      videoPath: video.path,
      zhSubtitlePath: zh.path,
      enSubtitlePath: en.path,
      queue: queue,
      appSupportDirectory: () async => temp,
    );
    final SubtitleCompletionJob job = (await queue.loadJobs()).single;
    expect(job.needEnglish, isFalse);
    expect(job.needChinese, isTrue);
  });

  test('complete asr-sentences bilingual skips enqueue', () async {
    final File video = _fakeVideo(temp, 'd.mp4');
    await persistAsrSentenceSubtitles(
      episodeId: 'ep-4',
      bundle: mergeAsrIntoSentences(
        asrLines: const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '00:01',
            english: 'Hello world',
            chinese: '',
            startMs: 0,
            endMs: 1000,
          ),
        ],
        chineseLines: const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '00:01',
            english: '',
            chinese: '你好世界',
            startMs: 0,
            endMs: 1000,
          ),
        ],
      ),
      appSupportDirectory: () async => temp,
    );
    await enqueueSubtitleCompletionForEpisode(
      episodeId: 'ep-4',
      videoPath: video.path,
      queue: queue,
      appSupportDirectory: () async => temp,
    );
    expect(await queue.loadJobs(), isEmpty);
  });
}
