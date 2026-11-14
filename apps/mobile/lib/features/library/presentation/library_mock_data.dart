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
      title: title,
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
    );
  }
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
