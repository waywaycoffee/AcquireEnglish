import 'dart:io';

import 'package:common_learn_english/features/import_course/data/bilibili_collection_download.dart';
import 'package:common_learn_english/features/import_course/data/bilibili_multipage.dart';
import 'package:common_learn_english/features/library/presentation/library_catalog_provider.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

LibraryCourseData _seasonCourse() {
  return LibraryCourseData(
    id: 'bilibili-season-123',
    title: '合集',
    description: 'https://www.bilibili.com/bangumi/play/ss123',
    sourceLabel: 'Bilibili',
    coverImage: 'https://i0.hdslb.com/bfs/season.jpg',
    level: 'A2',
    category: 'bilibili',
    progressPercent: 0,
    totalWords: 0,
    completedEpisodes: 0,
    totalEpisodes: 2,
    lastStudiedStr: '',
    lastStudiedAtMs: 0,
    rating: 0,
    episodes: <LibraryEpisodeItem>[
      LibraryEpisodeItem(
        id: 'bilibili-BV1AAA111111',
        numberStr: '1',
        title: 'Day 1',
        durationMinutes: 2,
        hasChineseSubtitles: false,
        hasEnglishSubtitles: false,
        completed: false,
        progressPercent: 0,
        coverImage: 'https://i0.hdslb.com/bfs/ep1.jpg',
        videoAsset: 'https://www.bilibili.com/video/BV1AAA111111',
        videoMissing: true,
      ),
      LibraryEpisodeItem(
        id: 'bilibili-BV1BBB222222',
        numberStr: '2',
        title: 'Day 2',
        durationMinutes: 3,
        hasChineseSubtitles: false,
        hasEnglishSubtitles: false,
        completed: false,
        progressPercent: 0,
        coverImage: '',
        videoAsset: 'https://www.bilibili.com/video/BV1BBB222222',
        videoMissing: true,
      ),
    ],
  );
}

void main() {
  group('bilibiliSourceForEpisode season', () {
    test('uses episode BV and ignores numberStr as page', () {
      final LibraryCourseData course = _seasonCourse();
      final String? source = bilibiliSourceForEpisode(
        course: course,
        episode: course.episodes[1],
        videoAsset: course.episodes[1].videoAsset,
      );
      expect(source, contains('BV1BBB222222'));
      expect(source, isNot(contains('p=2')));
    });
  });

  group('updateEpisodeLocalMedia', () {
    late Directory hiveDir;

    setUp(() async {
      hiveDir = Directory.systemTemp.createTempSync('collection-media-');
      Hive.init(hiveDir.path);
      await Hive.openBox<String>('prefs');
    });

    tearDown(() async {
      await Hive.box<String>('prefs').close();
      await Hive.deleteBoxFromDisk('prefs');
      hiveDir.deleteSync(recursive: true);
    });

    test('updates one episode without wiping sibling media', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final LibraryCatalogNotifier catalog = container.read(
        libraryCatalogProvider.notifier,
      );
      final LibraryCourseData course = _seasonCourse();
      await catalog.importCourse(course);

      await catalog.updateEpisodeLocalMedia(
        courseId: course.id,
        episodeId: course.episodes.first.id,
        videoAsset: '/tmp/ep1.mp4',
        coverImage: '/tmp/ep1.jpg',
        videoMissing: false,
      );

      final LibraryCourseData live = container
          .read(libraryCatalogProvider)
          .firstWhere((LibraryCourseData c) => c.id == course.id);
      expect(live.episodes.first.videoAsset, '/tmp/ep1.mp4');
      expect(live.episodes.first.videoMissing, isFalse);
      expect(live.episodes.first.coverImage, '/tmp/ep1.jpg');
      expect(live.episodes[1].videoMissing, isTrue);
      expect(
        live.episodes[1].videoAsset,
        'https://www.bilibili.com/video/BV1BBB222222',
      );
    });

    test('updateCourseVideoAsset is no-op for multi-episode courses', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final LibraryCatalogNotifier catalog = container.read(
        libraryCatalogProvider.notifier,
      );
      final LibraryCourseData course = _seasonCourse();
      await catalog.importCourse(course);

      await catalog.updateCourseVideoAsset(
        courseId: course.id,
        videoAsset: '/tmp/should-not-stamp.mp4',
      );

      final LibraryCourseData live = container
          .read(libraryCatalogProvider)
          .firstWhere((LibraryCourseData c) => c.id == course.id);
      expect(
        live.episodes.every(
          (LibraryEpisodeItem e) => e.videoAsset != '/tmp/should-not-stamp.mp4',
        ),
        isTrue,
      );
    });
  });

  group('collection download in-flight', () {
    test('reports in-flight flag helpers', () {
      expect(isBilibiliCollectionDownloadInFlight('missing'), isFalse);
    });
  });
}
