import 'dart:io';

import 'package:common_learn_english/features/subtitle_completion/subtitle_completion_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late SubtitleCompletionQueue queue;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('ae-sub-completion-q-');
    queue = SubtitleCompletionQueue(appSupportDirectory: () async => temp);
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  test('enqueue dedupes by episodeId and keeps pending', () async {
    await queue.enqueue(
      episodeId: 'ep-1',
      videoPath: '/tmp/a.mp4',
      zhPath: '/tmp/zh.srt',
      needEnglish: true,
      needChinese: false,
    );
    await queue.enqueue(
      episodeId: 'ep-1',
      videoPath: '/tmp/b.mp4',
      zhPath: '/tmp/zh2.srt',
      enPath: '/tmp/en.srt',
      needEnglish: false,
      needChinese: true,
    );
    final List<SubtitleCompletionJob> jobs = await queue.loadJobs();
    expect(jobs, hasLength(1));
    expect(jobs.single.videoPath, '/tmp/b.mp4');
    expect(jobs.single.needEnglish, isFalse);
    expect(jobs.single.needChinese, isTrue);
    expect(jobs.single.enPath, '/tmp/en.srt');
    expect(jobs.single.status, SubtitleCompletionStatus.pending);
  });

  test('legacy JSON defaults needEnglish true', () {
    final SubtitleCompletionJob? job = SubtitleCompletionJob.fromJson(
      <String, Object?>{
        'episodeId': 'ep-legacy',
        'videoPath': '/tmp/a.mp4',
        'status': 'pending',
      },
    );
    expect(job, isNotNull);
    expect(job!.needEnglish, isTrue);
    expect(job.needChinese, isFalse);
  });

  test('done jobs are not re-queued unless forced', () async {
    await queue.enqueue(episodeId: 'ep-1', videoPath: '/tmp/a.mp4');
    await queue.markDone('ep-1');
    final SubtitleCompletionJob again = await queue.enqueue(
      episodeId: 'ep-1',
      videoPath: '/tmp/a.mp4',
    );
    expect(again.status, SubtitleCompletionStatus.done);
    expect(await queue.nextRunnable(), isNull);

    final SubtitleCompletionJob forced = await queue.enqueue(
      episodeId: 'ep-1',
      videoPath: '/tmp/a.mp4',
      force: true,
    );
    expect(forced.status, SubtitleCompletionStatus.pending);
    expect((await queue.nextRunnable())?.episodeId, 'ep-1');
  });

  test('failed jobs retry until maxAttempts', () async {
    final SubtitleCompletionQueue limited = SubtitleCompletionQueue(
      appSupportDirectory: () async => temp,
      maxAttempts: 2,
    );
    await limited.enqueue(episodeId: 'ep-1', videoPath: '/tmp/a.mp4');
    await limited.markFailed('ep-1', 'boom');
    expect((await limited.nextRunnable())?.episodeId, 'ep-1');
    await limited.markFailed('ep-1', 'boom2');
    expect(await limited.nextRunnable(), isNull);
  });

  test('recoverInterrupted resets running to pending', () async {
    await queue.enqueue(episodeId: 'ep-1', videoPath: '/tmp/a.mp4');
    await queue.markRunning('ep-1');
    await queue.recoverInterrupted();
    final List<SubtitleCompletionJob> jobs = await queue.loadJobs();
    expect(jobs.single.status, SubtitleCompletionStatus.pending);
  });
}
