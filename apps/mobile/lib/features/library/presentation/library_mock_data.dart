class LibrarySubtitleTrackItem {
  const LibrarySubtitleTrackItem({
    required this.languageCode,
    required this.languageLabel,
    required this.path,
  });

  final String languageCode;
  final String languageLabel;
  final String path;
}

class LibraryEpisodeItem {
  const LibraryEpisodeItem({
    required this.id,
    required this.numberStr,
    required this.title,
    required this.durationMinutes,
    required this.hasChineseSubtitles,
    required this.hasEnglishSubtitles,
    required this.completed,
    required this.progressPercent,
    required this.coverImage,
    this.customTitle = false,
    this.customCover = false,
    this.lastWatchedStr,
    this.progressTimeStr,
    this.totalTimeStr,
    this.videoAsset,
    this.sourceUrl,
    this.videoMissing = false,
    this.enSubtitleAsset,
    this.cnSubtitleAsset,
    this.subtitleTracks = const <LibrarySubtitleTrackItem>[],
  });

  final String id;
  final String numberStr;
  final String title;
  final bool customTitle;
  final bool customCover;
  final int durationMinutes;
  final bool hasChineseSubtitles;
  final bool hasEnglishSubtitles;
  final bool completed;
  final int progressPercent;
  final String coverImage;
  final String? lastWatchedStr;
  final String? progressTimeStr;
  final String? totalTimeStr;
  final String? videoAsset;
  /// Durable B站 watch URL / BV for this episode. Survives local MP4 download
  /// overwriting [videoAsset], so 合集分集 never reuse another episode's CC.
  final String? sourceUrl;
  final bool videoMissing;
  final String? enSubtitleAsset;
  final String? cnSubtitleAsset;
  final List<LibrarySubtitleTrackItem> subtitleTracks;

  LibraryEpisodeItem copyWith({
    String? title,
    bool? customTitle,
    bool? customCover,
    String? videoAsset,
    Object? sourceUrl = _unset,
    Object? enSubtitleAsset = _unset,
    Object? cnSubtitleAsset = _unset,
    Object? subtitleTracks = _unset,
    bool? videoMissing,
    bool? completed,
    int? progressPercent,
    String? coverImage,
    String? lastWatchedStr,
    String? progressTimeStr,
    String? totalTimeStr,
    bool? hasChineseSubtitles,
    bool? hasEnglishSubtitles,
  }) {
    return LibraryEpisodeItem(
      id: id,
      numberStr: numberStr,
      title: title ?? this.title,
      customTitle: customTitle ?? this.customTitle,
      customCover: customCover ?? this.customCover,
      durationMinutes: durationMinutes,
      hasChineseSubtitles: hasChineseSubtitles ?? this.hasChineseSubtitles,
      hasEnglishSubtitles: hasEnglishSubtitles ?? this.hasEnglishSubtitles,
      completed: completed ?? this.completed,
      progressPercent: progressPercent ?? this.progressPercent,
      coverImage: coverImage ?? this.coverImage,
      lastWatchedStr: lastWatchedStr ?? this.lastWatchedStr,
      progressTimeStr: progressTimeStr ?? this.progressTimeStr,
      totalTimeStr: totalTimeStr ?? this.totalTimeStr,
      videoAsset: videoAsset ?? this.videoAsset,
      sourceUrl: identical(sourceUrl, _unset)
          ? this.sourceUrl
          : sourceUrl as String?,
      videoMissing: videoMissing ?? this.videoMissing,
      enSubtitleAsset: identical(enSubtitleAsset, _unset)
          ? this.enSubtitleAsset
          : enSubtitleAsset as String?,
      cnSubtitleAsset: identical(cnSubtitleAsset, _unset)
          ? this.cnSubtitleAsset
          : cnSubtitleAsset as String?,
      subtitleTracks: identical(subtitleTracks, _unset)
          ? this.subtitleTracks
          : subtitleTracks as List<LibrarySubtitleTrackItem>? ??
                const <LibrarySubtitleTrackItem>[],
    );
  }
}

const Object _unset = Object();

class LibraryCourseData {
  const LibraryCourseData({
    required this.id,
    required this.title,
    required this.description,
    required this.sourceLabel,
    required this.coverImage,
    required this.level,
    required this.category,
    required this.progressPercent,
    required this.totalWords,
    required this.completedEpisodes,
    required this.totalEpisodes,
    required this.lastStudiedStr,
    this.lastStudiedAtMs,
    required this.rating,
    required this.episodes,
    this.videoDirectories = const <String>[],
    this.subtitleDirectories = const <String>[],
    /// Audio spoken language hint: `en` | `zh` | `auto` (mixed teaching).
    this.spokenLanguage = '',
  });

  final String id;
  final String title;
  final String description;
  final String sourceLabel;
  final String coverImage;
  final String level;
  final String category;
  final int progressPercent;
  final int totalWords;
  final int completedEpisodes;
  final int totalEpisodes;
  final String lastStudiedStr;
  final int? lastStudiedAtMs;
  final double rating;
  final List<LibraryEpisodeItem> episodes;
  final List<String> videoDirectories;
  final List<String> subtitleDirectories;
  final String spokenLanguage;

