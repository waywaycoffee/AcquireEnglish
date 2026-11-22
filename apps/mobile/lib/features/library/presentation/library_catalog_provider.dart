import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../daily_path/data/oral_core_library_mapper.dart';
import '../../daily_path/domain/oral_core_series.dart';
import '../../learning_modules/american_ipa_course.dart';
import '../../learning_modules/british_ipa_course.dart';
import '../../learning_modules/phonics_nessy_course.dart';
import '../../import_course/data/bilibili_episode_prepare.dart';
import '../../import_course/data/bilibili_multipage.dart';
import '../../import_course/domain/bilibili_import.dart';
import '../../import_course/domain/import_match.dart';
import '../../membership/domain/free_trial_seeds.dart';
import '../../player/presentation/asr_subtitle_cache.dart';
import '../data/course_pack_mapper.dart';
import 'course_directory_relink.dart';
import 'library_mock_data.dart';

const String _libraryCatalogStorageKey = 'imported_library_courses_v1';

final NotifierProvider<LibraryCatalogNotifier, List<LibraryCourseData>>
libraryCatalogProvider =
    NotifierProvider<LibraryCatalogNotifier, List<LibraryCourseData>>(
      LibraryCatalogNotifier.new,
    );

final Provider<List<LibraryCourseData>> recentLearningCoursesProvider =
    Provider<List<LibraryCourseData>>((Ref ref) {
      final List<MapEntry<int, LibraryCourseData>> courses =
          ref.watch(libraryCatalogProvider).asMap().entries.toList()..sort((
            MapEntry<int, LibraryCourseData> a,
            MapEntry<int, LibraryCourseData> b,
          ) {
            final int byTime = (b.value.lastStudiedAtMs ?? 0).compareTo(
              a.value.lastStudiedAtMs ?? 0,
            );
            return byTime == 0 ? a.key.compareTo(b.key) : byTime;
          });
      return courses
          .map((MapEntry<int, LibraryCourseData> item) => item.value)
          .toList(growable: false);
    });

class LibraryCatalogNotifier extends Notifier<List<LibraryCourseData>> {
  String? _lastStudiedCourseId;

  @override
  List<LibraryCourseData> build() {
    const List<LibraryCourseData> baseCatalog = libraryCourses;

    if (!Hive.isBoxOpen('prefs')) {
      return baseCatalog;
    }

    final String? stored = Hive.box<String>(
      'prefs',
    ).get(_libraryCatalogStorageKey);
    if (stored == null || stored.isEmpty) {
      return baseCatalog;
    }

    return <LibraryCourseData>[...baseCatalog, ..._decodeCourses(stored)];
  }

  bool _isFreeTrialCourse(LibraryCourseData course) {
    for (final LibraryEpisodeItem ep in course.episodes) {
      final String url = (ep.sourceUrl ?? '').trim();
      if (url.isEmpty) continue;
      final Map<String, String>? ids = BilibiliImport.extractIds(url);
      final String bvid = (ids?['bvid'] ?? '').trim();
      if (bvid.isNotEmpty && isFreeTrialBilibiliBvid(bvid)) return true;
    }
    return false;
  }

  int get personalVideoCourseCount {
    return state
        .where(
          (LibraryCourseData c) =>
              !_isFreeTrialCourse(c) &&
              c.id != OralCoreSeries.kSeriesId &&
              c.id != AmericanIpaCourse.kSeriesId &&
              c.id != BritishIpaCourse.kSeriesId &&
              c.id != PhonicsNessyCourse.kSeriesId,
        )
        .length;
  }

  Future<void> _upsertOfficialCourse(LibraryCourseData course) async {
    final int existingIndex = state.indexWhere(
      (LibraryCourseData item) => item.id == course.id,
    );
    if (existingIndex < 0) {
      state = <LibraryCourseData>[course, ...state];
      await _persistImportedCourses();
      return;
    }
    final LibraryCourseData previous = state[existingIndex];
    final LibraryCourseData merged = course.copyWith(
      progressPercent: previous.progressPercent,
      completedEpisodes: previous.completedEpisodes,
      lastStudiedStr: previous.lastStudiedStr,
      lastStudiedAtMs: previous.lastStudiedAtMs,
      episodes: <LibraryEpisodeItem>[
        for (final LibraryEpisodeItem episode in course.episodes)
          _mergeImportedEpisode(
            next: episode,
            previous: _findMatchingEpisode(previous.episodes, episode),
          ),
      ],
    );
    final List<LibraryCourseData> next = <LibraryCourseData>[...state];
    next[existingIndex] = merged;
    state = next;
    await _persistImportedCourses();
  }

  /// Official american_ipa_20 — shadowing-only skill course.
  Future<void> ensureAmericanIpaCourse() async {
    await _upsertOfficialCourse(AmericanIpaCourse.toLibraryCourse());
  }

  /// Official BBC British IPA — shadowing-only skill course.
  Future<void> ensureBritishIpaCourse() async {
    await _upsertOfficialCourse(BritishIpaCourse.toLibraryCourse());
  }

  /// Official Nessy phonics — shadowing-only skill course.
  Future<void> ensurePhonicsNessyCourse() async {
    await _upsertOfficialCourse(PhonicsNessyCourse.toLibraryCourse());
  }

  /// Official oral_core_9000 series — always allowed, does not consume personal slots.
  Future<void> ensureOralCoreCourse(OralCoreSeries series) async {
    await _upsertOfficialCourse(oralCoreSeriesToLibraryCourse(series));
  }

