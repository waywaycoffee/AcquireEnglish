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

  test('done jobs stay done only when detect reports no missing side', () async {
    await queue.enqueue(
      episodeId: 'ep-1',
      videoPath: '/tmp/a.mp4',
      needEnglish: true,
      needChinese: false,
    );
    await queue.markDone('ep-1');
    final SubtitleCompletionJob stillDone = await queue.enqueue(
      episodeId: 'ep-1',
      videoPath: '/tmp/a.mp4',
      needEnglish: false,
      needChinese: false,
    );
    expect(stillDone.status, SubtitleCompletionStatus.done);
    expect(await queue.nextRunnable(), isNull);

    // Same need flags as the completed job must still reopen when work remains.
    final SubtitleCompletionJob reopened = await queue.enqueue(
      episodeId: 'ep-1',
      videoPath: '/tmp/a.mp4',
      needEnglish: true,
      needChinese: false,
    );
    expect(reopened.status, SubtitleCompletionStatus.pending);
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

  test('markDeferred keeps attempts and returns to pending', () async {
    await queue.enqueue(episodeId: 'ep-def', videoPath: '/tmp/a.mp4');
    await queue.markRunning('ep-def');
    await queue.markDeferred('ep-def', 'AI 字幕生成已取消。');
    final SubtitleCompletionJob job = (await queue.loadJobs()).single;
    expect(job.status, SubtitleCompletionStatus.pending);
    expect(job.attempts, 0);
    expect(job.lastError, contains('取消'));
    expect((await queue.nextRunnable())?.episodeId, 'ep-def');
  });

  test('running enqueue persists OR-merged need flags', () async {
    await queue.enqueue(
      episodeId: 'ep-run',
      videoPath: '/tmp/a.mp4',
      needEnglish: true,
      needChinese: false,
    );
    await queue.markRunning('ep-run');
    await queue.enqueue(
      episodeId: 'ep-run',
      videoPath: '/tmp/b.mp4',
      zhPath: '/tmp/zh.srt',
      needEnglish: false,
      needChinese: true,
    );
    final SubtitleCompletionJob job = (await queue.loadJobs()).single;
    expect(job.status, SubtitleCompletionStatus.running);
    expect(job.videoPath, '/tmp/b.mp4');
    expect(job.zhPath, '/tmp/zh.srt');
    expect(job.needEnglish, isTrue);
    expect(job.needChinese, isTrue);
  });
}