  LibraryCourseData copyWith({
    String? title,
    String? description,
    String? sourceLabel,
    String? coverImage,
    String? level,
    String? category,
    int? progressPercent,
    int? totalWords,
    int? completedEpisodes,
    int? totalEpisodes,
    String? lastStudiedStr,
    int? lastStudiedAtMs,
    double? rating,
    List<LibraryEpisodeItem>? episodes,
    List<String>? videoDirectories,
    List<String>? subtitleDirectories,
    String? spokenLanguage,
  }) {
    return LibraryCourseData(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      coverImage: coverImage ?? this.coverImage,
      level: level ?? this.level,
      category: category ?? this.category,
      progressPercent: progressPercent ?? this.progressPercent,
      totalWords: totalWords ?? this.totalWords,
      completedEpisodes: completedEpisodes ?? this.completedEpisodes,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      lastStudiedStr: lastStudiedStr ?? this.lastStudiedStr,
      lastStudiedAtMs: lastStudiedAtMs ?? this.lastStudiedAtMs,
      rating: rating ?? this.rating,
      episodes: episodes ?? this.episodes,
      videoDirectories: videoDirectories ?? this.videoDirectories,
      subtitleDirectories: subtitleDirectories ?? this.subtitleDirectories,
      spokenLanguage: spokenLanguage ?? this.spokenLanguage,
    );
  }
}

/// Internal catalog ids must never be shown as human titles.
bool looksLikeInternalLibraryId(String raw) {
  final String value = raw.trim().toLowerCase();
  if (value.isEmpty) return true;
  return value.startsWith('bilibili-') ||
      value.startsWith('youtube-') ||
      value.startsWith('netdisk-') ||
      value.startsWith('link-');
}

bool looksLikeYoutubeCourse(LibraryCourseData course) {
  final String source = course.sourceLabel.trim().toLowerCase();
  final String id = course.id.trim().toLowerCase();
  final String category = course.category.trim().toLowerCase();
  return source == 'youtube' ||
      id.startsWith('youtube-') ||
      category == 'youtube';
}

/// Prefer a user-renamed episode title, never raw `bilibili-season-*` ids.
String libraryEpisodeDisplayTitle(
  LibraryCourseData course,
  LibraryEpisodeItem episode,
) {
  final String episodeTitle = episode.title.trim();
  if (episode.customTitle &&
      episodeTitle.isNotEmpty &&
      !looksLikeInternalLibraryId(episodeTitle)) {
    return episodeTitle;
  }
  if (episodeTitle.isNotEmpty && !looksLikeInternalLibraryId(episodeTitle)) {
    return episodeTitle;
  }
  final String courseTitle = course.title.trim();
  if (courseTitle.isNotEmpty && !looksLikeInternalLibraryId(courseTitle)) {
    return courseTitle;
  }
  if (episode.numberStr.trim().isNotEmpty) {
    return '第 ${episode.numberStr} 集';
  }
  return episodeTitle.isNotEmpty ? episodeTitle : '未命名视频';
}

String libraryCourseDisplayTitle(
  LibraryCourseData course, {
  LibraryEpisodeItem? focusEpisode,
}) {
  if (focusEpisode != null) {
    return libraryEpisodeDisplayTitle(course, focusEpisode);
  }
  if (course.episodes.length == 1) {
    return libraryEpisodeDisplayTitle(course, course.episodes.single);
  }
  for (final LibraryEpisodeItem episode in course.episodes) {
    if (episode.customTitle &&
        episode.title.trim().isNotEmpty &&
        !looksLikeInternalLibraryId(episode.title)) {
      return episode.title.trim();
    }
  }
  final String courseTitle = course.title.trim();
  if (courseTitle.isNotEmpty && !looksLikeInternalLibraryId(courseTitle)) {
    return courseTitle;
  }
  for (final LibraryEpisodeItem episode in course.episodes) {
    final String title = episode.title.trim();
    if (title.isNotEmpty && !looksLikeInternalLibraryId(title)) {
      return title;
    }
  }
  return courseTitle.isNotEmpty ? courseTitle : '未命名课程';
}

LibraryEpisodeItem? nextStudyEpisode(
  LibraryCourseData course, {
  String? lastEpisodeId,
}) {
  final List<LibraryEpisodeItem> available = course.episodes
      .where((LibraryEpisodeItem episode) => !episode.videoMissing)
      .toList(growable: false);
  bool unfinished(LibraryEpisodeItem episode) =>
      !episode.completed && episode.progressPercent < 95;
  final int recent = available.indexWhere((episode) => episode.id == lastEpisodeId);
  if (recent >= 0) {
    final LibraryEpisodeItem? next = available.skip(recent)
        .where(unfinished).firstOrNull;
    if (next != null) return next;
  }
  return available.where((episode) => unfinished(episode) && episode.progressPercent > 0).firstOrNull ??
      available.where(unfinished).firstOrNull ??
      available.lastOrNull;
}

const LibraryCourseData emptyLibraryCourse = LibraryCourseData(
  id: '',
  title: '',
  description: '',
  sourceLabel: '',
  coverImage: '',
  level: '',
  category: '',
  progressPercent: 0,
  totalWords: 0,
  completedEpisodes: 0,
  totalEpisodes: 0,
  lastStudiedStr: '',
  rating: 0,
  episodes: <LibraryEpisodeItem>[],
);

const List<LibraryCourseData> libraryCourses = <LibraryCourseData>[];
