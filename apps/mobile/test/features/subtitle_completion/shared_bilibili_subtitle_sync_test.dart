import 'dart:io';

import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:common_learn_english/features/subtitle_completion/shared_bilibili_subtitle_sync.dart';
import 'package:common_learn_english/features/subtitle_completion/shared_subtitle_quality.dart';
import 'package:common_learn_english/features/subtitle_completion/subtitle_completion_enqueue.dart';
import 'package:common_learn_english/features/subtitle_completion/subtitle_completion_queue.dart';
import 'package:common_learn_english/features/sync/data/acquire_api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakeSharedApi extends AcquireApiClient {
  _FakeSharedApi(this.pack) : super(Dio());

  final SharedBilibiliSubtitlePack? pack;
  int getCalls = 0;

  @override
  Future<SharedBilibiliSubtitlePack?> getSharedBilibiliSubtitle({
    required String bvid,
    int page = 1,
    int? cid,
  }) async {
    getCalls += 1;
    return pack;
  }
}

class _FakePaths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePaths(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;

  @override
  Future<String?> getApplicationSupportPath() async =>
      Directory('${root.path}/support').path;

  @override
  Future<String?> getTemporaryPath() async =>
      Directory('${root.path}/tmp').path;
}

File _fakeVideo(Directory root, String name) {
  final File video = File('${root.path}/$name');
  video.writeAsBytesSync(List<int>.filled(65 * 1024, 1));
  return video;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Directory docs;
  late SubtitleCompletionQueue queue;
  late PathProviderPlatform previousPaths;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('ae-shared-sync-');
    docs = Directory('${temp.path}/docs')..createSync();
    Directory('${temp.path}/support').createSync();
    Directory('${temp.path}/tmp').createSync();
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePaths(docs);
    queue = SubtitleCompletionQueue(appSupportDirectory: () async => temp);
    configureSharedBilibiliSubtitleApi(null);
  });

  tearDown(() {
    PathProviderPlatform.instance = previousPaths;
    configureSharedBilibiliSubtitleApi(null);
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  test('resolveBilibiliSharedSubtitleIds parses BV and page', () {
    final BilibiliSharedSubtitleIds? ids = resolveBilibiliSharedSubtitleIds(
      sourceKey: 'BV1xx411c7mD-p02',
      sourceUrl: 'https://www.bilibili.com/video/BV1xx411c7mD?p=2',
    );
    expect(ids, isNotNull);
    expect(ids!.bvid, 'BV1xx411c7mD');
    expect(ids.page, 2);
  });

  test('download requests cloud subtitles without a local media file', () async {
    final _FakeSharedApi api = _FakeSharedApi(null);
    configureSharedBilibiliSubtitleApi(api);
    await requestSharedSubtitlesForDownload(bvid: 'BV1CS4y1v7sQ', page: 151);
    expect(api.getCalls, 1);
  });

  test('download continues when the cloud API is not configured', () async {
    await requestSharedSubtitlesForDownload(bvid: 'BV1CS4y1v7sQ', page: 1);
  });

  test('source URL restores case lost in a disk cache key', () {
    final BilibiliSharedSubtitleIds? ids = resolveBilibiliSharedSubtitleIds(
      sourceKey: 'BV1CS4Y1V7SQ-p03',
      sourceUrl: 'https://www.bilibili.com/video/BV1CS4y1v7sQ?p=3',
    );
    expect(ids!.bvid, 'BV1CS4y1v7sQ');
    expect(ids.page, 3);
  });

  test('season course does not invent page from episode numberStr', () {
    const LibraryCourseData course = LibraryCourseData(
      id: 'bilibili-season-123',
      title: 'season',
      description: '',
      sourceLabel: 'Bilibili',
      coverImage: 'assets/img/app_icon.png',
      level: 'A2',
      category: 'bilibili',
      progressPercent: 0,
      totalWords: 0,
      completedEpisodes: 0,
      totalEpisodes: 2,
      lastStudiedStr: '',
      rating: 0,
      episodes: <LibraryEpisodeItem>[],
    );
    const LibraryEpisodeItem episode = LibraryEpisodeItem(
      id: 'ep-2',
      numberStr: '02',
      title: '第二集',
      durationMinutes: 10,
      hasChineseSubtitles: false,
      hasEnglishSubtitles: true,
      completed: false,
      progressPercent: 0,
      coverImage: 'assets/img/app_icon.png',
      sourceUrl: 'https://www.bilibili.com/video/BV1SEASONEP02XX',
    );
    final BilibiliSharedSubtitleIds? ids = resolveBilibiliSharedSubtitleIds(
      sourceUrl: episode.sourceUrl,
      course: course,
      episode: episode,
    );
    expect(ids, isNotNull);
    expect(ids!.bvid, 'BV1SEASONEP02XX');
    expect(ids.page, 1);
  });

  test('enqueue skips ASR when shared EN is applied', () async {
    final File video = _fakeVideo(temp, 'shared.mp4');
    final String enSrt = buildSampleEnglishSrt(cues: 8);
    final String zhSrt = buildSampleChineseSrt(cues: 8);
    final _FakeSharedApi api = _FakeSharedApi(
      SharedBilibiliSubtitlePack(
        bvid: 'BV1SHAREDTEST01',
        page: 1,
        subtitleEnSrt: enSrt,
        subtitleZhSrt: zhSrt,
        qualityScore: 0.9,
        cueCount: 8,
      ),
    );

    await enqueueSubtitleCompletionForEpisode(
      episodeId: 'ep-shared-1',
      videoPath: video.path,
      sourceUrl: 'https://www.bilibili.com/video/BV1SHAREDTEST01',
      queue: queue,
      appSupportDirectory: () async => temp,
      documentsDirectory: () async => docs,
      sharedSubtitleApi: api,
    );

    expect(api.getCalls, 1);
    final List<SubtitleCompletionJob> jobs = await queue.loadJobs();
    expect(jobs, isEmpty);

    final File writtenEn = File(
      '${docs.path}/bilibili/BV1SHAREDTEST01/en.srt',
    );
    expect(writtenEn.existsSync(), isTrue);
    expect(writtenEn.readAsStringSync(), contains('Hello world'));
  });

  test('enqueue still ASR when shared lookup misses', () async {
    final File video = _fakeVideo(temp, 'miss.mp4');
    final _FakeSharedApi api = _FakeSharedApi(null);

    await enqueueSubtitleCompletionForEpisode(
      episodeId: 'ep-shared-miss',
      videoPath: video.path,
      sourceUrl: 'https://www.bilibili.com/video/BV1SHAREDMISS01',
      queue: queue,
      appSupportDirectory: () async => temp,
      documentsDirectory: () async => docs,
      sharedSubtitleApi: api,
    );

    expect(api.getCalls, 1);
    final SubtitleCompletionJob job = (await queue.loadJobs()).single;
    expect(job.needEnglish, isTrue);
  });
}
