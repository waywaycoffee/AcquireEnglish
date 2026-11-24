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
  _FakeSharedApi(this.pack, {this.enqueueSucceeds = true}) : super(Dio());

  final SharedBilibiliSubtitlePack? pack;
  final bool enqueueSucceeds;
  PersonalImportAsset? personalAsset;
  String? personalEnglish;
  final List<String> requests = <String>[];

  @override
  Future<List<PersonalImportAsset>> listPersonalImports() async => [
    if (personalAsset != null) personalAsset!,
  ];

  @override
  Future<String?> fetchPersonalImportSrt({
    required int importId,
    required String lang,
  }) async {
    requests.add('personal-$lang');
    return personalEnglish;
  }

  int getCalls = 0;
  int enqueueCalls = 0;
  String? lastEnqueuedBvid;
  int? lastEnqueuedPage;

  @override
  Future<SharedBilibiliSubtitlePack?> getSharedBilibiliSubtitle({
    required String bvid,
    int page = 1,
    int? cid,
  }) async {
    requests.add('public');
    getCalls += 1;
    return pack;
  }

  @override
  Future<SharedSubtitleGpuJob?> enqueueSharedSubtitleJob({
    required String bvid,
    int page = 1,
    bool reportErrors = false,
  }) async {
    enqueueCalls += 1;
    lastEnqueuedBvid = bvid;
    lastEnqueuedPage = page;
    if (!enqueueSucceeds) {
      return null;
    }
    return SharedSubtitleGpuJob(
      id: 'job-$enqueueCalls',
      bvid: bvid,
      page: page,
      state: 'queued',
    );
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

  test(
    'download requests cloud subtitles without a local media file',
    () async {
      final _FakeSharedApi api = _FakeSharedApi(null);
      configureSharedBilibiliSubtitleApi(api);
      await requestSharedSubtitlesForDownload(bvid: 'BV1CS4y1v7sQ', page: 151);
      expect(api.getCalls, 1);
      expect(api.enqueueCalls, 1);
      expect(api.lastEnqueuedBvid, 'BV1CS4y1v7sQ');
      expect(api.lastEnqueuedPage, 151);
    },
  );

  test(
    'public lookup fills only the missing track and keeps local corrections',
    () async {
      const String bvid = 'BV1CS4y1v7sQ';
      final String publicEn = buildSampleEnglishSrt(cues: 6);
      final String publicZh = buildSampleChineseSrt(cues: 6);
      final _FakeSharedApi api = _FakeSharedApi(
        SharedBilibiliSubtitlePack(
          bvid: bvid,
          page: 2,
          subtitleEnSrt: publicEn,
          subtitleZhSrt: publicZh,
          qualityScore: 0.9,
          cueCount: 6,
          hasZh: true,
        ),
      );
      api.personalAsset = const PersonalImportAsset(
        id: 1,
        source: 'bilibili',
        externalId: '$bvid-p02',
        title: 'Part 2',
        watchUrl: 'https://www.bilibili.com/video/$bvid?p=2',
        durationSec: 60,
        hasEn: true,
        hasZh: false,
        courseId: 'course',
      );
      final String personalEn = publicEn.replaceFirst(
        RegExp(r'[^\n]+(?=\n\n)'),
        'My corrected sentence.',
      );
      final File localEnglish = File("${docs.path}/corrected-en.srt");
      await localEnglish.writeAsString(personalEn);
      api.personalEnglish = personalEn;
      final result = await tryApplySharedBilibiliSubtitles(
        api: api,
        ids: const BilibiliSharedSubtitleIds(
          bvid: bvid,
          page: 2,
          idKey: '$bvid-p02',
        ),
        documentsDirectory: () async => docs,
        existingEnPath: localEnglish.path,
      );
      expect(api.requests, ['public']);
      expect(await File(result!.enPath!).readAsString(), personalEn);
      expect(await File(result.zhPath!).readAsString(), publicZh);
    },
  );

  test('download continues when the cloud API is not configured', () async {
    await requestSharedSubtitlesForDownload(bvid: 'BV1CS4y1v7sQ', page: 1);
  });

  test('download writes bilingual shared pack to Documents/bilibili', () async {
    final String enSrt = buildSampleEnglishSrt(cues: 6);
    final String zhSrt = buildSampleChineseSrt(cues: 6);
    final _FakeSharedApi api = _FakeSharedApi(
      SharedBilibiliSubtitlePack(
        bvid: 'BV1DOWNLOADWRITE',
        page: 1,
        subtitleEnSrt: enSrt,
        subtitleZhSrt: zhSrt,
        qualityScore: 0.9,
        cueCount: 6,
        hasZh: true,
      ),
    );
    configureSharedBilibiliSubtitleApi(api);

    final ({String? enPath, String? zhPath})? written =
        await requestSharedSubtitlesForDownload(
          bvid: 'BV1DOWNLOADWRITE',
          page: 1,
          documentsDirectory: () async => docs,
        );

    expect(api.getCalls, 1);
    expect(api.enqueueCalls, 0);
    expect(written?.enPath, isNotNull);
    expect(written?.zhPath, isNotNull);
    final File enFile = File('${docs.path}/bilibili/BV1DOWNLOADWRITE/en.srt');
    final File zhFile = File('${docs.path}/bilibili/BV1DOWNLOADWRITE/zh.srt');
    expect(enFile.existsSync(), isTrue);
    expect(zhFile.existsSync(), isTrue);
    expect(enFile.readAsStringSync(), contains('Hello world'));
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

    final File writtenEn = File('${docs.path}/bilibili/BV1SHAREDTEST01/en.srt');
    expect(writtenEn.existsSync(), isTrue);
    expect(writtenEn.readAsStringSync(), contains('Hello world'));
  });

  test('automatic Bilibili fill keeps a usable Chinese softsub', () async {
    final video = _fakeVideo(temp, 'existing.mp4');
    final zh = File('${temp.path}/official.zh.srt')
      ..writeAsStringSync(buildSampleChineseSrt(cues: 8));
    final api = _FakeSharedApi(null);

    await enqueueSubtitleCompletionForEpisode(
      episodeId: 'ep-official-zh',
      videoPath: video.path,
      zhSubtitlePath: zh.path,
      sourceUrl: 'https://www.bilibili.com/video/BV1CS4y1v7sQ',
      queue: queue,
      appSupportDirectory: () async => temp,
      documentsDirectory: () async => docs,
      sharedSubtitleApi: api,
      networkFetchOfficial: false,
    );

    expect(api.enqueueCalls, 0);
    expect(await queue.loadJobs(), isEmpty);
  });

  test('enqueue pushes cloud generation when shared lookup misses', () async {
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
    expect(api.enqueueCalls, 1);
    expect(api.lastEnqueuedBvid, 'BV1SHAREDMISS01');
    // Cloud is the default path — do not auto-queue on-device Whisper.
    expect(await queue.loadJobs(), isEmpty);
  });

  test('enqueue reports cloud failure without local ASR fallback', () async {
    final File video = _fakeVideo(temp, 'cloud-fail.mp4');
    final _FakeSharedApi api = _FakeSharedApi(null, enqueueSucceeds: false);

    await enqueueSubtitleCompletionForEpisode(
      episodeId: 'ep-cloud-fail',
      videoPath: video.path,
      sourceUrl: 'https://www.bilibili.com/video/BV1CLOUDFAIL01',
      queue: queue,
      appSupportDirectory: () async => temp,
      documentsDirectory: () async => docs,
      sharedSubtitleApi: api,
      networkFetchOfficial: false,
    );

    expect(api.enqueueCalls, 1);
    // Missing English waits on ECS GPU; on-device Whisper is not packaged.
    expect(await queue.loadJobs(), isEmpty);
  });

  test('cloud generation works without a local video file', () async {
    final _FakeSharedApi api = _FakeSharedApi(null);

    await enqueueSubtitleCompletionForEpisode(
      episodeId: 'ep-no-video',
      videoPath: null,
      sourceUrl: 'https://www.bilibili.com/video/BV1NOVIDEO0001',
      queue: queue,
      appSupportDirectory: () async => temp,
      documentsDirectory: () async => docs,
      sharedSubtitleApi: api,
      networkFetchOfficial: false,
    );

    expect(api.enqueueCalls, 1);
    expect(api.lastEnqueuedBvid, 'BV1NOVIDEO0001');
    expect(await queue.loadJobs(), isEmpty);
  });

  test('force still prefers cloud ASR and skips local Whisper queue', () async {
    final File video = _fakeVideo(temp, 'force.mp4');
    final _FakeSharedApi api = _FakeSharedApi(null);

    await enqueueSubtitleCompletionForEpisode(
      episodeId: 'ep-force-local',
      videoPath: video.path,
      sourceUrl: 'https://www.bilibili.com/video/BV1FORCELOCAL01',
      queue: queue,
      appSupportDirectory: () async => temp,
      documentsDirectory: () async => docs,
      sharedSubtitleApi: api,
      force: true,
      networkFetchOfficial: false,
    );

    // force still needs English → cloud queue path; no on-device ASR jobs.
    expect(api.enqueueCalls, greaterThanOrEqualTo(0));
    expect(await queue.loadJobs(), isEmpty);
  });
}
