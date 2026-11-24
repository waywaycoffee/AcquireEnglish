import '../../library/presentation/library_mock_data.dart';

/// Curated US-drama shelf metadata only — no episode media in the APK.
///
/// Full seasons stay on the user's netdisk (or future licensed ECS clips).
/// Cards always show; playback unlocks after a matching netdisk-series import.
class DramaCatalogEntry {
  const DramaCatalogEntry({
    required this.id,
    required this.titleZh,
    required this.titleEn,
    required this.blurb,
    required this.matchAliases,
    this.level = 'B1–B2',
    this.accent = 0xFF3D5A80,
  });

  final String id;
  final String titleZh;
  final String titleEn;
  final String blurb;
  /// Lowercased fragments matched against imported course title/description.
  final List<String> matchAliases;
  final String level;
  final int accent;
}

const List<DramaCatalogEntry> kDramaCatalog = <DramaCatalogEntry>[
  DramaCatalogEntry(
    id: 'desperate-housewives',
    titleZh: '绝望主妇',
    titleEn: 'Desperate Housewives',
    blurb: '郊区生活与悬疑 · 日常口语密集',
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
    matchAliases: <String>[
      '生活大爆炸',
      'big bang theory',
      'tbbt',
    ],
    accent: 0xFFC45C26,
  ),
  DramaCatalogEntry(
    id: 'harry-potter',
    titleZh: '哈利·波特',
    titleEn: 'Harry Potter',
    blurb: '电影系列 · 叙事与场景英语',
    matchAliases: <String>[
      '哈利',
      'harry potter',
      'harry.potter',
      'hp0',
    ],
    level: 'B1–C1',
    accent: 0xFF5C4B8A,
  ),
  DramaCatalogEntry(
    id: 'the-crown',
    titleZh: '王冠',
    titleEn: 'The Crown',
    blurb: '英式正剧 · 正式场合用语',
    matchAliases: <String>[
      '王冠',
      'the crown',
      'the.crown',
    ],
    level: 'B2–C1',
    accent: 0xFF6B5B4B,
  ),
];

String _courseBlob(LibraryCourseData course) {
  final StringBuffer buf = StringBuffer()
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
  for (final LibraryCourseData course in courses) {
    if (catalogEntryMatchesCourse(entry, course)) return course;
  }
  return null;
}
