import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';

import '../../../router/app_router.dart';
import '../../import_course/data/bilibili_collection_download.dart';
import '../../import_course/data/bilibili_cover_refresh.dart';
import '../../import_course/data/bilibili_episode_cover_backfill.dart';
import '../../import_course/data/bilibili_import_service.dart';
import '../../import_course/data/netdisk_local_download.dart';
import '../../import_course/presentation/course_import_entry.dart';
import '../../import_course/presentation/widgets/import_course_flow.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../player/presentation/asr_subtitle_cache.dart';
import '../../player/presentation/full_transcript_reader.dart';
import '../../player/presentation/learning_resume_provider.dart';
import '../../player/presentation/manual_subtitle_guard.dart';
import '../../player/presentation/player_course_lookup.dart';
import '../../player/presentation/player_mock_state.dart';
import '../../player/presentation/player_subtitle_loader.dart';
import '../../player/presentation/transcript_reader_session.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_lookup_service.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_compact.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../import_course/data/bilibili_episode_prepare.dart';
import '../../subtitle_completion/reset_episode_subtitles.dart';
import '../../subtitle_completion/subtitle_completion_enqueue.dart';
import '../../subtitle_completion/subtitle_completion_queue.dart';
import '../../subtitle_completion/subtitle_completion_scheduler.dart';
import '../../subtitle_completion/subtitle_completion_status_provider.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../words/data/offline_word_dictionary.dart';
import 'library_browse.dart';
import 'library_catalog_provider.dart';
import 'library_mock_data.dart';
import 'widgets/course_overview_card.dart';
import 'widgets/course_resource_directory_dialog.dart';
import 'widgets/episode_list_item.dart';
import 'widgets/library_course_card.dart';
import 'widgets/library_course_list_item.dart';
import 'widgets/library_feed_card.dart';

export 'library_browse.dart'
    show LibraryCourseSort, LibraryCourseViewMode;

const String _libraryViewModePrefsKey = 'library_course_view_mode_v1';
const String _librarySortPrefsKey = 'library_course_sort_v1';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({
    super.key,
    this.initialView = LibraryScreenView.list,
    this.initialCourseId,
    this.initialEpisodeId,
    this.pickCoverImage,
    this.openTranscriptReader,
  });

  final LibraryScreenView initialView;
  final String? initialCourseId;
  final String? initialEpisodeId;
  final Future<String?> Function()? pickCoverImage;
  final Future<void> Function(
    LibraryCourseData course,
    LibraryEpisodeItem episode,
  )? openTranscriptReader;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}