  Future<bool> importCourse(LibraryCourseData course) async {
    if (libraryCourses.any((LibraryCourseData item) => item.id == course.id)) {
      return false;
    }
    final int existingIndex = state.indexWhere(
      (LibraryCourseData item) => item.id == course.id,
    );
    // Free-tier personal video library: keep ≥15 slots (default 20 headroom).
    // Free-trial seeds do not consume personal slots; re-import refresh is OK.
    if (existingIndex < 0 &&
        !_isFreeTrialCourse(course) &&
        personalVideoCourseCount >= kFreePersonalUploadSlotsMin + 5) {
      throw StateError(
        '个人视频课已达上限（${kFreePersonalUploadSlotsMin + 5}）；'
        '开通视频模块可继续导入，已加入的免费体验课不会变为付费。',
      );
    }
    if (existingIndex >= 0) {
      // Re-importing the same Bilibili / online course should refresh media
      // paths (local download + cover) while keeping learning progress.
      final LibraryCourseData previous = state[existingIndex];
      final LibraryCourseData merged = course.copyWith(
        progressPercent: previous.progressPercent,
        completedEpisodes: previous.completedEpisodes,
        lastStudiedStr: previous.lastStudiedStr,
        lastStudiedAtMs: previous.lastStudiedAtMs,
        episodes: <LibraryEpisodeItem>[
          for (final LibraryEpisodeItem episode in course.episodes)
            _mergeImportedEpisode(
              next: episode,
              previous: _findMatchingEpisode(previous.episodes, episode),
            ),
        ],
      );
      final List<LibraryCourseData> next = <LibraryCourseData>[...state];
      next[existingIndex] = merged;
      state = next;
      await _persistImportedCourses();
      return true;
    }
    state = <LibraryCourseData>[course, ...state];
    await _persistImportedCourses();
    return true;
  }

  /// Upsert cloud / feed courses ahead of local imports (plan content order).
  Future<void> mergeCloudCourses(List<LibraryCourseData> cloudCourses) async {
    // Drop previously synced placeholder「云课程」(slow-english-demo etc.).
    final List<LibraryCourseData> withoutPlaceholders = state
        .where((LibraryCourseData c) => !isPlaceholderLibraryCourse(c))
        .toList(growable: false);
    if (cloudCourses.isEmpty) {
      if (withoutPlaceholders.length != state.length) {
        state = withoutPlaceholders;
        await _persistImportedCourses();
      }
      return;
    }
    final Set<String> cloudIds = cloudCourses
        .map((LibraryCourseData c) => c.id)
        .toSet();
    final List<LibraryCourseData> locals = withoutPlaceholders
        .where((LibraryCourseData c) => !cloudIds.contains(c.id))
        .toList(growable: false);
    // Plan order: cloud catalog → local imports → YouTube imports.
    final List<LibraryCourseData> localOnly = locals
        .where(
          (LibraryCourseData c) =>
              c.sourceLabel.trim().toLowerCase() != 'youtube' &&
              !c.id.startsWith('youtube-'),
        )
        .toList(growable: false);
    final List<LibraryCourseData> youtube = locals
        .where(
          (LibraryCourseData c) =>
              c.sourceLabel.trim().toLowerCase() == 'youtube' ||
              c.id.startsWith('youtube-'),
        )
        .toList(growable: false);
    state = <LibraryCourseData>[...cloudCourses, ...localOnly, ...youtube];
    await _persistImportedCourses();
  }

  Future<void> syncCloudCatalogFromApi() async {
    try {
      // Lazy import avoided — caller uses acquire API via daily feed / home.
    } catch (_) {}
  }

  Future<void> relinkDirectory({
    required CourseDirectoryRelinkPlan plan,
    required Map<String, String> selections,
    required Set<String> addedVideoPaths,
    AsrSubtitleCache subtitleCache = const AsrSubtitleCache(),
  }) async {
    for (final String path in <String>{
      ...selections.values,
      ...addedVideoPaths,
    }) {
      if (!File(path).existsSync()) {
        throw StateError('部分文件已移动或无法访问，请重新扫描。');
      }
    }
    final int index = state.indexWhere(
      (LibraryCourseData item) => item.id == plan.course.id,
    );
    if (index < 0) throw StateError('课程已被删除，请重新打开。');
    final LibraryCourseData current = state[index];
    if (!plan.isCurrent(current)) throw StateError('课程资源已变化，请重新扫描。');
    final LibraryCourseData updated = plan.apply(
      current,
      selections,
      addedVideoPaths,
    );
    // Persist before publishing, so a failed write cannot leave a partial update.
    final List<LibraryCourseData> next = <LibraryCourseData>[...state];
    next[index] = updated;
    if (Hive.isBoxOpen('prefs')) {
      await Hive.box<String>('prefs').put(
        _libraryCatalogStorageKey,
        jsonEncode(next.map(_serializeCourse).toList()),
      );
    }
    state = next;
    for (final LibraryEpisodeItem episode in current.episodes) {
      final String? oldPath = episode.videoAsset;
      final String? newPath = selections[oldPath];
      if (oldPath == null || newPath == null || oldPath == newPath) continue;
      try {
        await subtitleCache.relinkVideo(
          episodeId: episode.id,
          oldPath: oldPath,
          newPath: newPath,
        );
      } catch (_) {
        // Optional cache metadata must never prevent a confirmed directory move.
      }
    }
  }

  Future<void> updateCoursesMetadata({
    required Set<String> courseIds,
    String? title,
    String? sourceLabel,
    String? coverImage,
  }) async {
    if (courseIds.isEmpty) {
      return;
    }
    state = state
        .map((LibraryCourseData course) {
          if (!courseIds.contains(course.id)) {
            return course;
          }
          return course.copyWith(
            title: title == null || title.trim().isEmpty ? null : title.trim(),
            sourceLabel: sourceLabel == null || sourceLabel.trim().isEmpty
                ? null
                : sourceLabel.trim(),
            coverImage: coverImage == null || coverImage.trim().isEmpty
                ? null
                : coverImage.trim(),
          );
        })
        .toList(growable: false);
    await _persistImportedCourses();
  }

  /// Update course poster; only fill placeholder episode covers.
  Future<void> updateCourseCover({
    required String courseId,
    required String coverImage,
  }) async {
    final String next = coverImage.trim();
    if (next.isEmpty) {
      return;
    }
    bool changed = false;
    state = state.map((LibraryCourseData course) {
      if (course.id != courseId) {
        return course;
      }
      changed = true;
      return course.copyWith(
        coverImage: next,
        episodes: course.episodes
            .map((LibraryEpisodeItem episode) {
              final String existing = episode.coverImage.trim();
              final bool placeholder =
                  existing.isEmpty ||
                  existing.startsWith('assets/') ||
                  existing == 'assets/img/app_icon.png';
              return placeholder
                  ? episode.copyWith(coverImage: next)
                  : episode;
            })
            .toList(growable: false),
      );
    }).toList(growable: false);
    if (changed) {
      await _persistImportedCourses();
    }
  }

