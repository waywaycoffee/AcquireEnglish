import '../../library/presentation/library_mock_data.dart';

/// Curated US-drama shelf metadata only — no episode media in the APK.
///
/// Full seasons stay on the user's netdisk / licensed public series.
/// Cards always show; playback unlocks after a matching import or public publish.
class DramaCatalogEntry {
  const DramaCatalogEntry({
    required this.id,
    required this.titleZh,
    required this.titleEn,
    required this.blurb,
    required this.matchAliases,
    this.coverUrl,
    this.level = 'B1–B2',
    this.accent = 0xFF3D5A80,
  });

  final String id;
  final String titleZh;
  final String titleEn;
  final String blurb;
  /// Lowercased fragments matched against imported course title/description.
  final List<String> matchAliases;
  /// Relative ECS path `/media/misc/drama-covers/…` (not bundled in the APK).
  /// Resolved against the API base URL; device caches under Documents/drama_covers.
  final String? coverUrl;
  final String level;
  final int accent;
}

const String _kDramaCoverBase = '/media/misc/drama-covers';

const List<DramaCatalogEntry> kDramaCatalog = <DramaCatalogEntry>[
  DramaCatalogEntry(
    id: 'desperate-housewives',
    titleZh: '绝望主妇',
    titleEn: 'Desperate Housewives',
    blurb: '郊区生活与悬疑 · 日常口语密集',
    coverUrl: '$_kDramaCoverBase/desperate-housewives.jpg',
    matchAliases: <String>[
      '绝望主妇',
      '绝望的主妇',
      'desperate housewives',
      'desperate.housewives',
      'desperate_housewives',
      'dh s0',
    ],
    accent: 0xFF8B4557,
  ),
  DramaCatalogEntry(
    id: 'friends',
    titleZh: '老友记',
    titleEn: 'Friends',
    blurb: '经典情景喜剧 · 口语入门首选',
    coverUrl: '$_kDramaCoverBase/friends.jpg',
    matchAliases: <String>[
      '老友记',
      'friends',
      'f.r.i.e.n.d.s',
    ],
    level: 'A2–B1',
    accent: 0xFF4A6FA5,
  ),
  DramaCatalogEntry(
    id: 'modern-family',
    titleZh: '摩登家庭',
    titleEn: 'Modern Family',
    blurb: '家庭对话 · 语速适中',
    coverUrl: '$_kDramaCoverBase/modern-family.jpg',
    matchAliases: <String>[
      '摩登家庭',
      'modern family',
      'modern.family',
    ],
    level: 'A2–B1',
    accent: 0xFF2A9D8F,
  ),
  DramaCatalogEntry(
    id: 'the-big-bang-theory',
    titleZh: '生活大爆炸',
    titleEn: 'The Big Bang Theory',
    blurb: '极客幽默 · 词汇进阶',
    coverUrl: '$_kDramaCoverBase/the-big-bang-theory.jpg',
    matchAliases: <String>[
      '生活大爆炸',
      'big bang theory',
      'big.bang.theory',
      'the big bang theory',
      'the.big.bang.theory',
      'tbbt',
    ],
    accent: 0xFFC45C26,
  ),
  DramaCatalogEntry(
    id: 'harry-potter',
    titleZh: '哈利·波特',
    titleEn: 'Harry Potter',
    blurb: '电影系列 · 叙事与场景英语',
    coverUrl: '$_kDramaCoverBase/harry-potter.jpg',
    matchAliases: <String>[
      '哈利波特',
      '哈利·波特',
      'harry potter',
      'harry.potter',
      'harry_potter',
      'hp0',
    ],
    level: 'B1–C1',
    accent: 0xFF5C4B8A,
  ),
];

String _courseBlob(LibraryCourseData course) {
  final StringBuffer buf = StringBuffer()
    ..write(course.id)
    ..write(' ')
    ..write(course.title)
    ..write(' ')
    ..write(course.description)
    ..write(' ')
    ..write(course.category)
    ..write(' ')
    ..write(course.sourceLabel);
  for (final LibraryEpisodeItem ep in course.episodes.take(8)) {
    buf
      ..write(' ')
      ..write(ep.title)
      ..write(' ')
      ..write(ep.videoAsset)
      ..write(' ')
      ..write(ep.sourceUrl ?? '')
      ..write(' ')
      ..write(ep.enSubtitleAsset ?? '');
  }
  return buf.toString().toLowerCase();
}

bool catalogEntryMatchesCourse(
  DramaCatalogEntry entry,
  LibraryCourseData course,
) {
  // Stable public publish id: public-series-{catalogEntry.id}
  if (course.id == 'public-series-${entry.id}') {
    return true;
  }
  final String blob = _courseBlob(course);
  for (final String alias in entry.matchAliases) {
    final String a = alias.trim().toLowerCase();
    if (a.isNotEmpty && blob.contains(a)) return true;
  }
  return false;
}

DramaCatalogEntry? catalogEntryForCourse(LibraryCourseData course) {
  for (final DramaCatalogEntry entry in kDramaCatalog) {
    if (catalogEntryMatchesCourse(entry, course)) return entry;
  }
  return null;
}

LibraryCourseData? importedCourseForCatalogEntry(
  DramaCatalogEntry entry,
  Iterable<LibraryCourseData> courses,
) {
  // Prefer the richest matching course so a partial flat import cannot
  // replace a full netdisk-series (HP "5集→消失" when prune/sync flips ids).
  LibraryCourseData? best;
  for (final LibraryCourseData course in courses) {
    if (!catalogEntryMatchesCourse(entry, course)) {
      continue;
    }
    if (best == null || _rank(course) > _rank(best)) {
      best = course;
    }
  }
  return best;
}

int _rank(LibraryCourseData course) {
  int score = course.episodes.length * 10;
  if (course.id.startsWith('netdisk-series-')) score += 1000;
  if (course.id.startsWith('public-series-')) score += 200;
  return score;
}
