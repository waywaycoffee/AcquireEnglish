import 'package:common_learn_english/features/drama/domain/drama_catalog.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:flutter_test/flutter_test.dart';

LibraryCourseData _course({
  required String id,
  required String title,
  int episodes = 1,
}) {
  return LibraryCourseData(
    id: id,
    title: title,
    description: title,
    sourceLabel: '网盘',
    coverImage: 'assets/img/app_icon.png',
    level: 'B1',
    category: 'baidu_netdisk',
    progressPercent: 0,
    totalWords: 0,
    completedEpisodes: 0,
    totalEpisodes: episodes,
    lastStudiedStr: '',
    rating: 0,
    episodes: List<LibraryEpisodeItem>.generate(
      episodes,
      (int i) => LibraryEpisodeItem(
        id: '$id-ep${i + 1}',
        numberStr: '${i + 1}'.padLeft(2, '0'),
        title: '第${i + 1}集',
        durationMinutes: 20,
        hasChineseSubtitles: false,
        hasEnglishSubtitles: false,
        completed: false,
        progressPercent: 0,
        coverImage: 'assets/img/app_icon.png',
      ),
    ),
  );
}

void main() {
  test('哈利 alone does not match Harry Potter poster', () {
    final DramaCatalogEntry hp =
        kDramaCatalog.firstWhere((DramaCatalogEntry e) => e.id == 'harry-potter');
    final LibraryCourseData other = _course(
      id: 'netdisk-series-other',
      title: '哈利路亚精听',
      episodes: 3,
    );
    expect(catalogEntryMatchesCourse(hp, other), isFalse);
  });

  test('prefers richer netdisk-series over thin flat import', () {
    final DramaCatalogEntry hp =
        kDramaCatalog.firstWhere((DramaCatalogEntry e) => e.id == 'harry-potter');
    final LibraryCourseData thin = _course(
      id: 'link-1',
      title: '哈利波特试看',
      episodes: 5,
    );
    final LibraryCourseData rich = _course(
      id: 'netdisk-series-hp',
      title: '哈利·波特',
      episodes: 8,
    );
    final LibraryCourseData? picked = importedCourseForCatalogEntry(
      hp,
      <LibraryCourseData>[thin, rich],
    );
    expect(picked?.id, 'netdisk-series-hp');
    expect(picked?.episodes.length, 8);
  });

  test('crown poster removed; big bang still present', () {
    expect(
      kDramaCatalog.any((DramaCatalogEntry e) => e.id == 'the-crown'),
      isFalse,
    );
    expect(
      kDramaCatalog.any((DramaCatalogEntry e) => e.id == 'the-big-bang-theory'),
      isTrue,
    );
  });
}