  /// Point a single-episode Bilibili course at a local media file.
  ///
  /// Never stamps one MP4 onto every member of a 合集/分P course.
  Future<void> updateCourseVideoAsset({
    required String courseId,
    required String videoAsset,
  }) async {
    final String next = videoAsset.trim();
    if (next.isEmpty) {
      return;
    }
    bool changed = false;
    state = state.map((LibraryCourseData course) {
      if (course.id != courseId) {
        return course;
      }
      if (course.episodes.length > 1) {
        // Multi-episode courses must update per episode via
        // [updateEpisodeLocalMedia] / prepare-on-play.
        return course;
      }
      changed = true;
      return course.copyWith(
        episodes: course.episodes
            .map(
              (LibraryEpisodeItem episode) => episode.copyWith(
                videoAsset: next,
                videoMissing: false,
              ),
            )
            .toList(growable: false),
      );
    }).toList(growable: false);
    if (changed) {
      await _persistImportedCourses();
    }
  }

  /// Persist one Bilibili episode's local video / subs / cover after download.
  Future<void> updateEpisodeLocalMedia({
    required String courseId,
    required String episodeId,
    String? videoAsset,
    String? sourceUrl,
    String? enSubtitlePath,
    String? zhSubtitlePath,
    String? coverImage,
    bool? videoMissing,
    bool clearSubtitles = false,
  }) async {
    bool changed = false;
    state = state.map((LibraryCourseData course) {
      if (course.id != courseId) {
        return course;
      }
      final List<LibraryEpisodeItem> episodes = course.episodes.map((
        LibraryEpisodeItem episode,
      ) {
        if (episode.id != episodeId) {
          return episode;
        }
        changed = true;
        // Preserve watch URL when downloading overwrites videoAsset with MP4.
        String? nextSource = (sourceUrl ?? '').trim().isNotEmpty
            ? sourceUrl!.trim()
            : episode.sourceUrl;
        final String? previousAsset = episode.videoAsset?.trim();
        if ((nextSource == null || nextSource.isEmpty) &&
            previousAsset != null &&
            (BilibiliImport.isWatchPageUrl(previousAsset) ||
                BilibiliImport.looksLikeBilibiliInput(previousAsset))) {
          nextSource = previousAsset;
        }
        // clearSubtitles must not drop usable ASR or official softsubs.
        bool isProtectedSubtitlePath(String? path) {
          final String value = (path ?? '').trim();
          if (value.isEmpty || !isUsableSubtitlePath(value)) {
            return false;
          }
          final bool asr =
              value.contains(
                '${Platform.pathSeparator}episode_subtitles${Platform.pathSeparator}',
              ) ||
              value.contains('/episode_subtitles/') ||
              value.contains(r'\episode_subtitles\');
          final bool official =
              value.contains('${Platform.pathSeparator}bilibili${Platform.pathSeparator}') ||
              value.contains('/bilibili/') ||
              value.contains(r'\bilibili\');
          final bool netdisk =
              value.contains('${Platform.pathSeparator}netdisk${Platform.pathSeparator}') ||
              value.contains('/netdisk/') ||
              value.contains(r'\netdisk\');
          return asr || official || netdisk;
        }

        final String? nextEn;
        final String? nextZh;
        if (clearSubtitles) {
          final String? keptEn = isProtectedSubtitlePath(episode.enSubtitleAsset)
              ? episode.enSubtitleAsset
              : (isProtectedSubtitlePath(enSubtitlePath)
                    ? enSubtitlePath!.trim()
                    : null);
          final String? keptZh = isProtectedSubtitlePath(episode.cnSubtitleAsset)
              ? episode.cnSubtitleAsset
              : (isProtectedSubtitlePath(zhSubtitlePath)
                    ? zhSubtitlePath!.trim()
                    : null);
          nextEn = keptEn;
          nextZh = keptZh;
        } else {
          nextEn = isUsableSubtitlePath(enSubtitlePath)
              ? enSubtitlePath!.trim()
              : episode.enSubtitleAsset;
          nextZh = isUsableSubtitlePath(zhSubtitlePath)
              ? zhSubtitlePath!.trim()
              : episode.cnSubtitleAsset;
        }
        final List<LibrarySubtitleTrackItem> tracks =
            <LibrarySubtitleTrackItem>[
              if (isUsableSubtitlePath(nextEn))
                LibrarySubtitleTrackItem(
                  languageCode: 'en',
                  languageLabel: 'English',
                  path: nextEn!,
                ),
              if (isUsableSubtitlePath(nextZh))
                LibrarySubtitleTrackItem(
                  languageCode: 'zh',
                  languageLabel: '中文',
                  path: nextZh!,
                ),
            ];
        return episode.copyWith(
          videoAsset: (videoAsset ?? '').trim().isNotEmpty
              ? videoAsset!.trim()
              : episode.videoAsset,
          sourceUrl: nextSource,
          videoMissing: videoMissing,
          enSubtitleAsset: nextEn,
          cnSubtitleAsset: nextZh,
          hasEnglishSubtitles: isUsableSubtitlePath(nextEn),
          hasChineseSubtitles: isUsableSubtitlePath(nextZh),
          coverImage: (coverImage ?? '').trim().isNotEmpty
              ? coverImage!.trim()
              : episode.coverImage,
          subtitleTracks: tracks.isNotEmpty
              ? tracks
              : (clearSubtitles
                    ? const <LibrarySubtitleTrackItem>[]
                    : episode.subtitleTracks),
        );
      }).toList(growable: false);
      return course.copyWith(episodes: episodes);
    }).toList(growable: false);
    if (changed) {
      await _persistImportedCourses();
    }
  }

  /// Re-attach ASR `episode_subtitles/{id}/en.srt|zh.srt` onto the library row.
  Future<void> relinkEpisodeSubtitleFiles({
    required String episodeId,
    bool clearChineseIfMissing = false,
    bool clearEnglishIfMissing = false,
  }) async {
    final String id = episodeId.trim();
    if (id.isEmpty) {
      return;
    }
    LibraryCourseData? course;
    for (final LibraryCourseData c in state) {
      if (c.episodes.any((LibraryEpisodeItem e) => e.id == id)) {
        course = c;
        break;
      }
    }
    if (course == null) {
      return;
    }
    final Directory root = await getApplicationSupportDirectory();
    final ({String? en, String? zh}) paths = _episodeSubtitleDiskPaths(
      root: root,
      episodeId: id,
    );
    final bool hasEn = isUsableSubtitlePath(paths.en);
    final bool hasZh = isUsableSubtitlePath(paths.zh);
    await updateEpisodeLocalMedia(
      courseId: course.id,
      episodeId: id,
      enSubtitlePath: hasEn
          ? paths.en
          : (clearEnglishIfMissing ? '' : null),
      zhSubtitlePath: hasZh
          ? paths.zh
          : (clearChineseIfMissing ? '' : null),
      clearSubtitles: false,
    );
    // Empty-string paths above won't clear via isUsableSubtitlePath — force.
    if ((clearChineseIfMissing && !hasZh) ||
        (clearEnglishIfMissing && !hasEn)) {
      state = state.map((LibraryCourseData c) {
        if (c.id != course!.id) {
          return c;
        }
        return c.copyWith(
          episodes: c.episodes.map((LibraryEpisodeItem e) {
            if (e.id != id) {
              return e;
            }
            final String? nextEn = clearEnglishIfMissing && !hasEn
                ? null
                : (hasEn ? paths.en : e.enSubtitleAsset);
            final String? nextZh = clearChineseIfMissing && !hasZh
                ? null
                : (hasZh ? paths.zh : e.cnSubtitleAsset);
            return e.copyWith(
              enSubtitleAsset: nextEn,
              cnSubtitleAsset: nextZh,
              hasEnglishSubtitles: isUsableSubtitlePath(nextEn),
              hasChineseSubtitles: isUsableSubtitlePath(nextZh),
            );
          }).toList(growable: false),
        );
      }).toList(growable: false);
      await _persistImportedCourses();
    }
  }

  /// Scan every episode and re-attach on-disk ASR + official softsubs.
  ///
  /// Prefer `episode_subtitles/{id}/en.srt|zh.srt` when present; otherwise
  /// rediscover B站 official files under `bilibili/<BV>/`. Call on bootstrap
  /// so library chips stay linked even after a bad clear.
  Future<int> relinkAllEpisodeSubtitleFiles() async {
    final Directory root = await getApplicationSupportDirectory();
    bool changed = false;
    final List<LibraryCourseData> nextCourses = <LibraryCourseData>[];
    for (final LibraryCourseData course in state) {
      final List<LibraryEpisodeItem> episodes = <LibraryEpisodeItem>[];
      for (final LibraryEpisodeItem episode in course.episodes) {
        final ({String? en, String? zh}) disk = _episodeSubtitleDiskPaths(
          root: root,
          episodeId: episode.id,
        );
        final bool hasAsrEn = isUsableSubtitlePath(disk.en);
        final bool hasAsrZh = isUsableSubtitlePath(disk.zh);
        final String? sourceKey = bilibiliEpisodeCacheKey(
          course: course,
          episode: episode,
          sourceUrl: episode.sourceUrl,
          videoAsset: episode.videoAsset,
        );
        // Official B站 softsubs win over ASR episode_subtitles when both exist.
        final String? officialEn = await existingOfficialBilibiliSubtitle(
          idKey: sourceKey,
          fileName: 'en.srt',
        );
        final String? officialZh = await existingOfficialBilibiliSubtitle(
          idKey: sourceKey,
          fileName: 'zh.srt',
        );
        String? nextEn = officialEn;
        String? nextZh = officialZh;
        if (nextEn == null && isUsableSubtitlePath(episode.enSubtitleAsset)) {
          nextEn = episode.enSubtitleAsset;
        }
        if (nextZh == null && isUsableSubtitlePath(episode.cnSubtitleAsset)) {
          nextZh = episode.cnSubtitleAsset;
        }
        nextEn ??= hasAsrEn ? disk.en : null;
        nextZh ??= hasAsrZh ? disk.zh : null;
        final bool enFlag = isUsableSubtitlePath(nextEn);
        final bool zhFlag = isUsableSubtitlePath(nextZh);
        final bool tracksStale = episode.subtitleTracks.any(
          (LibrarySubtitleTrackItem t) => !isUsableSubtitlePath(t.path),
        );
        if (nextEn == episode.enSubtitleAsset &&
            nextZh == episode.cnSubtitleAsset &&
            enFlag == episode.hasEnglishSubtitles &&
            zhFlag == episode.hasChineseSubtitles &&
            !tracksStale) {
          episodes.add(episode);
          continue;
        }
        changed = true;
        episodes.add(
          episode.copyWith(
            enSubtitleAsset: nextEn,
            cnSubtitleAsset: nextZh,
            hasEnglishSubtitles: enFlag,
            hasChineseSubtitles: zhFlag,
            subtitleTracks: <LibrarySubtitleTrackItem>[
              if (enFlag)
                LibrarySubtitleTrackItem(
                  languageCode: 'en',
                  languageLabel: 'English',
                  path: nextEn!,
                ),
              if (zhFlag)
                LibrarySubtitleTrackItem(
                  languageCode: 'zh',
                  languageLabel: '中文',
                  path: nextZh!,
                ),
            ],
          ),
        );
      }
      nextCourses.add(course.copyWith(episodes: episodes));
    }
    if (!changed) {
      return 0;
    }
    state = nextCourses;
    await _persistImportedCourses();
    return nextCourses.fold<int>(
      0,
      (int sum, LibraryCourseData c) =>
          sum +
          c.episodes
              .where(
                (LibraryEpisodeItem e) =>
                    isUsableSubtitlePath(e.enSubtitleAsset) ||
                    isUsableSubtitlePath(e.cnSubtitleAsset),
              )
              .length,
    );
  }

  ({String? en, String? zh}) _episodeSubtitleDiskPaths({
    required Directory root,
    required String episodeId,
  }) {
    final String safeId = episodeId
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
    if (safeId.isEmpty) {
      return (en: null, zh: null);
    }
    final Directory dir = Directory(
      '${root.path}${Platform.pathSeparator}episode_subtitles'
      '${Platform.pathSeparator}$safeId',
    );
    return (
      en: '${dir.path}${Platform.pathSeparator}en.srt',
      zh: '${dir.path}${Platform.pathSeparator}zh.srt',
    );
  }

  Future<void> updateEpisodeProgress({
    required String episodeId,
    required Duration position,
    required Duration duration,
    DateTime? occurredAt,
  }) async {
    if (duration <= Duration.zero || position <= Duration.zero) {
      return;
    }
    final int nextProgress =
        ((position.inMilliseconds * 100) / duration.inMilliseconds)
            .round()
            .clamp(0, 100);
    final int studiedAtMs =
        (occurredAt ?? DateTime.now()).millisecondsSinceEpoch;
    bool changed = false;
    final List<LibraryCourseData> updated = state
        .map((LibraryCourseData course) {
          final LibraryEpisodeItem? current = course.episodes
              .where((LibraryEpisodeItem item) => item.id == episodeId)
              .firstOrNull;
          if (current == null) return course;
          final bool progressChanged = nextProgress > current.progressPercent;
          // Record rewatching too, without writing to disk on every video tick.
          final bool refreshRecency =
              _lastStudiedCourseId != course.id ||
              course.lastStudiedAtMs == null ||
              studiedAtMs - course.lastStudiedAtMs! >= 10000;
          _lastStudiedCourseId = course.id;
          if (!progressChanged && !refreshRecency) return course;
          changed = true;
          if (!progressChanged) {
            return course.copyWith(
              lastStudiedAtMs: studiedAtMs,
              lastStudiedStr: '刚刚学习',
            );
          }
          final List<LibraryEpisodeItem> episodes = course.episodes
              .map(
                (LibraryEpisodeItem item) => item.id == episodeId
                    ? item.copyWith(
                        progressPercent: nextProgress,
                        completed: nextProgress == 100,
                        lastWatchedStr: '刚刚学习',
                        progressTimeStr: _formatDuration(position),
                        totalTimeStr: _formatDuration(duration),
                      )
                    : item,
              )
              .toList(growable: false);
          final int completedEpisodes = episodes
              .where((LibraryEpisodeItem item) => item.completed)
              .length;
          final int courseProgress =
              (episodes.fold<int>(0, (int sum, LibraryEpisodeItem item) {
                        return sum + item.progressPercent;
                      }) /
                      episodes.length)
                  .round();
          return course.copyWith(
            episodes: episodes,
            progressPercent: courseProgress,
            completedEpisodes: completedEpisodes,
            lastStudiedStr: '刚刚学习',
            lastStudiedAtMs: studiedAtMs,
          );
        })
        .toList(growable: false);
    if (changed) {
      state = updated;
      await _persistImportedCourses();
    }
  }

  String _formatDuration(Duration duration) {
    final int totalSeconds = duration.inSeconds;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> deleteCourses(Set<String> courseIds) async {
    if (courseIds.isEmpty) {
      return;
    }
    final List<LibraryCourseData> removedCourses = state
        .where((LibraryCourseData course) => courseIds.contains(course.id))
        .toList(growable: false);
    state = state
        .where((LibraryCourseData course) => !courseIds.contains(course.id))
        .toList(growable: false);
    await _deleteManagedImportDirectories(removedCourses);
    await _persistImportedCourses();
  }

  Future<bool> importCourseFromMatches({
    required List<ImportMatchRow> rows,
    required String videoFolder,
    required String subtitleFolder,
    String sourceLabel = '本地资源',
    String? targetCourseId,
    String? courseTitle,
    String spokenLanguage = '',
  }) async {
    if (rows.isEmpty) {
      return false;
    }

    final LibraryCourseData? targetCourse = targetCourseId == null
        ? null
        : state
              .where((LibraryCourseData item) => item.id == targetCourseId)
              .firstOrNull;
    if (targetCourseId != null && targetCourse == null) {
      return false;
    }

    final String courseId =
        targetCourse?.id ?? _buildCourseId(videoFolder, rows);
    final List<ImportMatchRow> newRows = targetCourse == null
        ? rows
        : rows
              .where(
                (ImportMatchRow row) => !targetCourse.episodes.any(
                  (LibraryEpisodeItem episode) =>
                      episode.videoAsset == row.videoPath,
                ),
              )
              .toList(growable: false);
    if (newRows.isEmpty) {
      return false;
    }
    final Set<String> occupiedIds =
        targetCourse?.episodes.map((LibraryEpisodeItem e) => e.id).toSet() ??
        <String>{};
    final List<LibraryEpisodeItem> episodes = <LibraryEpisodeItem>[
      for (int index = 0; index < newRows.length; index++)
        _buildEpisodeItem(
          newRows[index],
          courseId: courseId,
          episodeId: _buildEpisodeId(
            courseId,
            newRows[index],
            (targetCourse?.episodes.length ?? 0) + index,
            occupiedIds,
          ),
          coverImage: '',
        ),
    ];

    if (targetCourse != null) {
      final List<LibraryEpisodeItem> mergedEpisodes = <LibraryEpisodeItem>[
        ...targetCourse.episodes,
        ...episodes,
      ];
      state = state
          .map(
            (LibraryCourseData course) => course.id == targetCourse.id
                ? course.copyWith(
                    description: '已导入课程 ${mergedEpisodes.length} 集',
                    totalEpisodes: mergedEpisodes.length,
                    episodes: mergedEpisodes,
                    spokenLanguage: spokenLanguage.trim().isEmpty
                        ? course.spokenLanguage
                        : spokenLanguage.trim(),
                    videoDirectories: <String>{
                      ...course.videoDirectories,
                      videoFolder,
                    }.where((String path) => path.isNotEmpty).toList(),
                    subtitleDirectories: <String>{
                      ...course.subtitleDirectories,
                      subtitleFolder,
                    }.where((String path) => path.isNotEmpty).toList(),
                  )
                : course,
          )
          .toList(growable: false);
      await _persistImportedCourses();
      return true;
    }

    return importCourse(
      LibraryCourseData(
        id: courseId,
        videoDirectories: videoFolder.isEmpty
            ? const <String>[]
            : <String>[videoFolder],
        subtitleDirectories: subtitleFolder.isEmpty
            ? const <String>[]
            : <String>[subtitleFolder],
        title: courseTitle == null || courseTitle.trim().isEmpty
            ? _buildCourseTitle(videoFolder, rows)
            : courseTitle.trim(),
        description: '已导入课程 ${episodes.length} 集',
        sourceLabel: sourceLabel,
        spokenLanguage: spokenLanguage.trim(),
        coverImage: '',
        level: '自定义',
        category: '自选课程',
        progressPercent: 0,
        totalWords: 0,
        completedEpisodes: 0,
        totalEpisodes: episodes.length,
        lastStudiedStr: '刚刚导入',
        rating: 4.7,
        episodes: episodes,
      ),
    );
  }

  Future<void> _persistImportedCourses() async {
    if (!Hive.isBoxOpen('prefs')) {
      return;
    }

    final List<Map<String, Object?>> importedCourses = state
        .where(
          (LibraryCourseData course) => !libraryCourses.any(
            (LibraryCourseData base) => base.id == course.id,
          ),
        )
        .map(_serializeCourse)
        .toList(growable: false);

    if (importedCourses.isEmpty) {
      await Hive.box<String>('prefs').delete(_libraryCatalogStorageKey);
      return;
    }

    await Hive.box<String>(
      'prefs',
    ).put(_libraryCatalogStorageKey, jsonEncode(importedCourses));
  }

  Map<String, Object?> _serializeCourse(LibraryCourseData course) {
    return <String, Object?>{
      'id': course.id,
      'videoDirectories': course.videoDirectories,
      'subtitleDirectories': course.subtitleDirectories,
      'title': course.title,
      'description': course.description,
      'sourceLabel': course.sourceLabel,
      'spokenLanguage': course.spokenLanguage,
      'coverImage': course.coverImage,
      'level': course.level,
      'category': course.category,
      'progressPercent': course.progressPercent,
      'totalWords': course.totalWords,
      'completedEpisodes': course.completedEpisodes,
      'totalEpisodes': course.totalEpisodes,
      'lastStudiedStr': course.lastStudiedStr,
      'lastStudiedAtMs': course.lastStudiedAtMs,
      'rating': course.rating,
      'episodes': course.episodes
          .map(
            (LibraryEpisodeItem item) => <String, Object?>{
              'id': item.id,
              'numberStr': item.numberStr,
              'title': item.title,
              'durationMinutes': item.durationMinutes,
              'hasChineseSubtitles': item.hasChineseSubtitles,
              'hasEnglishSubtitles': item.hasEnglishSubtitles,
              'completed': item.completed,
              'progressPercent': item.progressPercent,
              'coverImage': item.coverImage,
              'lastWatchedStr': item.lastWatchedStr,
              'progressTimeStr': item.progressTimeStr,
              'totalTimeStr': item.totalTimeStr,
              'videoAsset': item.videoAsset,
              'sourceUrl': item.sourceUrl,
              'videoMissing': item.videoMissing,
              'enSubtitleAsset': item.enSubtitleAsset,
              'cnSubtitleAsset': item.cnSubtitleAsset,
              'subtitleTracks': item.subtitleTracks
                  .map(
                    (LibrarySubtitleTrackItem track) => <String, Object?>{
                      'languageCode': track.languageCode,
                      'languageLabel': track.languageLabel,
                      'path': track.path,
                    },
                  )
                  .toList(growable: false),
            },
          )
          .toList(growable: false),
    };
  }

  List<LibraryCourseData> _decodeCourses(String raw) {
    try {
      final List<Object?> parsed = jsonDecode(raw) as List<Object?>;
      return parsed
          .cast<Map<String, Object?>>()
          .map((Map<String, Object?> courseJson) {
            final List<LibraryEpisodeItem> episodes = _decodeEpisodes(
              courseId: courseJson['id']! as String,
              episodesJson: courseJson['episodes'] as List<Object?>?,
            );

            return LibraryCourseData(
              id: courseJson['id']! as String,
              videoDirectories:
                  (courseJson['videoDirectories'] as List<Object?>? ??
                          const <Object?>[])
                      .cast<String>(),
              subtitleDirectories:
                  (courseJson['subtitleDirectories'] as List<Object?>? ??
                          const <Object?>[])
                      .cast<String>(),
              title: courseJson['title']! as String,
              description: courseJson['description']! as String,
              sourceLabel: courseJson['sourceLabel'] as String? ?? '本地资源',
              spokenLanguage: courseJson['spokenLanguage'] as String? ?? '',
              coverImage: courseJson['coverImage']! as String,
              level: courseJson['level']! as String,
              category: courseJson['category']! as String,
              progressPercent: courseJson['progressPercent']! as int,
              totalWords: courseJson['totalWords']! as int,
              completedEpisodes: courseJson['completedEpisodes']! as int,
              totalEpisodes: episodes.length,
              lastStudiedStr: courseJson['lastStudiedStr']! as String,
              lastStudiedAtMs: (courseJson['lastStudiedAtMs'] as num?)?.toInt(),
              rating: (courseJson['rating'] as num?)?.toDouble() ?? 0.0,
              episodes: episodes,
            );
          })
          .toList(growable: false);
    } catch (_) {
      return const <LibraryCourseData>[];
    }
  }

  List<LibraryEpisodeItem> _decodeEpisodes({
    required String courseId,
    required List<Object?>? episodesJson,
  }) {
    if (episodesJson == null) {
      return const <LibraryEpisodeItem>[];
    }

    final Set<String> seenIds = <String>{};
    final List<Map<String, Object?>> items = episodesJson
        .cast<Map<String, Object?>>()
        .where(_shouldKeepStoredEpisode)
        .toList(growable: false);
    return <LibraryEpisodeItem>[
      for (int index = 0; index < items.length; index++)
        _decodeEpisodeItem(
          courseId: courseId,
          json: items[index],
          index: index,
          seenIds: seenIds,
        ),
    ];
  }

  LibraryEpisodeItem _decodeEpisodeItem({
    required String courseId,
    required Map<String, Object?> json,
    required int index,
    required Set<String> seenIds,
  }) {
    final String storedId = json['id'] as String? ?? '';
    final String resolvedId = storedId.isNotEmpty && seenIds.add(storedId)
        ? storedId
        : '$courseId-ep${(index + 1).toString().padLeft(2, '0')}';
    seenIds.add(resolvedId);

    return LibraryEpisodeItem(
      id: resolvedId,
      videoMissing: json['videoMissing'] as bool? ?? false,
      numberStr: json['numberStr']! as String,
      title: json['title']! as String,
      durationMinutes: json['durationMinutes']! as int,
      hasChineseSubtitles: json['hasChineseSubtitles']! as bool,
      hasEnglishSubtitles: json['hasEnglishSubtitles']! as bool,
      completed: json['completed']! as bool,
      progressPercent: json['progressPercent']! as int,
      coverImage: json['coverImage'] as String? ?? '',
      lastWatchedStr: json['lastWatchedStr'] as String?,
      progressTimeStr: json['progressTimeStr'] as String?,
      totalTimeStr: json['totalTimeStr'] as String?,
      videoAsset: _sanitizeStoredPath(json['videoAsset'] as String?),
      sourceUrl: (json['sourceUrl'] as String?)?.trim().isNotEmpty == true
          ? (json['sourceUrl'] as String).trim()
          : null,
      enSubtitleAsset: _sanitizeStoredPath(json['enSubtitleAsset'] as String?),
      cnSubtitleAsset: _sanitizeStoredPath(json['cnSubtitleAsset'] as String?),
      subtitleTracks:
          ((json['subtitleTracks'] as List<Object?>?) ?? const <Object?>[])
              .cast<Map<String, Object?>>()
              .where(
                (Map<String, Object?> track) => ImportMatcher.isImportablePath(
                  track['path'] as String? ?? '',
                ),
              )
              .map(
                (Map<String, Object?> track) => LibrarySubtitleTrackItem(
                  languageCode: track['languageCode']! as String,
                  languageLabel: track['languageLabel']! as String,
                  path: track['path']! as String,
                ),
              )
              .toList(growable: false),
    );
  }

  String _buildCourseId(String videoFolder, List<ImportMatchRow> rows) {
    final String prefix = videoFolder.isNotEmpty
        ? _slug(videoFolder.split(RegExp(r'[\\/]')).last.replaceAll('-', '_'))
        : rows.isNotEmpty
        ? _slug(_stripExtension(rows.first.videoFile))
        : 'imported_course';
    return rows.isNotEmpty && rows.first.videoFile.isNotEmpty
        ? '$prefix-${_slug(rows.first.videoFile)}'
        : 'imported_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _buildCourseTitle(String videoFolder, List<ImportMatchRow> rows) {
    final List<String> segments = videoFolder
        .split(RegExp(r'[\\/]'))
        .where((String item) => item.trim().isNotEmpty)
        .toList(growable: false);
    if (segments.isNotEmpty && segments.last.trim().isNotEmpty) {
      return segments.last.trim();
    }
    if (rows.isNotEmpty) {
      return _stripExtension(rows.first.videoFile).trim();
    }
    return '已导入课程';
  }

  bool _shouldKeepStoredEpisode(Map<String, Object?> json) {
    final String videoPath = json['videoAsset'] as String? ?? '';
    if (!ImportMatcher.isImportablePath(videoPath)) {
      return false;
    }

    final List<String> subtitlePaths = <String>[
      json['enSubtitleAsset'] as String? ?? '',
      json['cnSubtitleAsset'] as String? ?? '',
      ...(((json['subtitleTracks'] as List<Object?>?) ?? const <Object?>[])
          .cast<Map<String, Object?>>()
          .map((Map<String, Object?> track) => track['path'] as String? ?? '')),
    ].where((String path) => path.trim().isNotEmpty).toList(growable: false);

    final bool containsVerifySubtitle = subtitlePaths.any(
      (String path) => !ImportMatcher.isImportablePath(path),
    );
    if (!containsVerifySubtitle) {
      return true;
    }

    final String normalizedVideoName = videoPath
        .replaceAll(r'\', '/')
        .split('/')
        .last
        .toLowerCase();
    final String normalizedTitle = (json['title'] as String? ?? '')
        .trim()
        .toLowerCase();
    return !normalizedVideoName.startsWith('lesson') &&
        !normalizedTitle.startsWith('lesson');
  }

  String? _sanitizeStoredPath(String? path) {
    if (path == null || path.trim().isEmpty) {
      return path;
    }
    return ImportMatcher.isImportablePath(path) ? path : null;
  }

  LibraryEpisodeItem? _findMatchingEpisode(
    List<LibraryEpisodeItem> previous,
    LibraryEpisodeItem next,
  ) {
    for (final LibraryEpisodeItem item in previous) {
      if (item.id == next.id) {
        return item;
      }
    }
    final String? nextKey = _episodeMediaKey(next);
    if (nextKey == null || nextKey.isEmpty) {
      return null;
    }
    for (final LibraryEpisodeItem item in previous) {
      final String? key = _episodeMediaKey(item);
      if (key != null && key == nextKey) {
        return item;
      }
    }
    return null;
  }

  String? _episodeMediaKey(LibraryEpisodeItem episode) {
    for (final String? candidate in <String?>[
      episode.sourceUrl,
      episode.videoAsset,
    ]) {
      if (candidate == null || candidate.trim().isEmpty) {
        continue;
      }
      final String? fromPath = bilibiliIdKeyFromPath(candidate);
      if (fromPath != null && fromPath.isNotEmpty) {
        return fromPath.toUpperCase();
      }
      final Map<String, String>? ids = BilibiliImport.extractIds(candidate);
      final String? bvid = ids?['bvid']?.trim();
      if (bvid != null && bvid.isNotEmpty) {
        return bvid.toUpperCase();
      }
      final String? aid = ids?['aid']?.trim();
      if (aid != null && aid.isNotEmpty) {
        return 'AV$aid';
      }
    }
    return null;
  }

  /// Keep progress + already-downloaded local MP4/subs when a re-import only
  /// refreshed the current episode (other 合集分集 would otherwise revert to
  /// watch URLs and re-download on open).
  LibraryEpisodeItem _mergeImportedEpisode({
    required LibraryEpisodeItem next,
    required LibraryEpisodeItem? previous,
  }) {
    if (previous == null) {
      return next;
    }
    final bool nextHasVideo = isUsableLocalVideoPath(next.videoAsset);
    final bool prevHasVideo = isUsableLocalVideoPath(previous.videoAsset);
    final bool nextHasEn = isUsableSubtitlePath(next.enSubtitleAsset);
    final bool prevHasEn = isUsableSubtitlePath(previous.enSubtitleAsset);
    final bool nextHasZh = isUsableSubtitlePath(next.cnSubtitleAsset);
    final bool prevHasZh = isUsableSubtitlePath(previous.cnSubtitleAsset);
    final String? mergedVideo = nextHasVideo
        ? next.videoAsset
        : (prevHasVideo ? previous.videoAsset : next.videoAsset);
    final String? mergedSource =
        (next.sourceUrl ?? '').trim().isNotEmpty
        ? next.sourceUrl
        : previous.sourceUrl;
    // Never keep previous CC when the durable source BV/page changed — that
    // reintroduced 合集/分P 串台 after re-import/expand.
    final String? nextSourceKey = bilibiliEpisodeCacheKey(
      sourceUrl: mergedSource,
      episode: next,
    );
    final String? prevEnKey = bilibiliIdKeyFromPath(previous.enSubtitleAsset);
    final String? prevZhKey = bilibiliIdKeyFromPath(previous.cnSubtitleAsset);
    final bool prevEnAligned = bilibiliMediaKeysAligned(prevEnKey, nextSourceKey);
    final bool prevZhAligned = bilibiliMediaKeysAligned(prevZhKey, nextSourceKey);
    final String? mergedEn = nextHasEn
        ? next.enSubtitleAsset
        : (prevHasEn && prevEnAligned
              ? previous.enSubtitleAsset
              : next.enSubtitleAsset);
    final String? mergedZh = nextHasZh
        ? next.cnSubtitleAsset
        : (prevHasZh && prevZhAligned
              ? previous.cnSubtitleAsset
              : next.cnSubtitleAsset);
    final bool hasLocalVideo = isUsableLocalVideoPath(mergedVideo);
    return next.copyWith(
      completed: previous.completed,
      progressPercent: previous.progressPercent,
      lastWatchedStr: previous.lastWatchedStr,
      progressTimeStr: previous.progressTimeStr,
      totalTimeStr: previous.totalTimeStr,
      videoAsset: mergedVideo,
      sourceUrl: mergedSource,
      videoMissing: hasLocalVideo ? false : next.videoMissing,
      enSubtitleAsset: mergedEn,
      cnSubtitleAsset: mergedZh,
      hasEnglishSubtitles: isUsableSubtitlePath(mergedEn),
      hasChineseSubtitles: isUsableSubtitlePath(mergedZh),
      subtitleTracks: next.subtitleTracks.isNotEmpty
          ? next.subtitleTracks
          : previous.subtitleTracks,
      coverImage: next.coverImage.trim().isNotEmpty
          ? next.coverImage
          : previous.coverImage,
    );
  }

  String _buildEpisodeId(
    String courseId,
    ImportMatchRow row,
    int index,
    Set<String> occupiedIds,
  ) {
    int episodeNumber = index + 1;
    String id;
    do {
      id = '$courseId-ep${(episodeNumber++).toString().padLeft(2, '0')}';
    } while (!occupiedIds.add(id));
    return id;
  }

  LibraryEpisodeItem _buildEpisodeItem(
    ImportMatchRow row, {
    required String courseId,
    required String episodeId,
    required String coverImage,
  }) {
    final String number = _extractEpisodeNumber(
      row.episodeName,
    ).toString().padLeft(2, '0');
    return LibraryEpisodeItem(
      subtitleTracks: row.subtitleTracks.values
          .map(
            (ImportSubtitleTrack track) => LibrarySubtitleTrackItem(
              languageCode: track.languageCode,
              languageLabel: track.languageLabel,
              path: track.path,
            ),
          )
          .toList(growable: false),
      id: episodeId,
      numberStr: number,
      title: row.episodeName,
      durationMinutes: 30,
      hasChineseSubtitles: row.hasChinese,
      hasEnglishSubtitles: row.hasEnglish,
      completed: false,
      progressPercent: 0,
      coverImage: coverImage,
      videoAsset: row.videoPath,
      enSubtitleAsset: row.englishSubtitlePath,
      cnSubtitleAsset: row.chineseSubtitlePath,
    );
  }

  int _extractEpisodeNumber(String name) {
    final RegExp matcher = RegExp(r'(\d+)');
    final Match? match = matcher.firstMatch(name);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(1) ?? '0') ?? 0;
  }

  String _stripExtension(String value) {
    final int index = value.lastIndexOf('.');
    if (index <= 0) {
      return value;
    }
    return value.substring(0, index);
  }

  String _slug(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp('_+'), '_')
        .replaceAll(RegExp(r'^_|_\$'), '');
  }

  Future<void> _deleteManagedImportDirectories(
    List<LibraryCourseData> courses,
  ) async {
    final Set<String> directories = <String>{};
    for (final LibraryCourseData course in courses) {
      for (final LibraryEpisodeItem episode in course.episodes) {
        for (final String? path in <String?>[
          episode.videoAsset,
          episode.enSubtitleAsset,
          episode.cnSubtitleAsset,
          ...episode.subtitleTracks.map(
            (LibrarySubtitleTrackItem item) => item.path,
          ),
        ]) {
          final String? managedDirectory = _managedImportDirectoryForPath(path);
          if (managedDirectory != null) {
            directories.add(managedDirectory);
          }
        }
      }
    }

    final List<String> sortedDirectories = directories.toList(growable: false)
      ..sort((String a, String b) => b.length.compareTo(a.length));
    for (final String directoryPath in sortedDirectories) {
      final Directory directory = Directory(directoryPath);
      if (!directory.existsSync()) {
        continue;
      }
      try {
        await directory.delete(recursive: true);
      } catch (_) {
        // ponytail: best-effort cleanup; stale files are less bad than blocked deletion.
      }
    }
  }

  String? _managedImportDirectoryForPath(String? rawPath) {
    if (rawPath == null || rawPath.trim().isEmpty) {
      return null;
    }
    final String normalized = rawPath.replaceAll(r'\', '/');
    const String marker = '/imported_sources/';
    final int markerIndex = normalized.indexOf(marker);
    if (markerIndex < 0) {
      return null;
    }

    final String prefix = normalized.substring(0, markerIndex + marker.length);
    final List<String> segments = normalized
        .substring(markerIndex + marker.length)
        .split('/')
        .where((String segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return null;
    }

    final List<String> managedSegments =
        segments.first == 'confirmed_imports' && segments.length >= 2
        ? <String>['confirmed_imports', segments[1]]
        : <String>[segments.first];
    return '$prefix${managedSegments.join('/')}';
  }
}
