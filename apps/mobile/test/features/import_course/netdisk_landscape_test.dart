import 'package:common_learn_english/features/import_course/data/netdisk_local_download.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:flutter_test/flutter_test.dart';

LibraryCourseData _course({
  required String id,
  String category = 'baidu_netdisk',
  String title = 'Demo',
  int episodeCount = 1,
}) {
  return LibraryCourseData(
    id: id,
    title: title,
    description: '',
    sourceLabel: '网盘',
    coverImage: '',
    level: 'B1',
    category: category,
    progressPercent: 0,
    totalWords: 0,
    completedEpisodes: 0,
    totalEpisodes: episodeCount,
    lastStudiedStr: '',
    rating: 0,
    episodes: List<LibraryEpisodeItem>.generate(
      episodeCount,
      (int i) => LibraryEpisodeItem(
        id: '$id-ep$i',
        title: 'E$i',
        numberStr: '${i + 1}',
        durationMinutes: 20,
        hasChineseSubtitles: false,
        hasEnglishSubtitles: true,
        completed: false,
        progressPercent: 0,
        coverImage: '',
        videoAsset: 'https://example.com/api/netdisk/play/$i',
      ),
    ),
  );
}

void main() {
  test('netdisk series stays portrait by default', () {
    final LibraryCourseData series = _course(
      id: 'netdisk-series-friends',
      episodeCount: 8,
      title: 'Friends S01',
    );
    expect(isNetdiskCourse(series), isTrue);
    expect(prefersNetdiskLandscapePlayback(series), isFalse);
    expect(isRemoteStreamVideoAsset(series.episodes.first.videoAsset), isTrue);
  });

  test('single netdisk clip titled 美剧 also stays portrait', () {
    final LibraryCourseData drama = _course(
      id: 'link-42',
      category: 'baidu_netdisk',
      title: '美剧精听 · Pilot',
    );
    expect(prefersNetdiskLandscapePlayback(drama), isFalse);
  });

  test('bilibili course does not prefer netdisk landscape', () {
    final LibraryCourseData bili = _course(
      id: 'bilibili-xxx',
      category: 'bilibili',
      episodeCount: 3,
    );
    expect(isNetdiskCourse(bili), isFalse);
    expect(prefersNetdiskLandscapePlayback(bili), isFalse);
  });
}