enum LibraryScreenView { list, detail, import }

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final TranscriptReaderSession transcriptReaderSession =
      TranscriptReaderSession();
  late bool showDetail;
  late bool showImport;
  final ImportCourseFlowController importFlowController =
      ImportCourseFlowController();
  late final TextEditingController queryController;
  late final ScrollController listScrollController;
  bool appliedInitialSelection = false;
  LibraryCourseViewMode viewMode = LibraryCourseViewMode.grid;
  LibraryCourseSort courseSort = LibraryCourseSort.recent;
  String query = '';
  bool editMode = false;
  bool showScrollToTop = false;
  LibraryCourseData selectedCourse = emptyLibraryCourse;
  String selectedEpisodeId = '';
  String episodeSort = '自然排序';
  final Set<String> selectedCourseIds = <String>{};
  final Map<String, List<String>> customEpisodeOrders =
      <String, List<String>>{};

  @override
  void initState() {
    super.initState();
    showImport = widget.initialView == LibraryScreenView.import;
    showDetail = widget.initialView == LibraryScreenView.detail;
    _restoreBrowsePrefs();
    queryController = TextEditingController()
      ..addListener(() {
        setState(() {});
      });
    listScrollController = ScrollController()
      ..addListener(() {
        final bool nextVisible = listScrollController.offset > 320;
        if (nextVisible != showScrollToTop) {
          setState(() {
            showScrollToTop = nextVisible;
          });
        }
      });
  }

  void _restoreBrowsePrefs() {
    if (!Hive.isBoxOpen('prefs')) {
      return;
    }
    final Box<String> box = Hive.box<String>('prefs');
    viewMode = LibraryCourseViewModeLabel.fromStorage(
      box.get(_libraryViewModePrefsKey),
    );
    courseSort = LibraryCourseSortLabel.fromStorage(
      box.get(_librarySortPrefsKey),
    );
  }

  void _persistBrowsePrefs() {
    if (!Hive.isBoxOpen('prefs')) {
      return;
    }
    Hive.box<String>('prefs')
      ..put(_libraryViewModePrefsKey, viewMode.storageValue)
      ..put(_librarySortPrefsKey, courseSort.storageValue);
  }

  @override
  void dispose() {
    transcriptReaderSession.dispose();
    importFlowController.dispose();
    queryController.dispose();
    listScrollController.dispose();
    super.dispose();
  }

  Future<void> _openTranscriptReader(
    LibraryCourseData course,
    LibraryEpisodeItem episode,
  ) async {
    final Future<void> Function(LibraryCourseData, LibraryEpisodeItem)?
    override = widget.openTranscriptReader;
    if (override != null) {
      await override(course, episode);
      return;
    }

    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    final PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: <LibraryCourseData>[course],
      episodeId: episode.id,
    );
    List<PlayerSubtitleLine> lines = const <PlayerSubtitleLine>[];
    Map<String, String> generatedMeanings = const <String, String>{};
    try {
      final String enPath = (resource.englishSubtitleAsset ?? '').trim();
      final String zhPath = (resource.chineseSubtitleAsset ?? '').trim();
      final List<PlayerSubtitleLine> englishLines = enPath.isEmpty
          ? const <PlayerSubtitleLine>[]
          : await loadSubtitleLines(enPath);
      final List<PlayerSubtitleLine> chineseLines = zhPath.isEmpty
          ? const <PlayerSubtitleLine>[]
          : await loadSubtitleLines(zhPath);
      if (englishLines.isNotEmpty || chineseLines.isNotEmpty) {
        // Prefer Chinese timeline + English overlay so EN originals are kept
        // even when the official "en" track is sparse or mislabeled ZH.
        if (chineseLines.isNotEmpty) {
          lines = mergePartialEnglishOntoChineseBase(
            chineseLines: chineseLines,
            englishLines: englishLines,
          );
        } else {
          lines = mergeSubtitleLines(
            englishLines: englishLines,
            chineseLines: chineseLines,
          );
        }
      }
      if (lines.isEmpty && (resource.videoAsset ?? '').isNotEmpty) {
        final String? cached = await const AsrSubtitleCache().read(
          episodeId: episode.id,
          videoPath: resource.videoAsset!,
          settings: settings,
          validateReferenceSignature: false,
        );
        if (cached != null) {
          lines = parseSubtitleLines(cached);
          generatedMeanings = parseSubtitleGlossary(cached);
        }
      }
    } catch (_) {
      lines = const <PlayerSubtitleLine>[];
    }
    if (!mounted) return;
    if (lines.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前剧集没有可查看的全文字幕')));
      return;
    }

    final TranscriptReaderSnapshot snapshot =
        await buildTranscriptReaderSnapshot(
          courseTitle: course.title,
          episodeTitle: episode.title,
          lines: lines,
          activeLineIndex: 0,
          currentWordIndex: 0,
          generatedMeanings: generatedMeanings,
          dictionary: ref.read(offlineWordDictionaryProvider),
        );
    if (!mounted) return;
    final WordLookupService lookupService = ref.read(wordLookupServiceProvider);
    try {
      await transcriptReaderSession.open(
        context: context,
        snapshot: snapshot,
        lookupWord:
            ({required String rawWord, required String contextSentence}) =>
                lookupService.lookupWord(
                  rawWord: rawWord,
                  contextSentence: contextSentence,
                  settings: settings,
                ),
        translateSentence: (String sentence) => lookupService.translateSentence(
          sentence: sentence,
          settings: settings,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开全文，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(bilibiliCoverRefreshProvider);
    final bool compact = context.isPadCompact;
    final double pagePadding = context.padPagePadding;
    final List<LibraryCourseData> courses = ref.watch(libraryCatalogProvider);
    if (!appliedInitialSelection) {
      if (widget.initialCourseId != null) {
        for (final LibraryCourseData course in courses) {
          if (course.id == widget.initialCourseId) {
            selectedCourse = course;
            break;
          }
        }
      }
      if (widget.initialEpisodeId != null) {
        selectedEpisodeId = widget.initialEpisodeId!;
      }
      appliedInitialSelection = true;
    }
    final LibraryCourseData currentCourse = courses.firstWhere(
      (LibraryCourseData course) => course.id == selectedCourse.id,
      orElse: () => courses.isEmpty ? emptyLibraryCourse : courses.first,
    );
    selectedCourse = currentCourse;

    final List<LibraryCourseMatch> browsedCourses = browseLibraryCourses(
      courses: courses,
      query: query,
      sort: courseSort,
    );
    final List<LibraryCourseData> filteredCourses = browsedCourses
        .map((LibraryCourseMatch match) => match.course)
        .toList(growable: false);
    selectedCourseIds.removeWhere(
      (String id) => !courses.any((LibraryCourseData course) => course.id == id),
    );
    final List<LibraryEpisodeItem> visibleEpisodes = _visibleEpisodes(
      selectedCourse,
    );
    final LibraryEpisodeItem? activeEpisode = visibleEpisodes.isEmpty
        ? null
        : visibleEpisodes.firstWhere(
            (LibraryEpisodeItem item) => item.id == selectedEpisodeId,
            orElse: () => visibleEpisodes.first,
          );

    final bool canContinueLearning =
        ref.watch(continueLearningTargetProvider) != null;
    return PadScaffold(
      // Always show: morphs to「补字幕」while fill jobs run (detail + list).
      showContinueLearning: true,
      currentDestination: AppNavDestination.library,
      topBar: PadTopBar(
        title: showImport
            ? '导入影视'
            : showDetail
            ? selectedCourse.title
            : '影视库',
        subtitle: showImport
            ? '影视库'
            : showDetail
            ? activeEpisode == null
                  ? '暂无剧集'
                  : '第 ${activeEpisode.numberStr} 集'
            : null,
        description: showImport
            ? '把本地视频和字幕整理成新的学习片库。'
            : showDetail
            ? null
            : '挑一部继续放映，去新的场景里练耳朵。',
        leading: showImport
            ? AnimatedBuilder(
                animation: importFlowController,
                builder: (BuildContext context, _) {
                  return Tooltip(
                    message: importFlowController.canGoBack ? '返回上一步' : '返回影视库',
                    child: TextButton(
                      onPressed: importFlowController.canGoBack
                          ? importFlowController.goBack
                          : () {
                              setState(() {
                                showImport = false;
                                showDetail = false;
                              });
                            },
                      style: TextButton.styleFrom(
                        backgroundColor: AppDesignTokens.appWhite,
                        foregroundColor: AppDesignTokens.brandGreenDark,
                        minimumSize: const Size(44, 44),
                        padding: EdgeInsets.zero,
                        side: BorderSide(
                          color: AppDesignTokens.borderGray,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Icon(Icons.arrow_back_rounded, size: 18),
                    ),
                  );
                },
              )
            : showDetail
            ? Tooltip(
                message: '返回影视库',
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      showDetail = false;
                    });
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: AppDesignTokens.appWhite,
                    foregroundColor: AppDesignTokens.brandGreenDark,
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    side: BorderSide(
                      color: AppDesignTokens.borderGray,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Icon(Icons.arrow_back_rounded, size: 18),
                ),
              )
            : null,
        trailing: showDetail
            ? _LibraryDetailTopStatus(
                courseMeta: '${selectedCourse.level} · ${selectedCourse.category}',
                episodeName: activeEpisode?.title,
              )
            : null,
      ),
      body: showImport
          ? ImportCourseFlow(
              controller: importFlowController,
              showHeader: false,
              onCancel: () {
                setState(() {
                  showImport = false;
                  showDetail = false;
                });
              },
              onImportCompleted: () {
                setState(() {
                  showImport = false;
                  showDetail = false;
                });
              },
            )
          : showDetail
          ? Stack(
              children: <Widget>[
                ListView(
                  padding: EdgeInsets.fromLTRB(
                    pagePadding,
                    compact ? 22 : 28,
                    pagePadding,
                    120,
                  ),
                  children: <Widget>[
                    if (_pendingCollectionEpisodes(selectedCourse) > 0)
                      Consumer(
                        builder: (BuildContext context, WidgetRef ref, _) {
                          final BilibiliCollectionDownloadProgress? progress =
                              ref.watch(bilibiliCollectionDownloadProgressProvider);
                          final bool downloading = progress?.courseId == selectedCourse.id &&
                              progress?.done == false;
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: downloading ? null : () => unawaited(
                                _confirmCollectionDownload(selectedCourse),
                              ),
                              icon: const Icon(Icons.download_outlined),
                              label: Text(downloading
                                  ? '正在下载合集'
                                  : '下载剩余各集（${_pendingCollectionEpisodes(selectedCourse)}）'),
                            ),
                          );
                        },
                      ),
                    if (pendingNetdiskEpisodes(selectedCourse) > 0)
                      Consumer(
                        builder: (BuildContext context, WidgetRef ref, _) {
                          final NetdiskDownloadProgress? progress =
                              ref.watch(netdiskDownloadProgressProvider);
                          final bool downloading =
                              progress?.courseId == selectedCourse.id &&
                              progress?.done == false;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: downloading
                                    ? null
                                    : () => unawaited(
                                          _confirmNetdiskDownload(selectedCourse),
                                        ),
                                icon: const Icon(Icons.download_for_offline_outlined),
                                label: Text(
                                  downloading
                                      ? '正在下载到本机'
                                      : '下载到本机（在线慢时可离线播）',
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    // Course-level download / 补字幕 progress stays at the very top.
                    Consumer(
                      builder: (BuildContext context, WidgetRef ref, _) {
                        final BilibiliCollectionDownloadProgress? progress =
                            ref.watch(
                              bilibiliCollectionDownloadProgressProvider,
                            );
                        final NetdiskDownloadProgress? netdiskProgress =
                            ref.watch(netdiskDownloadProgressProvider);
                        final SubtitleCompletionCourseUi? subtitleFill = ref
                            .watch(subtitleCompletionStatusProvider)
                            .forCourse(
                              courseId: selectedCourse.id,
                              episodeIds: selectedCourse.episodes.map(
                                (LibraryEpisodeItem e) => e.id,
                              ),
                            );
                        final bool showDownload =
                            progress != null &&
                            progress.courseId == selectedCourse.id &&
                            !progress.done;
                        final bool showNetdiskDownload =
                            netdiskProgress != null &&
                            netdiskProgress.courseId == selectedCourse.id &&
                            !netdiskProgress.done;
                        final bool showSubtitle =
                            subtitleFill != null && subtitleFill.showBanner;
                        if (!showDownload &&
                            !showNetdiskDownload &&
                            !showSubtitle) {
                          return const SizedBox.shrink();
                        }
                        final String? downloadMessage = showNetdiskDownload
                            ? netdiskProgress.message
                            : (showDownload ? progress.message : null);
                        final double? downloadValue = showNetdiskDownload
                            ? netdiskProgress.progress
                            : (showDownload ? progress.progress : null);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              if (downloadMessage != null &&
                                  downloadValue != null) ...<Widget>[
                                Text(
                                  downloadMessage,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppDesignTokens.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: downloadValue.clamp(0.05, 1),
                                    minHeight: 8,
                                    backgroundColor: AppDesignTokens.softGray,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      AppDesignTokens.primaryBlue,
                                    ),
                                  ),
                                ),
                              ],
                              if ((showDownload || showNetdiskDownload) &&
                                  showSubtitle)
                                const SizedBox(height: 12),
                              if (showSubtitle) ...<Widget>[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        subtitleFill.message,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: subtitleFill.failedCount > 0
                                              ? const Color(0xFFBA1A1A)
                                              : AppDesignTokens.textSecondary,
                                        ),
                                      ),
                                    ),
                                    if (subtitleFill.failedCount > 0)
                                      TextButton(
                                        onPressed: () {
                                          unawaited(
                                            ref
                                                .read(
                                                  subtitleCompletionStatusProvider
                                                      .notifier,
                                                )
                                                .retryCourse(
                                                  selectedCourse.episodes.map(
                                                    (LibraryEpisodeItem e) =>
                                                        e.id,
                                                  ),
                                                ),
                                          );
                                        },
                                        child: const Text('重试'),
                                      ),
                                  ],
                                ),
                                if (subtitleFill.activeCount > 0) ...<Widget>[
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: LinearProgressIndicator(
                                      value: subtitleFill.progress,
                                      minHeight: 8,
                                      backgroundColor: AppDesignTokens.softGray,
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                        Color(0xFFFB7299),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    CourseOverviewCard(
                      course: selectedCourse,
                      activeEpisode:
                          activeEpisode ??
                          const LibraryEpisodeItem(
                            id: '',
                            numberStr: '--',
                            title: '暂无可播放剧集',
                            durationMinutes: 0,
                            hasChineseSubtitles: false,
                            hasEnglishSubtitles: false,
                            completed: false,
                            progressPercent: 0,
                            coverImage: '',
                          ),
                      onPlayTap: activeEpisode == null
                          ? () {}
                          : () => context.pushNamed(
                              SGRoute.player.name,
                              pathParameters: <String, String>{
                                'episodeId': activeEpisode.id,
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => unawaited(
                            _confirmReimportCourseSubtitles(selectedCourse),
                          ),
                          icon: const Icon(Icons.subtitles_outlined, size: 18),
                          label: const Text('重新导入字幕'),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 8,
                        children: <Widget>[
                          TextButton.icon(
                            onPressed: () =>
                                _showResourceDirectory(selectedCourse),
                            icon: const Icon(Icons.folder_open_outlined),
                            label: const Text('资源目录'),
                          ),
                          TextButton.icon(
                            onPressed: () => unawaited(
                              _confirmDeleteCollection(selectedCourse),
                            ),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: Color(0xFFC74A4A),
                            ),
                            label: Text(
                              _isCollectionCourse(selectedCourse)
                                  ? '删除合集'
                                  : '删除课程',
                              style: const TextStyle(color: Color(0xFFC74A4A)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: compact ? 20 : 28),
                    Container(
                      padding: EdgeInsets.all(compact ? 18 : 20),
                      decoration: BoxDecoration(
                        color: AppDesignTokens.appWhite,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: AppDesignTokens.toyCardShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      '全部剧集',
                                      style: TextStyle(
                                        fontSize: compact ? 24 : 28,
                                        fontWeight: FontWeight.w900,
                                        color: AppDesignTokens.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '挑一集继续练耳朵，保留当前排序和重排能力。',
                                      style: TextStyle(
                                        fontSize: compact ? 13 : 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppDesignTokens.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppDesignTokens.pinkLight,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${visibleEpisodes.length} 集',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: compact ? 14 : 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: <Widget>[
                              _EpisodeSortChip(
                                value: episodeSort,
                                onChanged: (String? value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setState(() {
                                    episodeSort = value;
                                  });
                                },
                              ),
                              OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    episodeSort = '手动排序';
                                    customEpisodeOrders.putIfAbsent(
                                      selectedCourse.id,
                                      () => selectedCourse.episodes
                                          .map((LibraryEpisodeItem item) => item.id)
                                          .toList(growable: false),
                                    );
                                  });
                                },
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: AppDesignTokens.borderGray,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  backgroundColor: AppDesignTokens.softWhite,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.swap_vert_rounded,
                                  size: 18,
                                  color: AppDesignTokens.primaryBlueDark,
                                ),
                                label: Text(
                                  '手动重排',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: compact ? 14 : 18),
                          if (visibleEpisodes.isEmpty)
                            const _EmptyEpisodesState()
                          else if (episodeSort == '手动排序')
                            ReorderableListView.builder(
                              shrinkWrap: true,
                              buildDefaultDragHandles: false,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: visibleEpisodes.length,
                              onReorderItem: _handleReorderEpisodes,
                              itemBuilder: (BuildContext context, int index) {
                                final LibraryEpisodeItem item =
                                    visibleEpisodes[index];
                                return Padding(
                                  key: ValueKey<String>(item.id),
                                  padding: EdgeInsets.only(
                                    bottom: compact ? 12 : 16,
                                  ),
                                  child: Consumer(
                                    builder:
                                        (BuildContext context, WidgetRef ref, _) {
                                      final SubtitleCompletionEpisodeUi?
                                      fill = ref
                                          .watch(
                                            subtitleCompletionStatusProvider,
                                          )
                                          .forEpisode(item.id);
                                      return EpisodeListItem(
                                    item: item,
                                    selected: item.id == selectedEpisodeId,
                                    fallbackCoverImage:
                                        selectedCourse.coverImage,
                                    englishFillLabel:
                                        fill?.englishChipProgressLabel,
                                    chineseFillLabel:
                                        fill?.chineseChipProgressLabel,
                                    englishFillFailed:
                                        fill != null &&
                                        fill.isFailed &&
                                        fill.needEnglish,
                                    chineseFillFailed:
                                        fill != null &&
                                        fill.isFailed &&
                                        fill.needChinese,
                                    subtitleFillActive:
                                        fill != null && fill.isActive,
                                    subtitleFillProgress: fill?.progressFraction,
                                    onTap: () {
                                      setState(() {
                                        selectedEpisodeId = item.id;
                                      });
                                      context.pushNamed(
                                        SGRoute.player.name,
                                        pathParameters: <String, String>{
                                          'episodeId': item.id,
                                        },
                                      );
                                    },
                                    onViewTranscript: () =>
                                        _openTranscriptReader(
                                          selectedCourse,
                                          item,
                                        ),
                                    onRerecognizeEnglish: () {
                                      unawaited(
                                        _confirmResetEpisodeSubtitles(
                                          selectedCourse,
                                          item,
                                          SubtitleResetSide.english,
                                        ),
                                      );
                                    },
                                    onRerecognizeChinese: () {
                                      unawaited(
                                        _confirmResetEpisodeSubtitles(
                                          selectedCourse,
                                          item,
                                          SubtitleResetSide.chinese,
                                        ),
                                      );
                                    },
                                    onMissingEnglishTap: () {
                                      unawaited(
                                        _requestMissingSubtitleFill(
                                          course: selectedCourse,
                                          episode: item,
                                          chip: SubtitleFillChip.english,
                                        ),
                                      );
                                    },
                                    onMissingChineseTap: () {
                                      unawaited(
                                        _requestMissingSubtitleFill(
                                          course: selectedCourse,
                                          episode: item,
                                          chip: SubtitleFillChip.chinese,
                                        ),
                                      );
                                    },
                                    trailing: ReorderableDragStartListener(
                                      index: index,
                                      child: Icon(
                                        Icons.drag_indicator_rounded,
                                        color: AppDesignTokens.textSecondary,
                                      ),
                                    ),
                                  );
                                    },
                                  ),
                                );
                              },
                            )
                          else
                            ...List<Widget>.generate(visibleEpisodes.length, (
                              int index,
                            ) {
                              final LibraryEpisodeItem item =
                                  visibleEpisodes[index];
                              return Padding(
                                padding: EdgeInsets.only(
                                  bottom: compact ? 12 : 16,
                                ),
                                child: Consumer(
                                  builder:
                                      (BuildContext context, WidgetRef ref, _) {
                                    final SubtitleCompletionEpisodeUi? fill = ref
                                        .watch(
                                          subtitleCompletionStatusProvider,
                                        )
                                        .forEpisode(item.id);
                                    return EpisodeListItem(
                                      item: item,
                                      selected: item.id == selectedEpisodeId,
                                      fallbackCoverImage:
                                          selectedCourse.coverImage,
                                      englishFillLabel:
                                          fill?.englishChipProgressLabel,
                                      chineseFillLabel:
                                          fill?.chineseChipProgressLabel,
                                      englishFillFailed:
                                          fill != null &&
                                          fill.isFailed &&
                                          fill.needEnglish,
                                      chineseFillFailed:
                                          fill != null &&
                                          fill.isFailed &&
                                          fill.needChinese,
                                      subtitleFillActive:
                                          fill != null && fill.isActive,
                                      subtitleFillProgress:
                                          fill?.progressFraction,
                                      onTap: () {
                                        setState(() {
                                          selectedEpisodeId = item.id;
                                        });
                                        context.pushNamed(
                                          SGRoute.player.name,
                                          pathParameters: <String, String>{
                                            'episodeId': item.id,
                                          },
                                        );
                                      },
                                      onViewTranscript: () =>
                                          _openTranscriptReader(
                                            selectedCourse,
                                            item,
                                          ),
                                      onRerecognizeEnglish: () {
                                        unawaited(
                                          _confirmResetEpisodeSubtitles(
                                            selectedCourse,
                                            item,
                                            SubtitleResetSide.english,
                                          ),
                                        );
                                      },
                                      onRerecognizeChinese: () {
                                        unawaited(
                                          _confirmResetEpisodeSubtitles(
                                            selectedCourse,
                                            item,
                                            SubtitleResetSide.chinese,
                                          ),
                                        );
                                      },
                                      onMissingEnglishTap: () {
                                        unawaited(
                                          _requestMissingSubtitleFill(
                                            course: selectedCourse,
                                            episode: item,
                                            chip: SubtitleFillChip.english,
                                          ),
                                        );
                                      },
                                      onMissingChineseTap: () {
                                        unawaited(
                                          _requestMissingSubtitleFill(
                                            course: selectedCourse,
                                            episode: item,
                                            chip: SubtitleFillChip.chinese,
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            )
          : LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double contentWidth = constraints.maxWidth - pagePadding * 2;
                final bool useCompactGrid =
                    viewMode == LibraryCourseViewMode.compact;
                final int gridColumns = useCompactGrid
                    ? (contentWidth >= 1100
                          ? 5
                          : contentWidth >= 820
                          ? 4
                          : contentWidth >= 560
                          ? 3
                          : 2)
                    : (contentWidth >= 900
                          ? 3
                          : contentWidth >= 560
                          ? 2
                          : 1);
                final double gridGap = useCompactGrid ? 14.0 : 20.0;
                final double gridItemWidth =
                    (contentWidth - gridGap * (gridColumns - 1)) /
                    gridColumns;
                final bool hasActiveQuery = query.trim().isNotEmpty;
                final int episodeHitCount = browsedCourses
                    .where((LibraryCourseMatch match) => match.matchedByEpisode)
                    .length;

                return Stack(
                  children: <Widget>[
                    ListView(
                  controller: listScrollController,
                  padding: EdgeInsets.all(pagePadding),
                  children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppDesignTokens.appWhite.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: AppDesignTokens.toyCardShadow,
                  ),
                  child: TextField(
                    controller: queryController,
                    onChanged: (String value) {
                      setState(() {
                        query = value;
                      });
                    },
                    onSubmitted: (_) => _applySearch(),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: '搜索课程、剧集、分类或来源...',
                      hintStyle: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppDesignTokens.textSecondary,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppDesignTokens.primaryBlueDark,
                      ),
                      filled: true,
                      fillColor: Colors.transparent,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      suffixIcon: queryController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _clearSearch,
                              icon: Icon(
                                Icons.close_rounded,
                                color: AppDesignTokens.textSecondary,
                              ),
                              tooltip: '清空搜索',
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    _CourseSortMenu(
                      value: courseSort,
                      onChanged: (LibraryCourseSort nextValue) {
                        setState(() {
                          courseSort = nextValue;
                        });
                        _persistBrowsePrefs();
                      },
                    ),
                    _CourseViewModeToggle(
                      value: viewMode,
                      onChanged: (LibraryCourseViewMode nextValue) {
                        setState(() {
                          viewMode = nextValue;
                        });
                        _persistBrowsePrefs();
                      },
                    ),
                    if (editMode)
                      _LibraryEditToolbar(
                        selectedCount: selectedCourseIds.length,
                        allSelected:
                            filteredCourses.isNotEmpty &&
                            filteredCourses.every(
                              (LibraryCourseData course) =>
                                  selectedCourseIds.contains(course.id),
                            ),
                        onSelectAll: filteredCourses.isEmpty
                            ? null
                            : () => _toggleSelectAll(filteredCourses),
                        onEdit: selectedCourseIds.isEmpty
                            ? null
                            : _showBatchEditDialog,
                        onDelete: selectedCourseIds.isEmpty
                            ? null
                            : _confirmDeleteSelectedCourses,
                        onDone: _exitEditMode,
                      )
                    else
                      FilledButton.tonal(
                        onPressed:
                            filteredCourses.isEmpty ? null : _enterEditMode,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppDesignTokens.appWhite.withValues(
                            alpha: 0.92,
                          ),
                          foregroundColor: AppDesignTokens.primaryBlueDark,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          '多选删除',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                // Keep import actions on their own full-width row so B站 is
                // never clipped by the phone's right edge. Same entry as 首页.
                CourseImportActionButtons(enabled: !editMode),
                if (hasActiveQuery) ...<Widget>[
                  const SizedBox(height: 14),
                  Text(
                    episodeHitCount > 0
                        ? '找到 ${filteredCourses.length} 门课程，其中 $episodeHitCount 门命中剧集'
                        : '找到 ${filteredCourses.length} 门课程',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (filteredCourses.isEmpty)
                  _EmptyLibraryState(query: query)
                else if (viewMode == LibraryCourseViewMode.grid ||
                    viewMode == LibraryCourseViewMode.compact)
                  Wrap(
                    spacing: gridGap,
                    runSpacing: gridGap,
                    children: browsedCourses
                        .map((LibraryCourseMatch match) {
                          return SizedBox(
                            width: gridItemWidth,
                            child: _LibraryCourseMatchShell(
                              match: match,
                              showEpisodeHint: hasActiveQuery,
                              child: LibraryCourseCard(
                                course: match.course,
                                selected: selectedCourseIds.contains(
                                  match.course.id,
                                ),
                                selectionMode: editMode,
                                onTap: () => _handleCourseTap(match.course),
                                onResourceDirectory: () =>
                                    _showResourceDirectory(match.course),
                                onContextMenu: (Offset position) =>
                                    _showCourseContextMenu(
                                      course: match.course,
                                      globalPosition: position,
                                    ),
                              ),
                            ),
                          );
                        })
                        .toList(growable: false),
                  )
                else if (viewMode == LibraryCourseViewMode.rows)
                  Column(
                    children: <Widget>[
                      for (int i = 0; i < browsedCourses.length; i++) ...<Widget>[
                        if (i > 0) const SizedBox(height: 14),
                        _LibraryCourseMatchShell(
                          match: browsedCourses[i],
                          showEpisodeHint: hasActiveQuery,
                          child: LibraryCourseListItem(
                            course: browsedCourses[i].course,
                            selected: selectedCourseIds.contains(
                              browsedCourses[i].course.id,
                            ),
                            selectionMode: editMode,
                            onTap: () =>
                                _handleCourseTap(browsedCourses[i].course),
                            onResourceDirectory: () => _showResourceDirectory(
                              browsedCourses[i].course,
                            ),
                            onContextMenu: (Offset position) =>
                                _showCourseContextMenu(
                                  course: browsedCourses[i].course,
                                  globalPosition: position,
                                ),
                          ),
                        ),
                      ],
                    ],
                  )
                else
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Color(0xFF16181E),
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: <Widget>[
                          for (int i = 0; i < browsedCourses.length; i++)
                            _LibraryCourseMatchShell(
                              match: browsedCourses[i],
                              showEpisodeHint: hasActiveQuery,
                              darkSurface: true,
                              child: LibraryFeedCard(
                                course: browsedCourses[i].course,
                                index: i,
                                onTap: () => _handleCourseTap(
                                  browsedCourses[i].course,
                                ),
                                onContextMenu: (Offset position) =>
                                    _showCourseContextMenu(
                                      course: browsedCourses[i].course,
                                      globalPosition: position,
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 88),
                ],
              ),
                    if (showScrollToTop)
                      Positioned(
                        right: pagePadding,
                        bottom: canContinueLearning
                            ? (compact ? 96 : 100)
                            : (compact ? 24 : 28),
                        child: FloatingActionButton.small(
                          onPressed: () {
                            listScrollController.animateTo(
                              0,
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutCubic,
                            );
                          },
                          backgroundColor: AppDesignTokens.primaryBlue,
                          foregroundColor: AppDesignTokens.onAccent,
                          elevation: 6,
                          child: const Icon(Icons.keyboard_arrow_up_rounded),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  Future<void> _showResourceDirectory(LibraryCourseData course) async {
    final bool? updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          CourseResourceDirectoryDialog(courseId: course.id),
    );
    if ((updated ?? false) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('资源目录已更新，学习进度和生词已保留。')),
      );
    }
  }

  Future<void> _confirmReimportCourseSubtitles(LibraryCourseData course) async {
    final bool ok =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('重新导入本课程字幕？'),
              content: const Text(
                '将清除本课程语音识别生成的字幕，重新挂上 B 站官方软字幕；'
                '缺英文/中文的分集再在后台补全。视频文件不会删除。',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('开始重新导入'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!ok || !mounted) {
      return;
    }
    try {
      final int n = await reimportCourseSubtitles(
        catalog: ref.read(libraryCatalogProvider.notifier),
        course: course,
        bilibiliCookieHeader: ref
            .read(learningSettingsProvider)
            .resolvedBilibiliCookieHeader,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已重新导入 $n 集字幕，缺侧正在后台补全')),
      );
      unawaited(ref.read(subtitleCompletionStatusProvider.notifier).refresh());
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重新导入字幕失败：$e')),
      );
    }
  }

  Future<void> _confirmResetEpisodeSubtitles(
    LibraryCourseData course,
    LibraryEpisodeItem episode,
    SubtitleResetSide side,
  ) async {
    if (!mounted) {
      return;
    }
    final bool hasManual = await episodeHasManualSubtitleEdits(
      episodeId: episode.id,
    );
    if (!mounted) {
      return;
    }
    if (hasManual) {
      final bool ok = await confirmManualSubtitleDestructiveAction(
        context,
        action: ManualSubtitleDestructiveAction.delete,
      );
      if (!ok || !mounted) {
        return;
      }
    }
    final LibraryCatalogNotifier catalog = ref.read(
      libraryCatalogProvider.notifier,
    );
    final String cookie = ref
        .read(learningSettingsProvider)
        .resolvedBilibiliCookieHeader;
    try {
      final String message;
      switch (side) {
        case SubtitleResetSide.chinese:
          if (!episode.hasEnglishSubtitles) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('没有英文字幕，无法重译中文。请先重新识别英文字幕'),
              ),
            );
            return;
          }
          await resetEpisodeChineseSubtitles(
            catalog: catalog,
            course: course,
            episode: episode,
            bilibiliCookieHeader: cookie,
          );
          ref.read(subtitleCompletionStatusProvider.notifier).reportProgress(
            episode.id,
            '正在用英文重译中文字幕…',
            needEnglish: false,
            needChinese: true,
            status: SubtitleCompletionStatus.running,
          );
          message = '第 ${episode.numberStr} 集：正在用英文重译中文';
          break;
        case SubtitleResetSide.english:
          await resetEpisodeEnglishSubtitles(
            catalog: catalog,
            course: course,
            episode: episode,
            bilibiliCookieHeader: cookie,
          );
          ref.read(subtitleCompletionStatusProvider.notifier).reportProgress(
            episode.id,
            '正在用语音重新识别英文字幕…',
            needEnglish: true,
            needChinese: false,
            status: SubtitleCompletionStatus.running,
          );
          message = '第 ${episode.numberStr} 集：正在语音 ASR 英文字幕';
          break;
        case SubtitleResetSide.both:
          await resetEpisodeSubtitles(
            catalog: catalog,
            course: course,
            episode: episode,
            bilibiliCookieHeader: cookie,
            requeueFill: true,
          );
          ref.read(subtitleCompletionStatusProvider.notifier).reportProgress(
            episode.id,
            '正在重新识别：先 ASR 英文，再翻译中文…',
            needEnglish: true,
            needChinese: true,
            status: SubtitleCompletionStatus.running,
          );
          message = '第 ${episode.numberStr} 集：ASR 英文 → 翻译中文';
          break;
      }
      unawaited(ref.read(subtitleCompletionStatusProvider.notifier).refresh());
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重新识别失败：$e')),
      );
    }
  }

  void _openCourse(LibraryCourseData course) {
    setState(() {
      selectedCourse = course;
      selectedEpisodeId = course.episodes
              .where((LibraryEpisodeItem item) =>
                  !item.videoMissing && isUsableLocalVideoPath(item.videoAsset))
              .firstOrNull?.id ??
          course.episodes.firstOrNull?.id ??
          '';
      showDetail = true;
    });
    _maybeBackfillBilibiliEpisodeCovers(course);
  }

  void _maybeBackfillBilibiliEpisodeCovers(LibraryCourseData course) {
    final bool isBili =
        course.category == 'bilibili' ||
        course.sourceLabel.toLowerCase().contains('bilibili') ||
        course.id.startsWith('bilibili-');
    if (!isBili || course.episodes.isEmpty) {
      return;
    }
    // Always refresh episode posters for bilibili — even a course-level cover
    // should be stamped onto empty episode rows immediately.
    final String cookie = ref
        .read(learningSettingsProvider)
        .resolvedBilibiliCookieHeader;
    final ProviderContainer container = ProviderScope.containerOf(context);
    unawaited(
      backfillBilibiliEpisodeCovers(
        catalog: container.read(libraryCatalogProvider.notifier),
        readCourses: () => container.read(libraryCatalogProvider),
        courseId: course.id,
        service: BilibiliImportService.withCookie(cookie),
      ),
    );
  }

  int _pendingCollectionEpisodes(LibraryCourseData course) {
    final bool isBili = course.category == 'bilibili' ||
        course.sourceLabel.toLowerCase().contains('bilibili') ||
        course.id.startsWith('bilibili-');
    if (!isBili || course.episodes.length <= 1) return 0;
    return course.episodes.where((LibraryEpisodeItem item) =>
        item.videoMissing || !isUsableLocalVideoPath(item.videoAsset)).length;
  }

  Future<void> _confirmCollectionDownload(LibraryCourseData course) async {
    final int count = _pendingCollectionEpisodes(course);
    if (count == 0 || isBilibiliCollectionDownloadInFlight(course.id)) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('下载合集剩余各集？'),
        content: Text('还有 $count 集未下载。继续后会在后台下载到本地。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续试看'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('全部下载'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final String cookie = ref
        .read(learningSettingsProvider)
        .resolvedBilibiliCookieHeader;
    final ProviderContainer container = ProviderScope.containerOf(context);
    final BilibiliCollectionDownloadProgressNotifier progressNotifier =
        container.read(bilibiliCollectionDownloadProgressProvider.notifier);
    // Progress lives on the course banner — avoid SnackBar spam on every open.
    unawaited(
      downloadRemainingBilibiliEpisodes(
        catalog: container.read(libraryCatalogProvider.notifier),
        readCourses: () => container.read(libraryCatalogProvider),
        courseId: course.id,
        service: BilibiliImportService.withCookie(cookie),
        progressNotifier: progressNotifier,
      ),
    );
  }

  Future<void> _confirmNetdiskDownload(LibraryCourseData course) async {
    final int count = pendingNetdiskEpisodes(course);
    if (count == 0 || isNetdiskDownloadInFlight(course.id)) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('下载到本机？'),
        content: const Text(
          '在线播放若因网盘非会员限速卡顿，可下载到手机后再播。'
          '同目录的字幕文件会一并关联。下载速度仍受网盘账号限制。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续在线看'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('下载到本机'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
    final ProviderContainer container = ProviderScope.containerOf(context);
    final NetdiskDownloadProgressNotifier progressNotifier =
        container.read(netdiskDownloadProgressProvider.notifier);
    unawaited(
      downloadNetdiskCourseToLocal(
        api: container.read(acquireApiClientProvider),
        catalog: container.read(libraryCatalogProvider.notifier),
        readCourses: () => container.read(libraryCatalogProvider),
        courseId: course.id,
        progressNotifier: progressNotifier,
      ).catchError((Object error) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '网盘下载失败：${'$error'.replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }),
    );
  }

  void _handleCourseTap(LibraryCourseData course) {
    if (!editMode) {
      _openCourse(course);
      return;
    }
    setState(() {
      if (selectedCourseIds.contains(course.id)) {
        selectedCourseIds.remove(course.id);
      } else {
        selectedCourseIds.add(course.id);
      }
    });
  }

  Future<void> _requestMissingSubtitleFill({
    required LibraryCourseData course,
    required LibraryEpisodeItem episode,
    required SubtitleFillChip chip,
  }) async {
    if (episode.videoMissing || !isUsableLocalVideoPath(episode.videoAsset)) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先下载本集视频，再补字幕')),
      );
      return;
    }
    final bool wantEnglish = chip == SubtitleFillChip.english;
    final bool wantChinese = chip == SubtitleFillChip.chinese;
    // Optimistic chip + bar update so progress shows on the list immediately.
    ref.read(subtitleCompletionStatusProvider.notifier).reportProgress(
      episode.id,
      wantEnglish ? '排队补英文字幕…' : '排队补中文字幕…',
      needEnglish: wantEnglish || !episode.hasEnglishSubtitles,
      needChinese: wantChinese || !episode.hasChineseSubtitles,
      status: SubtitleCompletionStatus.pending,
    );
    // Failed jobs may already be at maxAttempts — force requeue before enqueue.
    if (wantChinese || wantEnglish) {
      await SubtitleCompletionQueue.shared.requeueFailedJobs(
        onlyConfigErrors: false,
      );
    }
    await enqueueSubtitleCompletionForEpisode(
      episodeId: episode.id,
      videoPath: episode.videoAsset,
      zhSubtitlePath: episode.cnSubtitleAsset,
      enSubtitlePath: episode.enSubtitleAsset,
      sourceUrl: episode.sourceUrl,
      title: episode.title,
      description: course.description,
      course: course,
      episode: episode,
      chip: chip,
      bilibiliCookieHeader: ref
          .read(learningSettingsProvider)
          .resolvedBilibiliCookieHeader,
    );
    await SubtitleCompletionQueue.shared.prioritizeEpisode(episode.id);
    SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
    await ref.read(subtitleCompletionStatusProvider.notifier).refresh();
  }

  void _enterEditMode() {
    setState(() {
      editMode = true;
      selectedCourseIds.clear();
    });
  }

  void _exitEditMode() {
    setState(() {
      editMode = false;
      selectedCourseIds.clear();
    });
  }

  Future<void> _showBatchEditDialog() async {
    final List<LibraryCourseData> selectedCourses = ref
        .read(libraryCatalogProvider)
        .where((LibraryCourseData course) => selectedCourseIds.contains(course.id))
        .toList(growable: false);
    if (selectedCourses.isEmpty) {
      return;
    }
    final bool single = selectedCourses.length == 1;
    final TextEditingController titleController = TextEditingController(
      text: single ? selectedCourses.first.title : '',
    );
    final String initialSource = selectedCourses
            .map((LibraryCourseData course) => course.sourceLabel)
            .toSet()
            .length ==
        1
        ? selectedCourses.first.sourceLabel
        : '';
    final TextEditingController sourceController = TextEditingController(
      text: initialSource,
    );
    String selectedCoverImage = single ? selectedCourses.first.coverImage : '';
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              backgroundColor: AppDesignTokens.appWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              title: Text(single ? '编辑课程' : '批量编辑'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: '影视名',
                      hintText: single ? null : '留空则不修改',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sourceController,
                    decoration: InputDecoration(
                      labelText: '来源',
                      hintText: initialSource.isEmpty ? '留空则不修改' : null,
                    ),
                  ),
                  if (single) ...<Widget>[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: () async {
                          final String? coverImage = await _pickCoverImage();
                          if (coverImage == null || coverImage.isEmpty) {
                            return;
                          }
                          setDialogState(() {
                            selectedCoverImage = coverImage;
                          });
                        },
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('上传封面'),
                      ),
                    ),
                    if (selectedCoverImage.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          selectedCoverImage.split(RegExp(r'[\\/]')).last,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: AppDesignTokens.textSecondary,
                  ),
                  child: const Text(
                    '取消',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppDesignTokens.brandGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Text(
                    '保存',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (saved != true || !mounted) {
      return;
    }
    await ref.read(libraryCatalogProvider.notifier).updateCoursesMetadata(
      courseIds: selectedCourseIds,
      title: titleController.text,
      sourceLabel: sourceController.text,
      coverImage: single ? selectedCoverImage : null,
    );
    if (!mounted) {
      return;
    }
    _exitEditMode();
  }

  Future<String?> _pickCoverImage() async {
    if (widget.pickCoverImage != null) {
      return widget.pickCoverImage!();
    }
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'images',
          extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
        ),
      ],
      confirmButtonText: '选择封面',
    );
    return file?.path;
  }

  bool _isCollectionCourse(LibraryCourseData course) {
    if (course.id.startsWith('bilibili-season-')) {
      return true;
    }
    if (course.episodes.length > 1) {
      return true;
    }
    final String label = course.sourceLabel.toLowerCase();
    return label.contains('合集') || label.contains('season');
  }

  /// Courses removed together when deleting a "合集".
  /// Multi-episode / B站合集 = itself; otherwise peers sharing the same video dir.
  List<LibraryCourseData> _collectionPeers(
    LibraryCourseData course, {
    List<LibraryCourseData>? catalog,
  }) {
    final List<LibraryCourseData> all =
        catalog ?? ref.read(libraryCatalogProvider);
    if (_isCollectionCourse(course)) {
      return <LibraryCourseData>[course];
    }
    final String? dir = course.videoDirectories
        .map((String path) => path.trim())
        .where((String path) => path.isNotEmpty)
        .firstOrNull;
    if (dir == null) {
      return <LibraryCourseData>[course];
    }
    final List<LibraryCourseData> peers = all
        .where(
          (LibraryCourseData item) => item.videoDirectories.any(
            (String path) => path.trim() == dir,
          ),
        )
        .toList(growable: false);
    return peers.isEmpty ? <LibraryCourseData>[course] : peers;
  }

  void _toggleSelectAll(List<LibraryCourseData> courses) {
    setState(() {
      final bool allSelected = courses.isNotEmpty &&
          courses.every(
            (LibraryCourseData course) => selectedCourseIds.contains(course.id),
          );
      if (allSelected) {
        selectedCourseIds.clear();
      } else {
        selectedCourseIds
          ..clear()
          ..addAll(courses.map((LibraryCourseData course) => course.id));
      }
    });
  }

  void _enterEditModeWith(LibraryCourseData course) {
    setState(() {
      editMode = true;
      selectedCourseIds
        ..clear()
        ..add(course.id);
    });
  }

  Future<void> _showCourseContextMenu({
    required LibraryCourseData course,
    required Offset globalPosition,
  }) async {
    final List<LibraryCourseData> peers = _collectionPeers(course);
    final bool collection = _isCollectionCourse(course) || peers.length > 1;
    final String? action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'multi',
          child: Row(
            children: <Widget>[
              Icon(Icons.checklist_rounded, size: 20),
              SizedBox(width: 10),
              Text('多选删除'),
            ],
          ),
        ),
        if (collection)
          PopupMenuItem<String>(
            value: 'delete_collection',
            child: Row(
              children: <Widget>[
                const Icon(Icons.folder_off_outlined, size: 20),
                const SizedBox(width: 10),
                Text(
                  _isCollectionCourse(course)
                      ? '删除整个合集（${course.episodes.length} 集）'
                      : '删除同目录合集（${peers.length} 门）',
                ),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: <Widget>[
              const Icon(Icons.delete_outline_rounded, size: 20),
              const SizedBox(width: 10),
              Text(collection ? '仅删除本课程' : '删除课程'),
            ],
          ),
        ),
      ],
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case 'multi':
        _enterEditModeWith(course);
      case 'delete_collection':
        await _confirmDeleteCollection(course);
      case 'delete':
        await _confirmDeleteCourses(
          courseIds: <String>{course.id},
          title: '删除课程',
          message: '确定删除「${course.title}」吗？删除后可重新导入。',
        );
    }
  }

  Future<void> _confirmDeleteCollection(LibraryCourseData course) async {
    final List<LibraryCourseData> peers = _collectionPeers(course);
    final bool multiEpisode = _isCollectionCourse(course);
    final Set<String> ids =
        peers.map((LibraryCourseData item) => item.id).toSet();
    final String title = multiEpisode ? '删除整个合集' : '按合集删除';
    final String message = multiEpisode
        ? '将删除合集「${course.title}」及全部 ${course.episodes.length} 集，删除后可重新导入。'
        : peers.length > 1
        ? '将删除同目录下的 ${peers.length} 门课程（含「${course.title}」），删除后可重新导入。'
        : '确定删除「${course.title}」吗？删除后可重新导入。';
    await _confirmDeleteCourses(
      courseIds: ids,
      title: title,
      message: message,
      exitEditMode: true,
    );
    if (!mounted) {
      return;
    }
    if (showDetail && ids.contains(selectedCourse.id)) {
      setState(() {
        showDetail = false;
        selectedCourse = emptyLibraryCourse;
        selectedEpisodeId = '';
      });
    }
  }

  Future<void> _confirmDeleteSelectedCourses() async {
    await _confirmDeleteCourses(
      courseIds: Set<String>.from(selectedCourseIds),
      title: '多选删除',
      message: '将删除已选的 ${selectedCourseIds.length} 门课程。',
      exitEditMode: true,
    );
  }

  Future<void> _confirmDeleteCourses({
    required Set<String> courseIds,
    required String title,
    required String message,
    bool exitEditMode = false,
  }) async {
    if (courseIds.isEmpty) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppDesignTokens.appWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppDesignTokens.textSecondary,
              ),
              child: const Text(
                '取消',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppDesignTokens.brandGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Text(
                '确认删除',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await ref.read(libraryCatalogProvider.notifier).deleteCourses(courseIds);
    if (!mounted) {
      return;
    }
    if (exitEditMode) {
      _exitEditMode();
    }
  }

  List<LibraryEpisodeItem> _visibleEpisodes(LibraryCourseData course) {
    final List<LibraryEpisodeItem> episodes = List<LibraryEpisodeItem>.from(
      course.episodes,
    );
    switch (episodeSort) {
      case '最近学习':
        episodes.sort((LibraryEpisodeItem a, LibraryEpisodeItem b) {
          return _recentScore(b).compareTo(_recentScore(a));
        });
      case '学习进度':
        episodes.sort((LibraryEpisodeItem a, LibraryEpisodeItem b) {
          return b.progressPercent.compareTo(a.progressPercent);
        });
      case '手动排序':
        final List<String> order =
            customEpisodeOrders[course.id] ??
            course.episodes
                .map((LibraryEpisodeItem item) => item.id)
                .toList(growable: false);
        episodes.sort((LibraryEpisodeItem a, LibraryEpisodeItem b) {
          return order.indexOf(a.id).compareTo(order.indexOf(b.id));
        });
      default:
        episodes.sort((LibraryEpisodeItem a, LibraryEpisodeItem b) {
          return int.parse(a.numberStr).compareTo(int.parse(b.numberStr));
        });
    }
    return episodes;
  }

  int _recentScore(LibraryEpisodeItem item) {
    if (item.progressPercent > 0 && !item.completed) {
      return 300 + item.progressPercent;
    }
    if (item.completed) {
      return 200 + item.progressPercent;
    }
    return item.progressPercent;
  }

  void _handleReorderEpisodes(int oldIndex, int newIndex) {
    final int targetIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final List<String> order = List<String>.from(
      customEpisodeOrders[selectedCourse.id] ??
          selectedCourse.episodes
              .map((LibraryEpisodeItem item) => item.id)
              .toList(growable: false),
    );
    final String item = order.removeAt(oldIndex);
    order.insert(targetIndex, item);
    setState(() {
      customEpisodeOrders[selectedCourse.id] = order;
      episodeSort = '手动排序';
    });
  }

  void _applySearch() {
    setState(() {
      query = queryController.text;
    });
  }

  void _clearSearch() {
    queryController.clear();
    setState(() {
      query = '';
    });
  }
}

class _EmptyLibraryState extends StatelessWidget {
  const _EmptyLibraryState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final bool hasQuery = query.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppDesignTokens.borderGray),
        boxShadow: AppDesignTokens.toyCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            hasQuery ? '没有找到匹配课程' : '还没有导入任何课程',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            hasQuery
                ? '试试课程名、剧集标题、分类或来源关键词；也可以直接导入新视频。'
                : '先导入你自己的视频和字幕资源，再开始精听。',
            style: TextStyle(
              fontSize: 14,
              height: 1.55,
              color: AppDesignTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryCourseMatchShell extends StatelessWidget {
  const _LibraryCourseMatchShell({
    required this.match,
    required this.child,
    this.showEpisodeHint = false,
    this.darkSurface = false,
  });

  final LibraryCourseMatch match;
  final Widget child;
  final bool showEpisodeHint;
  final bool darkSurface;

  @override
  Widget build(BuildContext context) {
    if (!showEpisodeHint || !match.matchedByEpisode) {
      return child;
    }
    final String hint =
        '剧集命中：${match.matchedEpisodeTitles.join(' · ')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        child,
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(
            hint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: darkSurface
                  ? Colors.white70
                  : AppDesignTokens.primaryBlueDark,
            ),
          ),
        ),
      ],
    );
  }
}

class _CourseSortMenu extends StatelessWidget {
  const _CourseSortMenu({
    required this.value,
    required this.onChanged,
  });

  final LibraryCourseSort value;
  final ValueChanged<LibraryCourseSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<LibraryCourseSort>(
      tooltip: '排序方式',
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (BuildContext context) {
        return LibraryCourseSort.values
            .map(
              (LibraryCourseSort sort) => PopupMenuItem<LibraryCourseSort>(
                value: sort,
                child: Text(sort.label),
              ),
            )
            .toList(growable: false);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppDesignTokens.appWhite.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(999),
          boxShadow: AppDesignTokens.toyCardShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.sort_rounded,
              size: 18,
              color: AppDesignTokens.primaryBlueDark,
            ),
            const SizedBox(width: 8),
            Text(
              value.label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppDesignTokens.primaryBlueDark,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: AppDesignTokens.primaryBlueDark,
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseViewModeToggle extends StatelessWidget {
  const _CourseViewModeToggle({
    required this.value,
    required this.onChanged,
  });

  final LibraryCourseViewMode value;
  final ValueChanged<LibraryCourseViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        boxShadow: AppDesignTokens.toyCardShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _CourseViewModeButton(
            icon: Icons.grid_view_rounded,
            tooltip: LibraryCourseViewMode.grid.label,
            selected: value == LibraryCourseViewMode.grid,
            onTap: () => onChanged(LibraryCourseViewMode.grid),
          ),
          const SizedBox(width: 6),
          _CourseViewModeButton(
            icon: Icons.apps_rounded,
            tooltip: LibraryCourseViewMode.compact.label,
            selected: value == LibraryCourseViewMode.compact,
            onTap: () => onChanged(LibraryCourseViewMode.compact),
          ),
          const SizedBox(width: 6),
          _CourseViewModeButton(
            icon: Icons.view_list_rounded,
            tooltip: LibraryCourseViewMode.rows.label,
            selected: value == LibraryCourseViewMode.rows,
            onTap: () => onChanged(LibraryCourseViewMode.rows),
          ),
          const SizedBox(width: 6),
          _CourseViewModeButton(
            icon: Icons.view_agenda_rounded,
            tooltip: LibraryCourseViewMode.feed.label,
            selected: value == LibraryCourseViewMode.feed,
            onTap: () => onChanged(LibraryCourseViewMode.feed),
          ),
        ],
      ),
    );
  }
}

class _CourseViewModeButton extends StatelessWidget {
  const _CourseViewModeButton({
    required this.icon,
    required this.selected,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Widget button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: selected ? AppDesignTokens.brandGreen : AppDesignTokens.skyLight,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected ? AppDesignTokens.toyButtonShadow : null,
        ),
        child: Icon(
          icon,
          size: 18,
          color: selected
              ? AppDesignTokens.onAccent
              : AppDesignTokens.primaryBlueDark,
        ),
      ),
    );
    final String? tip = tooltip;
    if (tip == null || tip.isEmpty) {
      return button;
    }
    return Tooltip(message: tip, child: button);
  }
}

class _LibraryEditToolbar extends StatelessWidget {
  const _LibraryEditToolbar({
    required this.selectedCount,
    required this.allSelected,
    required this.onSelectAll,
    required this.onEdit,
    required this.onDelete,
    required this.onDone,
  });

  final int selectedCount;
  final bool allSelected;
  final VoidCallback? onSelectAll;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        boxShadow: AppDesignTokens.toyCardShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppDesignTokens.skyLight,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              selectedCount == 0 ? '选择课程' : '已选 $selectedCount 项',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppDesignTokens.primaryBlueDark,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _LibraryEditActionButton(
            label: allSelected ? '取消全选' : '全选',
            icon: allSelected
                ? Icons.deselect_rounded
                : Icons.select_all_rounded,
            color: AppDesignTokens.primaryBlueDark,
            background: AppDesignTokens.skyLight,
            onTap: onSelectAll,
          ),
          const SizedBox(width: 8),
          _LibraryEditActionButton(
            label: '编辑',
            icon: Icons.edit_rounded,
            color: AppDesignTokens.primaryBlueDark,
            background: AppDesignTokens.skyLight,
            onTap: onEdit,
          ),
          const SizedBox(width: 8),
          _LibraryEditActionButton(
            label: '删除',
            icon: Icons.delete_outline_rounded,
            color: const Color(0xFFC74A4A),
            background: const Color(0xFFFFECEC),
            onTap: onDelete,
          ),
          const SizedBox(width: 8),
          _LibraryEditActionButton(
            label: '完成',
            icon: Icons.check_rounded,
            color: AppDesignTokens.appWhite,
            background: AppDesignTokens.brandGreen,
            onTap: onDone,
          ),
        ],
      ),
    );
  }
}

class _LibraryEditActionButton extends StatelessWidget {
  const _LibraryEditActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.background,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            boxShadow: background == AppDesignTokens.brandGreen
                ? AppDesignTokens.toyButtonShadow
                : null,
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryDetailTopStatus extends StatelessWidget {
  const _LibraryDetailTopStatus({
    required this.courseMeta,
    this.episodeName,
  });

  final String courseMeta;
  final String? episodeName;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
        Text(
          courseMeta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F7A43),
          ),
        ),
          if (episodeName != null && episodeName!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              episodeName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF191C1E),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyEpisodesState extends StatelessWidget {
  const _EmptyEpisodesState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: AppDesignTokens.softWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppDesignTokens.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '这个课程还没有可播放剧集',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '请先完成资源导入，或者返回影视库选择已有剧集。',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppDesignTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeSortChip extends StatelessWidget {
  const _EpisodeSortChip({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    const List<String> options = <String>['自然排序', '最近学习', '学习进度', '手动排序'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE4DA)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          borderRadius: BorderRadius.circular(16),
          onChanged: onChanged,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF53625A),
          ),
          items: options
              .map((String item) {
                return DropdownMenuItem<String>(value: item, child: Text(item));
              })
              .toList(growable: false),
        ),
      ),
    );
  }
}
