import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../router/app_router.dart';
import '../../guide/presentation/guide_screen.dart';
import '../../home/presentation/learning_dashboard_provider.dart';
import '../../import_course/data/bilibili_episode_prepare.dart';
import '../../import_course/data/bilibili_import_service.dart';
import '../../import_course/data/bilibili_multipage.dart';
import '../../import_course/domain/bilibili_import.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../phrases/presentation/phrase_book_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../subtitle_completion/subtitle_completion_enqueue.dart';
import '../../subtitle_completion/subtitle_completion_scheduler.dart';
import '../../shared/data/word_lookup_service.dart';
import '../../shared/data/word_pronunciation_service.dart';
import '../../shared/presentation/app_loading_overlay.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../words/data/offline_word_dictionary.dart';
import '../../words/presentation/word_book_provider.dart';
import '../domain/pronunciation_assessment.dart';
import 'asr_subtitle_cache.dart';
import 'asr_subtitle_job.dart';
import 'asr_subtitle_service.dart';
import 'bilingual_subtitle_helpers.dart';
import 'bilingual_subtitle_pipeline.dart';
import 'embedded_subtitle_reference.dart';
import 'full_transcript_reader.dart';
import 'learning_resume_provider.dart';
import 'player_course_lookup.dart';
import 'player_fullscreen_video_screen.dart';
import 'player_graphics_cache.dart';
import 'player_media_source.dart';
import 'player_mock_state.dart';
import 'player_native_subtitles.dart';
import 'player_subtitle_loader.dart';
import 'player_system_media_controls.dart';
import 'player_video_init.dart';
import 'pronunciation_target_selection.dart';
import 'subtitle_display_mode.dart';
import 'subtitle_file_persist.dart';
import 'subtitle_reference_review.dart';
import 'subtitle_sentence_merge.dart';
import 'subtitle_word_alignment.dart';
import 'transcript_reader_session.dart';
import 'widgets/ai_grammar_analysis_sheet.dart';
import 'widgets/ai_subtitle_generation_progress_dialog.dart';
import 'widgets/player_episode_strip.dart';
import 'widgets/player_subtitle_list.dart';
import 'widgets/player_top_bar.dart';
import 'widgets/player_transcript_panel.dart';
import 'widgets/player_video_panel.dart';
import 'widgets/pronunciation_assessment_dialog.dart';
import 'widgets/subtitle_vocabulary_highlight.dart';

class PadLandscapePlayerScreen extends ConsumerStatefulWidget {
  const PadLandscapePlayerScreen({
    required this.episodeId,
    this.initialStartTime,
    this.autoPlay = false,
    this.autoOpenFullscreen = false,
    super.key,
  });

  final String episodeId;
  final String? initialStartTime;
  final bool autoPlay;
  final bool autoOpenFullscreen;

  @override
  ConsumerState<PadLandscapePlayerScreen> createState() =>
      PadLandscapePlayerScreenState();
}

class PadLandscapePlayerScreenState
    extends ConsumerState<PadLandscapePlayerScreen> {
  late final PlayerMockState state;
  final TranscriptReaderSession _transcriptReaderSession =
      TranscriptReaderSession();
  Player? _videoPlayer;
  VideoController? _videoController;
  Future<void>? _videoDisposal;
  late final Future<void> Function() _releaseGraphicsCache;
  StreamSubscription<Duration>? _videoPositionSubscription;
  StreamSubscription<Duration>? _videoDurationSubscription;
  StreamSubscription<bool>? _videoPlayingSubscription;
  StreamSubscription<bool>? _videoCompletedSubscription;
  StreamSubscription<int?>? _videoWidthSubscription;
  StreamSubscription<int?>? _videoHeightSubscription;
  StreamSubscription<Tracks>? _videoTracksSubscription;
  bool _isMuted = false;
  double _volumeLevel = 1;
  bool _videoReady = false;
  bool _videoLoading = false;
  bool _isBootstrapping = true;
  bool _videoIsPlaying = false;
  Duration _videoDuration = Duration.zero;
  Duration _videoPosition = Duration.zero;
  int? _scrubTargetMs;
  DateTime? _scrubArmedAt;
  String? _videoErrorText;
  String? _videoAsset;
  double _videoAspectRatio = 16 / 9;
  Duration _lastTrackedVideoPosition = Duration.zero;
  bool _didAutoOpenFullscreen = false;
  bool _isFullscreenOpen = false;
  bool _pronunciationDialogActive = false;
  bool _generatingAiSubtitles = false;
  AsrSubtitleCancellationToken? _aiSubtitleCancellationToken;
  double? _aiSubtitleProgressValue;
  String? _aiSubtitleProgressText;
  String? _aiSubtitlePreviewText;
  String? _aiSubtitleErrorText;
  bool _usingAiSubtitles = false;
  bool _hasOfficialEnglish = false;
  final Map<int, String> _manualEnglishByStartMs = <int, String>{};
  final Map<int, String> _manualChineseByStartMs = <int, String>{};
  final Map<int, String> _lineNotesByStartMs = <int, String>{};
  BilingualSubtitlePipeline? _bilingualPipeline;
  BilingualPipelinePhase _bilingualPhase = BilingualPipelinePhase.idle;
  String? _bilingualPipelineLabel;
  bool _bilingualShowAiComplete = false;
  bool _englishFillInFlight = false;
  AsrSubtitleCancellationToken? _englishFillCancellationToken;
  Timer? _ocrPersistDebounce;
  List<PlayerSubtitleLine>? _pendingOcrPersistLines;
  List<SubtitleTrack> _embeddedSubtitleTracks = const <SubtitleTrack>[];
  String? _selectedEmbeddedSubtitleId;
  List<PlayerSubtitleLine> _referenceSubtitleLines =
      const <PlayerSubtitleLine>[];
  Map<int, List<PlayerSubtitleLine>> _asrFragmentsBySentenceStartMs =
      const <int, List<PlayerSubtitleLine>>{};
  bool _usingAsrSentences = false;

  @override
  void initState() {
    super.initState();
    _releaseGraphicsCache = PlayerGraphicsCache.acquire();
    state = PlayerMockState(initialStartTime: widget.initialStartTime);
    _syncSettingsToState(ref.read(learningSettingsProvider));
    ref.listenManual<String>(
      learningSettingsProvider.select(
        (LearningSettingsState settings) => settings.subtitleLetterCase,
      ),
      (String? previous, String next) => _syncTranscriptReader(),
    );
    PlayerSystemMediaControls.bind(
      onPlay: _handleSystemPlay,
      onPause: _handleSystemPause,
      onToggle: _handleTogglePlaying,
      onNext: _handleNextLine,
      onPrevious: _handlePreviousLine,
    );
    SubtitleCompletionScheduler.instance.setPlayerActive(false);
    _loadEpisodeResources();
  }

  void _syncSettingsToState(LearningSettingsState settings) {
    state
      ..selectSpeed(settings.playbackSpeed)
      ..subtitleDelayMs = settings.subtitleDelayMs
      ..setSubtitleMode(settings.subtitleMode);
  }

  @override
  void dispose() {
    SubtitleCompletionScheduler.instance.setPlayerActive(false);
    _aiSubtitleCancellationToken?.cancel();
    _englishFillCancellationToken?.cancel();
    _ocrPersistDebounce?.cancel();
    final List<PlayerSubtitleLine>? pending = _pendingOcrPersistLines;
    if (pending != null) {
      unawaited(_persistCompletedBilingualSubtitles(pending));
    }
    unawaited(_bilingualPipeline?.dispose());
    _bilingualPipeline = null;
    PlayerSystemMediaControls.unbind();
    unawaited(_disposeVideo().whenComplete(_releaseGraphicsCache));
    _transcriptReaderSession.dispose();
    super.dispose();
  }

  void _syncIdleSchedulerWithPlayback(bool isPlaying) {
    SubtitleCompletionScheduler.instance.setPlayerActive(isPlaying);
  }

  void _scheduleOcrSubtitlePersist(List<PlayerSubtitleLine> lines) {
    _pendingOcrPersistLines = lines;
    _ocrPersistDebounce?.cancel();
    _ocrPersistDebounce = Timer(const Duration(milliseconds: 700), () {
      final List<PlayerSubtitleLine>? pending = _pendingOcrPersistLines;
      _pendingOcrPersistLines = null;
      if (pending == null || !mounted) {
        return;
      }
      unawaited(_persistCompletedBilingualSubtitles(pending));
    });
  }

  Future<void> _loadEpisodeResources() async {
    final List<LibraryCourseData> courses = ref.read(libraryCatalogProvider);
    PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: courses,
      episodeId: widget.episodeId,
    );
    final String? initialStartTime =
        widget.initialStartTime ??
        ((resource.episode?.completed ?? false)
            ? null
            : resource.episode?.progressTimeStr);
    _videoAsset = resource.videoAsset;

    String? enSub = resource.englishSubtitleAsset;
    String? zhSub = resource.chineseSubtitleAsset;
    final ({String? en, String? zh, bool dropped}) filtered =
        await _filterForeignSubtitles(
          resource: resource,
          enSub: enSub,
          zhSub: zhSub,
        );
    enSub = filtered.en;
    zhSub = filtered.zh;
    if (filtered.dropped) {
      resource = resolvePlayerCourseForEpisode(
        courses: ref.read(libraryCatalogProvider),
        episodeId: widget.episodeId,
      );
    }
    if (_needsBilibiliPrepare(resource)) {
      if (mounted) {
        setState(() {
          _videoLoading = true;
          _videoErrorText = '正在准备 B 站本地视频与字幕…';
          _isBootstrapping = false;
        });
      }
      final BilibiliEpisodePrepareResult prepared =
          await _prepareBilibiliEpisodeAssets(resource);
      if (!mounted) {
        return;
      }
      if ((prepared.enSubtitlePath ?? '').isNotEmpty) {
        enSub = prepared.enSubtitlePath;
      }
      if ((prepared.zhSubtitlePath ?? '').isNotEmpty) {
        zhSub = prepared.zhSubtitlePath;
      }
      if ((prepared.localVideoPath ?? '').isNotEmpty) {
        _videoAsset = prepared.localVideoPath;
      }
      if ((prepared.note ?? '').isNotEmpty) {
        final String note = prepared.note!;
        setState(() => _videoErrorText = note);
        if ((prepared.localVideoPath ?? '').isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            final ScaffoldMessengerState messenger = ScaffoldMessenger.of(
              context,
            );
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              SnackBar(
                content: Text(note),
                duration: const Duration(seconds: 4),
              ),
            );
          });
        }
      }
      resource = resolvePlayerCourseForEpisode(
        courses: ref.read(libraryCatalogProvider),
        episodeId: widget.episodeId,
      );
    }

    List<PlayerSubtitleLine> resolvedLines = const <PlayerSubtitleLine>[];
    bool officialEnglish = false;
    final bool enIsScopedPersist = (enSub ?? '').contains(
      '${Platform.pathSeparator}episode_subtitles${Platform.pathSeparator}',
    );
    final bool zhIsScopedPersist = (zhSub ?? '').contains(
      '${Platform.pathSeparator}episode_subtitles${Platform.pathSeparator}',
    );
    if (enIsScopedPersist || zhIsScopedPersist) {
      enSub = null;
      zhSub = null;
    }
    if (isUsableSubtitlePath(enSub)) {
      try {
        final List<PlayerSubtitleLine> englishLines = await loadSubtitleLines(
          enSub!,
        );
        List<PlayerSubtitleLine> chineseLines = const <PlayerSubtitleLine>[];
        if (isUsableSubtitlePath(zhSub)) {
          chineseLines = await loadSubtitleLines(zhSub!);
        }
        resolvedLines = mergeSubtitleLines(
          englishLines: englishLines,
          chineseLines: chineseLines,
        );
        officialEnglish = resolvedLines.any(
          (PlayerSubtitleLine line) => isReliableOcrEnglish(line.english),
        );
      } catch (e) {
        // ignore: avoid_print
        print('bilibili.prepare load en/zh subs error: $e');
        resolvedLines = const <PlayerSubtitleLine>[];
      }
    } else if (isUsableSubtitlePath(zhSub)) {
      try {
        resolvedLines = normalizeChineseOnlySubtitleLines(
          await loadSubtitleLines(zhSub!),
        );
      } catch (e) {
        // ignore: avoid_print
        print('bilibili.prepare load zh-only subs error: $e');
        resolvedLines = const <PlayerSubtitleLine>[];
      }
    }
    if (!resolvedLines.any(
      (PlayerSubtitleLine line) => looksChinese(line.chinese),
    )) {
      final String? officialZh = await existingOfficialBilibiliSubtitle(
        idKey: _episodeSourceKey(resource),
        fileName: 'zh.srt',
      );
      if (officialZh != null) {
        try {
          resolvedLines = normalizeChineseOnlySubtitleLines(
            await loadSubtitleLines(officialZh),
          );
        } catch (e) {
          // ignore: avoid_print
          print('bilibili official zh load error: $e');
        }
      }
    }
    if (_linesMissingEnglish(resolvedLines)) {
      try {
        final String? sourceKey = _episodeSourceKey(resource);
        final bool isSeason =
            resource.course?.id.startsWith('bilibili-season-') ?? false;
        if (isSeason && (sourceKey == null || sourceKey.isEmpty)) {
          await deletePersistedBilingualSubtitleFiles(
            episodeId: widget.episodeId,
          );
        } else {
          final PersistedBilingualSubtitleFiles? files =
              await locatePersistedBilingualSubtitleFiles(
                episodeId: widget.episodeId,
                sourceKey: sourceKey,
              );
          if (files != null &&
              isUsableSubtitlePath(files.englishPath) &&
              isUsableSubtitlePath(files.chinesePath)) {
            final List<PlayerSubtitleLine> cachedEnglish =
                await loadSubtitleLines(files.englishPath);
            final List<PlayerSubtitleLine> cachedPair =
                mergePartialEnglishOntoChineseBase(
                  chineseLines: await loadSubtitleLines(files.chinesePath),
                  englishLines: cachedEnglish,
                  allowIndexFallback: false,
                );
            final bool officialChinese = resolvedLines.any(
              (PlayerSubtitleLine line) => looksChinese(line.chinese),
            );
            if (officialChinese) {
              final bool trustTranslation =
                  await persistedEnglishIsZhTranslation(
                    episodeId: widget.episodeId,
                  );
              resolvedLines = subtitleBaseFromOfficialChinese(
                officialChinese: resolvedLines,
                cachedLines: cachedPair,
                cachedEnglishIsTranslation: trustTranslation,
              );
            } else {
              final List<PlayerSubtitleLine> merged =
                  mergePartialEnglishOntoChineseBase(
                    chineseLines: await loadSubtitleLines(files.chinesePath),
                    englishLines: cachedEnglish,
                  );
              final bool hasAnyEnglish = merged.any(
                (PlayerSubtitleLine line) => looksEnglish(line.english),
              );
              if (merged.isNotEmpty && hasAnyEnglish) {
                resolvedLines = merged;
              }
            }
          }
        }
      } catch (_) {}
    }
    Map<int, List<PlayerSubtitleLine>> asrFragments =
        const <int, List<PlayerSubtitleLine>>{};
    bool usingAsrSentences = false;
    final MergedSubtitleBundle? asrBundle = await loadAsrSentenceSubtitles(
      episodeId: widget.episodeId,
      sourceKey: _episodeSourceKey(resource),
    );
    if (asrBundle != null && asrBundle.sentences.isNotEmpty) {
      resolvedLines = asrBundle.sentenceLines;
      asrFragments = asrBundle.fragmentsBySentenceStartMs();
      usingAsrSentences = true;
      officialEnglish = false;
    }
    _manualEnglishByStartMs
      ..clear()
      ..addAll(await loadManualEnglishLocks(episodeId: widget.episodeId));
    _manualChineseByStartMs
      ..clear()
      ..addAll(await loadManualChineseLocks(episodeId: widget.episodeId));
    _lineNotesByStartMs
      ..clear()
      ..addAll(await loadEpisodeLineNotes(episodeId: widget.episodeId));
    if (_manualEnglishByStartMs.isNotEmpty) {
      resolvedLines = keepManualEnglish(
        lines: resolvedLines,
        manualEnglishByStartMs: _manualEnglishByStartMs,
      );
    }
    if (_manualChineseByStartMs.isNotEmpty) {
      resolvedLines = keepManualChinese(
        lines: resolvedLines,
        manualChineseByStartMs: _manualChineseByStartMs,
      );
    }
    if (!mounted) {
      return;
    }

    setState(() {
      state
        ..loadLines(resolvedLines, initialStartTime: initialStartTime)
        ..setSubtitleMode(
          _linesMissingEnglish(resolvedLines)
              ? SubtitleDisplayMode.bilingual
              : SubtitleDisplayMode.normalize(
                  ref.read(learningSettingsProvider).subtitleMode,
                ),
        )
        ..isPlaying = widget.autoPlay && (_videoAsset?.isNotEmpty ?? false);
      _usingAiSubtitles = usingAsrSentences;
      _usingAsrSentences = usingAsrSentences;
      _asrFragmentsBySentenceStartMs = asrFragments;
      _hasOfficialEnglish = officialEnglish;
      _referenceSubtitleLines = resolvedLines;
      _isBootstrapping = false;
      if (!usingAsrSentences && _linesMissingEnglish(resolvedLines)) {
        // OCR-first: burned-in English hardsubs beat machine ZH→EN.
        _bilingualPhase = BilingualPipelinePhase.ocrRunning;
        _bilingualPipelineLabel = '正在识别画面英文字幕…';
        _bilingualShowAiComplete = false;
      } else {
        _bilingualPhase = BilingualPipelinePhase.idle;
        _bilingualPipelineLabel = null;
        _bilingualShowAiComplete = false;
      }
    });
    if (resource.episode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
        ref.read(lastLearningEpisodeProvider.notifier).record(widget.episodeId);
      });
    }
    if (!usingAsrSentences &&
        _linesMissingEnglish(resolvedLines) &&
        resolvedLines.any((PlayerSubtitleLine l) => looksChinese(l.chinese))) {
      unawaited(_eagerFillEnglishFromChinese());
    }
    await _initVideo();
  }

  bool _needsBilibiliPrepare(PlayerCourseLookupResult resource) {
    final LibraryCourseData? course = resource.course;
    if (course == null) {
      return false;
    }
    final bool isBili =
        course.category == 'bilibili' ||
        course.sourceLabel.toLowerCase().contains('bilibili') ||
        course.id.startsWith('bilibili-');
    if (!isBili) {
      return false;
    }
    final bool hasLocalVideo = isUsableLocalVideoPath(resource.videoAsset);
    final bool hasEnglish = isUsableSubtitlePath(resource.englishSubtitleAsset);
    final bool hasChinese = isUsableSubtitlePath(resource.chineseSubtitleAsset);
    // Local + real English: open immediately. Local + Chinese-only still
    // prepare once so official EN can be pulled before falling back to translate.
    if (hasLocalVideo && hasEnglish) {
      return false;
    }
    if (hasLocalVideo && hasChinese && !hasEnglish) {
      return true;
    }
    return !hasLocalVideo || (!hasEnglish && !hasChinese);
  }

  Future<void> _persistBilibiliEpisodeAssets({
    required PlayerCourseLookupResult resource,
    String? localVideoPath,
    String? enSubtitlePath,
    String? zhSubtitlePath,
    String? sourceUrl,
    bool clearSubtitles = false,
  }) async {
    final LibraryCourseData? course = resource.course;
    final LibraryEpisodeItem? episode = resource.episode;
    if (course == null || episode == null) {
      return;
    }
    final bool hasEn = isUsableSubtitlePath(enSubtitlePath);
    final bool hasZh = isUsableSubtitlePath(zhSubtitlePath);
    final bool hasVideo = isUsableLocalVideoPath(localVideoPath);
    if (!hasEn &&
        !hasZh &&
        !hasVideo &&
        !clearSubtitles &&
        (sourceUrl == null || sourceUrl.trim().isEmpty)) {
      return;
    }
    await ref
        .read(libraryCatalogProvider.notifier)
        .updateEpisodeLocalMedia(
          courseId: course.id,
          episodeId: episode.id,
          videoAsset: hasVideo ? localVideoPath : null,
          sourceUrl: sourceUrl,
          enSubtitlePath: hasEn ? enSubtitlePath : null,
          zhSubtitlePath: hasZh ? zhSubtitlePath : null,
          videoMissing: hasVideo ? false : null,
          clearSubtitles: clearSubtitles,
        );
  }

  Future<void> _rejectSubtitlesThatExceedVideo(Duration mediaDuration) async {
    if (!mounted || !state.hasLines || mediaDuration.inMilliseconds <= 0) {
      return;
    }
    final int endMs = subtitleLinesEndMs(state.lines);
    if (!subtitleTimelineExceedsMedia(
      subtitleEndMs: endMs,
      mediaDurationMs: mediaDuration.inMilliseconds,
    )) {
      return;
    }
    await deletePersistedBilingualSubtitleFiles(episodeId: widget.episodeId);
    final String? sourceKey = _episodeSourceKey();
    if (sourceKey != null && sourceKey.isNotEmpty) {
      try {
        await BilibiliImportService.withCookie(
          ref.read(learningSettingsProvider).resolvedBilibiliCookieHeader,
        ).clearOfficialSubtitleFiles(sourceKey);
      } catch (_) {}
    }
    final PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: widget.episodeId,
    );
    await _persistBilibiliEpisodeAssets(
      resource: resource,
      sourceUrl: bilibiliSourceForEpisode(
        course: resource.course,
        episode: resource.episode,
        videoAsset: resource.videoAsset ?? _videoAsset,
      ),
      clearSubtitles: true,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      state.replaceLines(const <PlayerSubtitleLine>[]);
      _referenceSubtitleLines = const <PlayerSubtitleLine>[];
      _usingAiSubtitles = false;
      _usingAsrSentences = false;
      _asrFragmentsBySentenceStartMs = const <int, List<PlayerSubtitleLine>>{};
      _bilingualPhase = BilingualPipelinePhase.ocrRunning;
      _bilingualPipelineLabel = '字幕与视频不匹配，已清除，正在重新识别…';
      _bilingualShowAiComplete = false;
    });
    _showMessage('检测到串台字幕（时长不匹配），已清除并重新识别');
    unawaited(_restartEnglishFillFromChineseAndOcr());
  }

  Future<({String? en, String? zh, bool dropped})> _filterForeignSubtitles({
    required PlayerCourseLookupResult resource,
    required String? enSub,
    required String? zhSub,
  }) async {
    final String? source = bilibiliSourceForEpisode(
      course: resource.course,
      episode: resource.episode,
      videoAsset: resource.videoAsset ?? _videoAsset,
    );
    if (source == null || source.isEmpty) {
      return (en: enSub, zh: zhSub, dropped: false);
    }
    final bool enForeign =
        isUsableSubtitlePath(enSub) &&
        !bilibiliSubtitleBelongsToSource(subtitlePath: enSub, source: source);
    final bool zhForeign =
        isUsableSubtitlePath(zhSub) &&
        !bilibiliSubtitleBelongsToSource(subtitlePath: zhSub, source: source);
    if (!enForeign && !zhForeign) {
      if ((resource.episode?.sourceUrl ?? '').trim().isEmpty) {
        await _persistBilibiliEpisodeAssets(
          resource: resource,
          sourceUrl: source,
        );
      }
      return (en: enSub, zh: zhSub, dropped: false);
    }
    await deletePersistedBilingualSubtitleFiles(episodeId: widget.episodeId);
    final String? videoPath = resource.videoAsset ?? _videoAsset;
    if (videoPath != null && videoPath.isNotEmpty) {
      try {
        await const AsrSubtitleCache().delete(
          episodeId: widget.episodeId,
          videoPath: videoPath,
        );
      } catch (_) {}
    }
    await _persistBilibiliEpisodeAssets(
      resource: resource,
      sourceUrl: source,
      clearSubtitles: true,
    );
    return (
      en: enForeign ? null : enSub,
      zh: zhForeign ? null : zhSub,
      dropped: true,
    );
  }

  Future<BilibiliEpisodePrepareResult> _prepareBilibiliEpisodeAssets(
    PlayerCourseLookupResult resource,
  ) async {
    final BilibiliImportService service = BilibiliImportService.withCookie(
      ref.read(learningSettingsProvider).resolvedBilibiliCookieHeader,
    );
    LibraryCourseData? course = resource.course;
    if (course != null) {
      try {
        final LibraryCourseData? expanded = await expandBilibiliCourseIfNeeded(
          service: service,
          course: course,
        );
        if (expanded != null) {
          await ref
              .read(libraryCatalogProvider.notifier)
              .importCourse(expanded);
          course = expanded;
          resource = resolvePlayerCourseForEpisode(
            courses: ref.read(libraryCatalogProvider),
            episodeId: widget.episodeId,
          );
          if (resource.course == null) {
            resource = resolvePlayerCourseForEpisode(
              courses: ref.read(libraryCatalogProvider),
              episodeId: _preferredExpandedEpisodeId(expanded),
            );
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print('bilibili.prepare expand pages error: $e');
      }
    }
    final bool isSeason =
        (resource.course ?? course)?.id.startsWith('bilibili-season-') ?? false;
    final String? source =
        bilibiliSourceForEpisode(
          course: resource.course ?? course,
          episode: resource.episode,
          videoAsset: resource.videoAsset,
        ) ??
        _bilibiliRecoverSource(resource.videoAsset ?? '') ??
        (isSeason
            ? null
            : _bilibiliRecoverSource(resource.course?.description ?? ''));
    if (source == null || source.isEmpty) {
      return const BilibiliEpisodePrepareResult(
        note: '无法识别本集 B 站来源（合集分集需各自 BV）',
      );
    }
    String? currentVideoAsset = resource.videoAsset;
    if (!isUsableLocalVideoPath(currentVideoAsset)) {
      try {
        final String? cached = await service.findExistingLocalCache(source);
        if (isUsableLocalVideoPath(cached)) {
          currentVideoAsset = cached;
          await _persistBilibiliEpisodeAssets(
            resource: resource,
            localVideoPath: cached,
            sourceUrl: source,
          );
        }
      } catch (_) {}
    }
    final BilibiliEpisodePrepareResult prepared = await prepareBilibiliEpisode(
      service: service,
      source: source,
      currentVideoAsset: currentVideoAsset,
      existingEnSubtitlePath: resource.englishSubtitleAsset,
      existingZhSubtitlePath: resource.chineseSubtitleAsset,
      onProgress: (String message) {
        if (!mounted) {
          return;
        }
        setState(() => _videoErrorText = message);
      },
      onSubtitlesReady:
          ({
            required String? enSubtitlePath,
            required String? zhSubtitlePath,
            String? note,
          }) async {
            await _persistBilibiliEpisodeAssets(
              resource: resource,
              enSubtitlePath: enSubtitlePath,
              zhSubtitlePath: zhSubtitlePath,
              sourceUrl: source,
            );
          },
    );
    await _persistBilibiliEpisodeAssets(
      resource: resource,
      localVideoPath: prepared.localVideoPath,
      enSubtitlePath: prepared.enSubtitlePath,
      zhSubtitlePath: prepared.zhSubtitlePath,
      sourceUrl: source,
    );
    return prepared;
  }

  Future<void> _initVideo() async {
    await _disposeVideo();
    if (!mounted) return;

    if (_videoAsset == null || _videoAsset!.isEmpty) {
      setState(() {
        _videoReady = false;
        _videoLoading = false;
        _videoErrorText = null;
        _videoDuration = Duration.zero;
        _videoPosition = Duration.zero;
      });
      _applyPlaybackMode();
      return;
    }

    final bool isBilibili = BilibiliImport.isWatchPageUrl(_videoAsset!);
    setState(() {
      _videoReady = false;
      _videoLoading = true;
      _videoErrorText = isBilibili ? '正在解析 B 站视频…' : null;
    });

    final Player player = createStudyVideoPlayer();
    // Own the player before opening media so leaving during initialization
    // also releases its decoder and native video output.
    _videoPlayer = player;
    final int initialPositionMs = state.positionMs;

    try {
      final VideoController controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration:
              defaultTargetPlatform != TargetPlatform.macOS,
        ),
      );
      _videoController = controller;
      final ({String uri, Map<String, String>? headers}) media =
          await _resolvePlayableMedia(
            _videoAsset!,
            onProgress: isBilibili
                ? (double? _, String message) {
                    if (!mounted || !identical(_videoPlayer, player)) {
                      return;
                    }
                    setState(() => _videoErrorText = message);
                  }
                : null,
          ).timeout(
            Duration(minutes: isBilibili ? 8 : 1),
            onTimeout: () =>
                throw StateError(isBilibili ? '缓存 B 站视频超时，请检查网络后重试' : '视频加载超时'),
          );
      if (!mounted || !identical(_videoPlayer, player)) return;
      setState(() {
        _videoErrorText = isBilibili ? '正在连接播放器…' : null;
      });
      await waitForVideoInitialization(() async {
        await player.open(
          Media(
            createPlayerMediaUri(media.uri),
            httpHeaders: media.headers ?? const <String, String>{},
          ),
        );
      }, timeout: Duration(seconds: isBilibili ? 30 : 8));
      if (!mounted || !identical(_videoPlayer, player)) return;
      await waitForPlayerReady(
        player,
        timeout: Duration(seconds: isBilibili ? 30 : 8),
      );
      if (!mounted || !identical(_videoPlayer, player)) return;
      await suppressPlayerSoftSubtitles(player);
      await player.setRate(state.playbackRate);
      await player.setVolume(_volumeLevel * 100);
      if (!mounted || !identical(_videoPlayer, player)) return;

      _videoDuration = player.state.duration;
      _videoPosition = player.state.position;
      _syncVideoAspectRatio(player.state.width, player.state.height);
      if (initialPositionMs > 0) {
        await player.seek(Duration(milliseconds: initialPositionMs));
      }
      await player.pause();
      _videoPosition = player.state.position;
      if (!mounted || !identical(_videoPlayer, player)) return;
      _attachVideoListeners(player);
      final List<SubtitleTrack> embeddedTracks = embeddedSubtitleTracks(
        player.state.tracks.subtitle,
      );
      setState(() {
        _embeddedSubtitleTracks = embeddedTracks;
        _selectedEmbeddedSubtitleId = null;
        _videoReady = true;
        _videoLoading = false;
        _videoErrorText = null;
      });
      final bool hasEmbeddedEnglish = embeddedTracks.any(
        (SubtitleTrack track) =>
            track.language == 'eng' || track.language == 'en',
      );
      if (_referenceSubtitleLines.isEmpty && hasEmbeddedEnglish) {
        unawaited(_loadEmbeddedReferenceAndCachedAiSubtitles(embeddedTracks));
      } else if ((!state.hasLines || _linesMissingEnglish(state.lines)) &&
          !state.lines.any(
            (PlayerSubtitleLine line) => looksChinese(line.chinese),
          )) {
        await _loadCachedAiSubtitles(validateReferenceSignature: false);
      }
      if (!mounted) return;
      _applyPlaybackMode();
      unawaited(_maybeStartBilingualPipeline());
    } catch (error) {
      if (identical(_videoPlayer, player)) await _disposeVideo();
      if (!mounted) {
        return;
      }
      setState(() {
        _videoPlayer = null;
        _videoController = null;
        _videoReady = false;
        _videoLoading = false;
        _videoErrorText = _videoLoadErrorMessage(error, _videoAsset);
      });
      _applyPlaybackMode();
      if (_linesMissingEnglish(state.lines)) {
        unawaited(_eagerFillEnglishFromChinese());
      }
    }
  }

  Future<({String uri, Map<String, String>? headers})> _resolvePlayableMedia(
    String source, {
    void Function(double? progress, String message)? onProgress,
  }) async {
    final String trimmed = source.trim();
    final bool looksLocal =
        trimmed.isNotEmpty &&
        !trimmed.startsWith('http://') &&
        !trimmed.startsWith('https://');
    if (looksLocal) {
      final File local = File(trimmed);
      if (local.existsSync() && local.lengthSync() > 64 * 1024) {
        return (uri: trimmed, headers: null);
      }
    } else if (!BilibiliImport.isWatchPageUrl(trimmed) &&
        !BilibiliImport.looksLikeBilibiliInput(trimmed)) {
      return (uri: trimmed, headers: null);
    }

    final PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: widget.episodeId,
    );
    final String? biliSource =
        bilibiliSourceForEpisode(
          course: resource.course,
          episode: resource.episode,
          videoAsset: resource.videoAsset ?? trimmed,
        ) ??
        _bilibiliRecoverSource(trimmed);
    if (biliSource == null) {
      if (looksLocal) {
        throw StateError('本地视频文件不存在，且无法从课程信息恢复 B 站链接');
      }
      return (uri: trimmed, headers: null);
    }

    try {
      final BilibiliImportService service = BilibiliImportService.withCookie(
        ref.read(learningSettingsProvider).resolvedBilibiliCookieHeader,
      );
      final String? cached = await service.findExistingLocalCache(biliSource);
      if (isUsableLocalVideoPath(cached)) {
        await _persistLocalBilibiliVideo(cached!);
        if (mounted) {
          setState(() => _videoAsset = cached);
        }
        onProgress?.call(1, '使用已缓存视频');
        return (uri: cached, headers: null);
      }
      final BilibiliPlayableMedia media = await service
          .resolvePlayableForPlayback(biliSource, onProgress: onProgress);
      if (media.isLocalFile) {
        await _persistLocalBilibiliVideo(media.uri);
        if (mounted) {
          setState(() => _videoAsset = media.uri);
        }
      }
      return (uri: media.uri, headers: media.headers);
    } catch (error) {
      throw StateError('B站视频无法播放：$error');
    }
  }

  String _preferredExpandedEpisodeId(LibraryCourseData expanded) {
    for (final LibraryEpisodeItem episode in expanded.episodes) {
      if (isUsableLocalVideoPath(episode.videoAsset) && !episode.videoMissing) {
        return episode.id;
      }
    }
    return expanded.episodes.first.id;
  }

  String? _bilibiliRecoverSource(String source) {
    if (BilibiliImport.isWatchPageUrl(source) ||
        BilibiliImport.looksLikeBilibiliInput(source)) {
      return source;
    }
    final PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: widget.episodeId,
    );
    final LibraryCourseData? course = resource.course;
    if (course == null) {
      return null;
    }
    final bool isSeason = course.id.startsWith('bilibili-season-');
    final String? fromEpisode = bilibiliSourceForEpisode(
      course: course,
      episode: resource.episode,
      videoAsset: resource.videoAsset ?? source,
    );
    if (fromEpisode != null && fromEpisode.isNotEmpty) {
      return fromEpisode;
    }
    if (isSeason) {
      return null;
    }
    final String description = course.description.trim();
    if (BilibiliImport.looksLikeBilibiliInput(description)) {
      return description;
    }
    if (course.id.startsWith('bilibili-')) {
      final String idKey = course.id.substring('bilibili-'.length);
      if (idKey.startsWith('BV') || idKey.startsWith('av')) {
        return idKey;
      }
    }
    return null;
  }

  Future<void> _persistLocalBilibiliVideo(String localPath) async {
    final PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: widget.episodeId,
    );
    final String? courseId = resource.course?.id;
    final String? episodeId = resource.episode?.id;
    if (courseId == null ||
        courseId.isEmpty ||
        episodeId == null ||
        episodeId.isEmpty) {
      return;
    }
    final String? current = resource.episode?.videoAsset?.trim();
    if (current == localPath) {
      return;
    }
    await ref
        .read(libraryCatalogProvider.notifier)
        .updateEpisodeLocalMedia(
          courseId: courseId,
          episodeId: episodeId,
          videoAsset: localPath,
          videoMissing: false,
        );
  }

  Future<String> _resolveAsrVideoPath(String source) async {
    final String? catalogLocal = _catalogLocalVideoPath();
    if (catalogLocal != null) {
      return catalogLocal;
    }
    if (isUsableLocalVideoPath(source)) {
      return source;
    }
    if (isUsableLocalVideoPath(_videoAsset)) {
      return _videoAsset!.trim();
    }

    final PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: widget.episodeId,
    );
    final String? biliSource =
        bilibiliSourceForEpisode(
          course: resource.course,
          episode: resource.episode,
          videoAsset: resource.videoAsset ?? _videoAsset ?? source,
        ) ??
        _bilibiliRecoverSource(source) ??
        _bilibiliRecoverSource(_videoAsset ?? '') ??
        _bilibiliRecoverSource(resource.course?.description ?? '');

    final String input = (biliSource != null && biliSource.trim().isNotEmpty)
        ? biliSource.trim()
        : source;
    final bool needsBilibiliCache =
        BilibiliImport.isWatchPageUrl(input) ||
        BilibiliImport.looksLikeBilibiliInput(input) ||
        input.startsWith('http://127.0.0.1');
    if (!needsBilibiliCache) {
      if (isUsableLocalVideoPath(input)) {
        return input;
      }
      throw StateError('本地视频不可用，无法语音识别');
    }
    if (BilibiliImport.isShortLink(input) &&
        BilibiliImport.extractIds(input) == null) {
      throw StateError('B 站短链无法解析。请确认分集已下载到本地后再生成，或改用「重新识别」翻译补全。');
    }
    if (mounted) {
      setState(() => _aiSubtitleProgressText = '正在下载视频供语音识别…');
    }
    return BilibiliImportService.withCookie(
      ref.read(learningSettingsProvider).resolvedBilibiliCookieHeader,
    ).ensureLocalCacheForAsr(
      input,
      onProgress: (double? _, String message) {
        if (!mounted) return;
        setState(() => _aiSubtitleProgressText = message);
      },
    );
  }

  String? _catalogLocalVideoPath() {
    final PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: widget.episodeId,
    );
    if (isUsableLocalVideoPath(resource.episode?.videoAsset)) {
      return resource.episode!.videoAsset!.trim();
    }
    if (isUsableLocalVideoPath(resource.videoAsset)) {
      return resource.videoAsset!.trim();
    }
    if (isUsableLocalVideoPath(_videoAsset)) {
      return _videoAsset!.trim();
    }
    return null;
  }

  /// Subtitles are completed at import time — player only re-queues unfinished work.
  Future<void> _eagerFillEnglishFromChinese() async {
    if (!mounted) {
      return;
    }
    final PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: widget.episodeId,
    );
    final String? videoPath = _videoAsset ?? resource.videoAsset;
    if (!isUsableLocalVideoPath(videoPath)) {
      return;
    }
    final SubtitleCompletionNeed need = await detectSubtitleCompletionNeed(
      episodeId: widget.episodeId,
      zhSubtitlePath: resource.chineseSubtitleAsset,
      enSubtitlePath: resource.englishSubtitleAsset,
      sourceKey: bilibiliIdKeyFromPath(resource.episode?.sourceUrl) ??
          bilibiliIdKeyFromPath(videoPath),
    );
    if (!need.any) {
      return;
    }
    if (mounted) {
      setState(() {
        _bilingualPhase = BilingualPipelinePhase.asrProofreading;
        _bilingualShowAiComplete = false;
        _bilingualPipelineLabel = need.needEnglish && need.needChinese
            ? '导入后台补全中英字幕中…'
            : (need.needEnglish ? '导入后台语音补英文中…' : '导入后台补中文中…');
      });
    }
    await enqueueSubtitleCompletionForEpisode(
      episodeId: widget.episodeId,
      videoPath: videoPath,
      zhSubtitlePath: resource.chineseSubtitleAsset,
      enSubtitlePath: resource.englishSubtitleAsset,
      sourceUrl: resource.episode?.sourceUrl,
    );
    SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
  }

  Future<void> _maybeStartBilingualPipeline() async {
    if (!mounted || _generatingAiSubtitles) {
      return;
    }
    final String? rawVideoPath = _videoAsset;
    if (rawVideoPath == null || rawVideoPath.isEmpty || !_videoReady) {
      return;
    }
    String videoPath = rawVideoPath;
    if (!isUsableLocalVideoPath(videoPath)) {
      try {
        final String local = await _resolveAsrVideoPath(videoPath);
        if (isUsableLocalVideoPath(local)) {
          videoPath = local;
          if (mounted) {
            setState(() => _videoAsset = local);
          }
        }
      } catch (_) {}
    }
    // Empty timeline still runs OCR: hardsub-only videos have no softsubs.
    // Chinese courses whose English is only a machine translation still need
    // a video proofread — that English can be fluent and unrelated.
    final bool needsFill = BilingualSubtitlePipeline.shouldAutoStart(
      state.lines,
    );
    final bool proofreadTranslation =
        state.hasLines &&
        !needsFill &&
        !_hasOfficialEnglish &&
        state.lines.any(
          (PlayerSubtitleLine line) => looksChinese(line.chinese),
        );
    if (state.hasLines && !needsFill && !proofreadTranslation) {
      return;
    }
    if (!state.hasLines && !_isLikelyHardsubCourse()) {
      return;
    }
    _usingAiSubtitles = false;
    await _bilingualPipeline?.dispose();
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    final BilingualSubtitlePipeline pipeline = BilingualSubtitlePipeline(
      episodeId: widget.episodeId,
      videoPath: videoPath,
      settings: settings,
      player: _videoPlayer,
      getLines: () => state.lines,
      setLines: (List<PlayerSubtitleLine> lines) {
        if (!mounted) {
          return;
        }
        final List<PlayerSubtitleLine> kept = _withManualEnglish(lines);
        setState(() {
          state.replaceLines(
            kept,
            preferredSubtitleMode: SubtitleDisplayMode.bilingual,
          );
          _referenceSubtitleLines = kept;
        });
        _scheduleOcrSubtitlePersist(kept);
      },
      onNeedTranslationFallback: () {
        unawaited(_eagerFillEnglishFromChinese());
      },
      onPhaseChanged: (BilingualPipelinePhase phase) {
        if (!mounted) {
          return;
        }
        setState(() {
          _bilingualPhase = phase;
          _bilingualShowAiComplete = phase == BilingualPipelinePhase.ocrSlow;
          if (phase == BilingualPipelinePhase.completed) {
            final bool stillMissing = _linesMissingEnglish(state.lines);
            _usingAiSubtitles = !stillMissing;
            _bilingualPipelineLabel = stillMissing ? '英文字幕仍不完整' : null;
            _bilingualShowAiComplete = stillMissing;
          } else if (phase == BilingualPipelinePhase.cancelled) {
            _bilingualPipelineLabel = null;
            _bilingualShowAiComplete = false;
          }
        });
        if (phase == BilingualPipelinePhase.ocrSlow &&
            _linesMissingEnglish(state.lines)) {
          unawaited(_eagerFillEnglishFromChinese());
        }
      },
      onProgress: (String label) {
        if (!mounted) {
          return;
        }
        setState(() => _bilingualPipelineLabel = label);
      },
      onBilingualReady: (List<PlayerSubtitleLine> lines) async {
        await _persistCompletedBilingualSubtitles(_withManualEnglish(lines));
        if (mounted) {
          _showMessage('双语字幕已保存到本机，下次打开不用重译');
        }
      },
    );
    _bilingualPipeline = pipeline;
    final bool translateFirst =
        needsFill &&
        state.lines.any(
          (PlayerSubtitleLine line) =>
              looksChinese(line.chinese) ||
              (looksChinese(line.english) && !looksEnglish(line.english)),
        );
    setState(() {
      _bilingualPhase = proofreadTranslation
          ? BilingualPipelinePhase.asrProofreading
          : (translateFirst
                ? BilingualPipelinePhase.translating
                : BilingualPipelinePhase.ocrRunning);
      _bilingualPipelineLabel = proofreadTranslation
          ? '正在用语音对齐英文…'
          : (translateFirst ? '正在把中文字幕翻译成英文…' : '正在识别画面英文字幕…');
      _bilingualShowAiComplete = false;
    });
    if (_linesMissingEnglish(state.lines)) {
      unawaited(_eagerFillEnglishFromChinese());
    }
    await pipeline.startOcr(
      isPlaying: () => state.isPlaying || _videoIsPlaying,
      positionMs: () => _videoPosition.inMilliseconds > 0
          ? _videoPosition.inMilliseconds
          : state.positionMs,
      proofreadExisting: proofreadTranslation,
    );
  }

  bool _linesMissingEnglish(List<PlayerSubtitleLine> lines) {
    if (lines.isEmpty) {
      return true;
    }
    return BilingualSubtitlePipeline.shouldAutoStart(lines);
  }

  bool _isLikelyHardsubCourse() {
    final PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: widget.episodeId,
    );
    final LibraryCourseData? course = resource.course;
    if (course == null) {
      final String asset = (_videoAsset ?? '').toLowerCase();
      return asset.contains('bilibili.com') ||
          asset.contains('b23.tv') ||
          asset.contains('bili2233.cn');
    }
    return course.category == 'bilibili' ||
        course.sourceLabel.toLowerCase().contains('bilibili') ||
        course.id.startsWith('bilibili-');
  }

  String? _episodeSourceKey([PlayerCourseLookupResult? resource]) {
    final PlayerCourseLookupResult resolved =
        resource ??
        resolvePlayerCourseForEpisode(
          courses: ref.read(libraryCatalogProvider),
          episodeId: widget.episodeId,
        );
    final String? source = bilibiliSourceForEpisode(
      course: resolved.course,
      episode: resolved.episode,
      videoAsset: resolved.videoAsset ?? _videoAsset,
    );
    return bilibiliIdKeyFromPath(source) ??
        bilibiliIdKeyFromPath(resolved.videoAsset ?? _videoAsset) ??
        BilibiliImport.extractIds(source ?? '')?['bvid'];
  }

  Future<void> _persistCompletedBilingualSubtitles(
    List<PlayerSubtitleLine> lines,
  ) async {
    final String? videoPath = _videoAsset;
    if (videoPath == null || videoPath.isEmpty) {
      return;
    }
    final int englishHits = lines
        .where((PlayerSubtitleLine line) => looksEnglish(line.english))
        .length;
    if (englishHits <= 0) {
      return;
    }
    final bool complete = !_linesMissingEnglish(lines);
    if (complete) {
      final LearningSettingsState settings = ref.read(learningSettingsProvider);
      final String content = const JsonEncoder.withIndent('  ').convert(
        <String, Object?>{
          'version': 1,
          'language': 'en',
          'pipeline': 'bilingual_persist',
          'lines': lines
              .map(
                (PlayerSubtitleLine line) => <String, Object?>{
                  'startTime': line.startTime,
                  'english': line.english,
                  'chinese': line.chinese,
                  'startMs': line.startMs,
                  'endMs': line.endMs,
                  'words': line.words
                      .map(
                        (PlayerSubtitleWord w) => <String, Object?>{
                          'text': w.text,
                          'startMs': w.startMs,
                          'endMs': w.endMs,
                          if (w.confidence != null) 'confidence': w.confidence,
                        },
                      )
                      .toList(growable: false),
                },
              )
              .toList(growable: false),
        },
      );
      await const AsrSubtitleCache().write(
        episodeId: widget.episodeId,
        videoPath: videoPath,
        content: content,
        settings: settings,
        referenceSignature:
            'pipeline=bilingual_persist|${subtitleReferenceSignature(lines)}',
      );
    }
    final PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: widget.episodeId,
    );
    final PersistedBilingualSubtitleFiles? files =
        await persistBilingualSubtitleFiles(
          episodeId: widget.episodeId,
          lines: lines,
          sourceKey: _episodeSourceKey(resource),
          translatedFromChinese: lines.any(
            (PlayerSubtitleLine line) => looksChinese(line.chinese),
          ),
        );
    if (files == null || !complete) {
      return;
    }
    await _persistBilibiliEpisodeAssets(
      resource: resource,
      enSubtitlePath: files.englishPath,
      zhSubtitlePath: files.chinesePath,
      sourceUrl: bilibiliSourceForEpisode(
        course: resource.course,
        episode: resource.episode,
        videoAsset: resource.videoAsset ?? _videoAsset,
      ),
    );
  }

  Future<void> _handleAiCompleteSubtitles() async {
    final BilingualSubtitlePipeline? pipeline = _bilingualPipeline;
    if (pipeline == null || _generatingAiSubtitles) {
      return;
    }
    setState(() {
      _generatingAiSubtitles = true;
      _aiSubtitleProgressText = '正在 AI 补全…';
      _bilingualShowAiComplete = false;
    });
    try {
      await pipeline.runAiComplete();
      if (!mounted) {
        return;
      }
      await _persistCompletedBilingualSubtitles(state.lines);
      if (!mounted) {
        return;
      }
      setState(() {
        _usingAiSubtitles = true;
        _bilingualPipelineLabel = null;
        _bilingualShowAiComplete = false;
      });
      _showMessage('双语字幕已补全，已保存到本机（下次打开不用重译）');
    } catch (error) {
      if (!mounted) {
        return;
      }
      final String message = humanizeAsrSubtitleError(error);
      setState(() {
        _aiSubtitleErrorText = message;
        _bilingualShowAiComplete = true;
        _bilingualPipelineLabel = message;
      });
      _showMessage(message);
    } finally {
      if (mounted) {
        setState(() {
          _generatingAiSubtitles = false;
          _aiSubtitleProgressText = null;
        });
      }
    }
  }

  Future<void> _handleCancelBilingualPipeline() async {
    await _bilingualPipeline?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _bilingualPhase = BilingualPipelinePhase.cancelled;
      _bilingualPipelineLabel = null;
      _bilingualShowAiComplete = false;
    });
  }

  String _videoLoadErrorMessage(Object error, String? source) {
    String text = error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Exception: ', '')
        .replaceFirst('B站视频无法播放：', '');
    final RegExp statusCode = RegExp(r'status code of (\d+)');
    final Match? codeMatch = statusCode.firstMatch(text);
    if (text.contains('DioException') && codeMatch != null) {
      text = '网络错误 HTTP ${codeMatch.group(1)}';
    } else if (text.length > 80) {
      text = '${text.substring(0, 77)}...';
    }
    if (text.contains('B站') ||
        (source != null && BilibiliImport.isWatchPageUrl(source))) {
      return 'B站视频无法播放：$text';
    }
    return '视频加载失败：$text';
  }

  Future<void> _loadEmbeddedSubtitleReference(
    List<SubtitleTrack> tracks,
  ) async {
    final String? videoPath = _videoAsset;
    if (videoPath == null) return;
    final List<PlayerSubtitleLine> lines =
        await extractEmbeddedEnglishSubtitles(
          videoPath: videoPath,
          tracks: tracks,
        );
    if (!mounted || lines.isEmpty || _referenceSubtitleLines.isNotEmpty) return;
    setState(() => _referenceSubtitleLines = lines);
  }

  Future<void> _loadEmbeddedReferenceAndCachedAiSubtitles(
    List<SubtitleTrack> tracks,
  ) async {
    try {
      await _loadEmbeddedSubtitleReference(tracks);
      if (!mounted || state.hasLines || _generatingAiSubtitles) return;
      await _loadCachedAiSubtitles(
        validateReferenceSignature: _referenceSubtitleLines.isNotEmpty,
      );
    } catch (_) {
      // Reference subtitles are optional and must not block video playback.
    }
  }

  Future<void> _loadCachedAiSubtitles({
    bool validateReferenceSignature = true,
  }) async {
    final String? videoPath = _videoAsset;
    if (videoPath == null || !mounted) return;
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    final String? cached = await const AsrSubtitleCache().read(
      episodeId: widget.episodeId,
      videoPath: videoPath,
      settings: settings,
      referenceSignature: _referenceSubtitleLines.isEmpty
          ? null
          : subtitleReferenceSignature(_referenceSubtitleLines),
      validateReferenceSignature: validateReferenceSignature,
    );
    if (cached == null || !mounted) return;
    final List<PlayerSubtitleLine> lines = parseSubtitleLines(cached);
    if (lines.isEmpty) return;
    if (BilingualSubtitlePipeline.shouldAutoStart(lines)) {
      if (mounted && _videoReady) {
        unawaited(_maybeStartBilingualPipeline());
      }
      return;
    }
    final int positionMs = state.positionMs;
    setState(() {
      state
        ..loadLines(lines, wordDefinitions: parseSubtitleGlossary(cached))
        ..seekToMilliseconds(positionMs)
        ..setSubtitleMode(settings.subtitleMode);
      _usingAiSubtitles = true;
    });
  }

  Future<void> _disposeVideo() async {
    _cancelVideoSubscriptions();
    if (_videoPlayer == null) {
      await _videoDisposal;
      return;
    }

    final Player player = _videoPlayer!;
    _videoPlayer = null;
    _videoController = null;
    _videoIsPlaying = false;
    _videoDisposal = () async {
      try {
        await player.dispose();
      } catch (_) {
        // Ignore cleanup failures, disposal is best effort.
      }
    }();
    await _videoDisposal;
  }

  void _attachVideoListeners(Player player) {
    _videoTracksSubscription = player.stream.tracks.listen((Tracks tracks) {
      if (!mounted || !identical(_videoPlayer, player)) return;
      final List<SubtitleTrack> subtitles = embeddedSubtitleTracks(
        tracks.subtitle,
      );
      _selectedEmbeddedSubtitleId = null;
      unawaited(suppressPlayerSoftSubtitles(player));
      if (listEquals(_embeddedSubtitleTracks, subtitles)) return;
      setState(() {
        _embeddedSubtitleTracks = subtitles;
      });
    });
    _videoPositionSubscription = player.stream.position.listen(
      _onVideoProgress,
    );
    _videoDurationSubscription = player.stream.duration.listen((
      Duration duration,
    ) {
      if (!mounted) {
        return;
      }
      final bool durationBecameKnown =
          _videoDuration.inMilliseconds <= 0 && duration.inMilliseconds > 0;
      setState(() {
        _videoDuration = duration;
      });
      if (durationBecameKnown) {
        unawaited(_rejectSubtitlesThatExceedVideo(duration));
      }
    });
    _videoPlayingSubscription = player.stream.playing.listen((bool playing) {
      _videoIsPlaying = playing;
      _syncIdleSchedulerWithPlayback(playing);
    });
    _videoCompletedSubscription = player.stream.completed.listen((
      bool completed,
    ) {
      if (completed) {
        _stopVideo();
      }
    });
    _syncTranscriptReader();
    _videoWidthSubscription = player.stream.width.listen((int? width) {
      _syncVideoAspectRatio(width, player.state.height);
    });
    _videoHeightSubscription = player.stream.height.listen((int? height) {
      _syncVideoAspectRatio(player.state.width, height);
    });
  }

  void _cancelVideoSubscriptions() {
    unawaited(_videoPositionSubscription?.cancel());
    unawaited(_videoDurationSubscription?.cancel());
    unawaited(_videoPlayingSubscription?.cancel());
    unawaited(_videoCompletedSubscription?.cancel());
    unawaited(_videoWidthSubscription?.cancel());
    unawaited(_videoHeightSubscription?.cancel());
    unawaited(_videoTracksSubscription?.cancel());
    _videoPositionSubscription = null;
    _videoDurationSubscription = null;
    _videoPlayingSubscription = null;
    _videoCompletedSubscription = null;
    _videoWidthSubscription = null;
    _videoHeightSubscription = null;
    _videoTracksSubscription = null;
  }

  void _syncVideoAspectRatio(int? width, int? height) {
    if (!mounted ||
        width == null ||
        height == null ||
        width <= 0 ||
        height <= 0) {
      return;
    }
    final double nextAspectRatio = width / height;
    if ((_videoAspectRatio - nextAspectRatio).abs() < 0.001) {
      return;
    }
    setState(() {
      _videoAspectRatio = nextAspectRatio;
    });
  }

  void _armScrub(int targetMs) {
    _scrubTargetMs = targetMs;
    _scrubArmedAt = DateTime.now();
  }

  /// Player position events lag a scrub and would pull the highlighted cue
  /// back to the old time. Keep the scrubbed cue until the playhead arrives.
  bool _ignoreStaleScrubPosition(Duration position) {
    final int? target = _scrubTargetMs;
    final DateTime? armedAt = _scrubArmedAt;
    if (target == null || armedAt == null) {
      return false;
    }
    final bool caughtUp = (position.inMilliseconds - target).abs() <= 200;
    final bool expired =
        DateTime.now().difference(armedAt) >
        const Duration(milliseconds: 1500);
    if (!caughtUp && !expired) {
      return true;
    }
    _scrubTargetMs = null;
    _scrubArmedAt = null;
    return false;
  }

  void _onVideoProgress(Duration position) {
    if (!mounted || _ignoreStaleScrubPosition(position)) {
      return;
    }

    final bool wasPlaying = _videoIsPlaying;
    bool lineChanged = false;
    bool loopRestarted = false;

    setState(() {
      _videoPosition = position;
      loopRestarted = state.restartLoopAtTimestamp(position.inMilliseconds);
      if (loopRestarted) {
        _videoPosition = Duration(milliseconds: state.positionMs);
      } else {
        lineChanged = state.syncWithTimestamp(position.inMilliseconds);
      }
    });
    _syncTranscriptReader();

    if (wasPlaying) {
      _trackPlayProgress(position);
      unawaited(
        ref
            .read(libraryCatalogProvider.notifier)
            .updateEpisodeProgress(
              episodeId: widget.episodeId,
              position: position,
              duration: _videoDuration,
            ),
      );
    }

    if (loopRestarted) {
      _lastTrackedVideoPosition = Duration(milliseconds: state.positionMs);
      unawaited(_videoPlayer?.seek(_videoPosition));
      return;
    }

    if (lineChanged && wasPlaying) {
      _recordCurrentSentenceStudy();
      _recordCurrentLineWords();
    }

    if (!state.hasLines) {
      return;
    }
  }

  List<PlayerSubtitleLine> _withManualEnglish(List<PlayerSubtitleLine> lines) {
    return keepManualChinese(
      lines: keepManualEnglish(
        lines: lines,
        manualEnglishByStartMs: _manualEnglishByStartMs,
      ),
      manualChineseByStartMs: _manualChineseByStartMs,
    );
  }

  Future<void> _editEnglishLine(int index, String english) async {
    if (!mounted || index < 0 || index >= state.lines.length) {
      return;
    }
    await _editSubtitleLine(index, english, state.lines[index].chinese);
  }

  Future<void> _editSubtitleLine(
    int index,
    String english,
    String chinese,
  ) async {
    final String trimmedEn = english.trim();
    final String trimmedZh = chinese.trim();
    if (!mounted ||
        index < 0 ||
        index >= state.lines.length ||
        (trimmedEn.isEmpty && trimmedZh.isEmpty)) {
      return;
    }
    _stopVideo();
    final PlayerSubtitleLine current = state.lines[index];
    final String nextEnglish =
        trimmedEn.isEmpty ? current.english.trim() : trimmedEn;
    final String nextChinese =
        trimmedZh.isEmpty ? current.chinese.trim() : trimmedZh;
    if (nextEnglish.isNotEmpty) {
      _manualEnglishByStartMs[current.startMs] = nextEnglish;
      unawaited(
        saveManualEnglishLocks(
          episodeId: widget.episodeId,
          locks: _manualEnglishByStartMs,
        ),
      );
    }
    if (nextChinese.isNotEmpty) {
      _manualChineseByStartMs[current.startMs] = nextChinese;
      unawaited(
        saveManualChineseLocks(
          episodeId: widget.episodeId,
          locks: _manualChineseByStartMs,
        ),
      );
    }
    final List<PlayerSubtitleLine> next = List<PlayerSubtitleLine>.of(
      state.lines,
    );
    next[index] = PlayerSubtitleLine(
      startTime: current.startTime,
      english: nextEnglish.isEmpty ? current.english : nextEnglish,
      chinese: nextChinese,
      startMs: current.startMs,
      endMs: current.endMs,
      words: current.words,
    );
    setState(() {
      state.replaceLines(
        next,
        preferredSubtitleMode: SubtitleDisplayMode.bilingual,
      );
      _referenceSubtitleLines = next;
    });
    await _persistCompletedBilingualSubtitles(next);
    if (mounted) {
      _showMessage('已保存手工字幕，自动校对不会再改它');
    }
  }

  Future<void> _editLineNote(int index, String note) async {
    if (!mounted || index < 0 || index >= state.lines.length) {
      return;
    }
    final PlayerSubtitleLine current = state.lines[index];
    final String trimmed = note.trim();
    setState(() {
      if (trimmed.isEmpty) {
        _lineNotesByStartMs.remove(current.startMs);
      } else {
        _lineNotesByStartMs[current.startMs] = trimmed;
      }
    });
    await saveEpisodeLineNotes(
      episodeId: widget.episodeId,
      notes: _lineNotesByStartMs,
    );
    if (mounted) {
      _showMessage(trimmed.isEmpty ? '已清除笔记' : '已保存笔记');
    }
  }

  void _stopVideo() {
    if (!state.isPlaying) {
      return;
    }
    setState(() {
      state.isPlaying = false;
    });
    unawaited(_videoPlayer?.pause());
  }

  PronunciationTargetSelection _selectPronunciationForLine(int index) =>
      selectPronunciationTarget(
        state: state,
        videoSource: _videoAsset,
        videoReady: _videoReady,
        videoDuration: _videoDuration,
        subtitleIndex: index,
      );

  String? _pronunciationUnavailableReasonForLine(int index) =>
      _selectPronunciationForLine(index).unavailableReason;

  void _handleAssessLine(int index) {
    final PronunciationAssessmentTarget? target = _selectPronunciationForLine(
      index,
    ).target;
    if (target == null) {
      _showMessage(
        _pronunciationUnavailableReasonForLine(index) ?? '当前句暂不可跟读。',
      );
      return;
    }
    unawaited(_openPronunciationAssessment(target));
  }

  void _handleAssessVisibleLine() {
    final PronunciationTargetSelection selection = selectPronunciationTarget(
      state: state,
      videoSource: _videoAsset,
      videoReady: _videoReady,
      videoDuration: _videoDuration,
    );
    final PronunciationAssessmentTarget? target = selection.target;
    if (target == null) {
      _showMessage(selection.unavailableReason ?? '当前句暂不可跟读。');
      return;
    }
    unawaited(_openPronunciationAssessment(target));
  }

  Future<void> _openPronunciationAssessment(
    PronunciationAssessmentTarget target,
  ) async {
    if (_pronunciationDialogActive) return;
    _pronunciationDialogActive = true;
    setState(() => state.isPlaying = false);
    PlayerSystemMediaControls.updatePlaybackState(isPlaying: false);
    try {
      await _videoPlayer?.pause();
      try {
        await ref.read(wordPronunciationServiceProvider).stop();
      } catch (_) {}
      if (!mounted) return;
      await showPronunciationAssessmentDialog(context, target: target);
    } catch (_) {
      if (mounted) _showMessage('无法暂停当前视频，暂时不能开始录音。');
    } finally {
      _pronunciationDialogActive = false;
      if (mounted) setState(() {});
    }
  }

  void _applyPlaybackMode() {
    PlayerSystemMediaControls.updatePlaybackState(isPlaying: state.isPlaying);
    if (!state.isPlaying) {
      unawaited(_videoPlayer?.pause());
      return;
    }

    if (_videoAsset == null || _videoErrorText != null) {
      setState(() {
        state.isPlaying = false;
      });
      unawaited(_videoPlayer?.pause());
      return;
    }

    if (_videoLoading || _videoPlayer == null || !_videoReady) {
      return;
    }

    if (state.hasLines) {
      unawaited(_videoPlayer!.seek(Duration(milliseconds: state.positionMs)));
    }
    unawaited(_videoPlayer!.setRate(state.playbackRate));
    unawaited(_videoPlayer!.play());
  }

  void _seekToActiveLine() {
    if (_videoPlayer == null || !state.hasLines) {
      return;
    }
    unawaited(
      _videoPlayer!.seek(
        Duration(
          milliseconds: state.videoStartMsForLine(state.activeLineIndex),
        ),
      ),
    );
  }

  void _goToLine(int index) {
    setState(() {
      state
        ..selectLine(index)
        ..isPlaying = true;
    });
    _syncTranscriptReader();
    _seekToActiveLine();
    _recordCurrentSentenceStudy();
    _lastTrackedVideoPosition = _currentVideoPosition();
    _applyPlaybackMode();
  }

  void _handleSeek(double progress) {
    final double safeProgress = progress.clamp(0.0, 1.0);

    setState(() {
      if (_videoDuration.inMilliseconds > 0) {
        final int targetMs = (_videoDuration.inMilliseconds * safeProgress)
            .round();
        _videoPosition = Duration(milliseconds: targetMs);
        _armScrub(targetMs);
        if (state.hasLines) {
          state.seekToMilliseconds(targetMs);
        }
        _lastTrackedVideoPosition = Duration(milliseconds: targetMs);
        if (_videoPlayer != null) {
          unawaited(_videoPlayer!.seek(Duration(milliseconds: targetMs)));
        }
      } else {
        if (!state.hasLines) {
          return;
        }
        final int maxIndex = state.lines.length - 1;
        final int targetIndex = (safeProgress * maxIndex).round().clamp(
          0,
          maxIndex,
        );
        state.selectLine(targetIndex);
        state.timelineFollowEpoch += 1;
        _recordCurrentSentenceStudy();
      }
    });
    _syncTranscriptReader();
    _applyPlaybackMode();
  }

  void _handleSeekBySeconds(int deltaSeconds) {
    if (_videoDuration.inMilliseconds > 0) {
      final int targetMs =
          (_videoPosition.inMilliseconds + (deltaSeconds * 1000)).clamp(
            0,
            _videoDuration.inMilliseconds,
          );
      _handleSeek(targetMs / _videoDuration.inMilliseconds);
      return;
    }
    final int targetMs = (state.positionMs + (deltaSeconds * 1000)).clamp(
      state.lines.first.startMs,
      state.lines.last.endMs,
    );
    setState(() {
      state.seekToMilliseconds(targetMs);
    });
    _syncTranscriptReader();
    _seekToActiveLine();
    _lastTrackedVideoPosition = Duration(milliseconds: state.positionMs);
    _applyPlaybackMode();
  }

  void _syncTranscriptReader() {
    if (!state.hasLines) return;
    _transcriptReaderSession.updateProgress(
      subtitleLetterCase: ref.read(learningSettingsProvider).subtitleLetterCase,
      lineIndex: state.activeLineIndex,
      wordIndex: state.currentWordIndex,
      loopingLineIndex: state.isLooping ? state.activeLineIndex : null,
    );
  }

  @visibleForTesting
  void debugHandleVideoProgress(Duration position) =>
      _onVideoProgress(position);

  @visibleForTesting
  ValueListenable<TranscriptReaderProgress> get debugTranscriptReaderProgress =>
      _transcriptReaderSession.progress;

  Future<void> _handleOpenTranscriptReader({
    required String courseTitle,
    required String episodeTitle,
  }) async {
    final TranscriptReaderSnapshot snapshot =
        await buildTranscriptReaderSnapshot(
          subtitleLetterCase: ref
              .read(learningSettingsProvider)
              .subtitleLetterCase,
          courseTitle: courseTitle,
          episodeTitle: episodeTitle,
          lines: state.lines,
          activeLineIndex: state.activeLineIndex,
          currentWordIndex: state.currentWordIndex,
          loopingLineIndex: state.isLooping ? state.activeLineIndex : null,
          generatedMeanings: state.generatedWordDefinitions,
          dictionary: ref.read(offlineWordDictionaryProvider),
        );
    if (!mounted) return;
    final LearningSettingsState lookupSettings = ref.read(
      learningSettingsProvider,
    );
    final WordLookupService lookupService = ref.read(wordLookupServiceProvider);
    try {
      await _transcriptReaderSession.open(
        context: context,
        snapshot: snapshot,
        lookupWord:
            ({required String rawWord, required String contextSentence}) =>
                lookupService.lookupWord(
                  rawWord: rawWord,
                  contextSentence: contextSentence,
                  settings: lookupSettings,
                ),
        translateSentence: (String sentence) => lookupService.translateSentence(
          sentence: sentence,
          settings: lookupSettings,
        ),
        playFullTranscript: _handlePlayFullTranscript,
        toggleLineLoop: (int lineIndex) async {
          _handleLoopFromLine(lineIndex);
        },
      );
    } catch (_) {
      _showMessage('无法打开逐词全文，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<LibraryCourseData> courses = ref.watch(libraryCatalogProvider);
    final PlayerCourseLookupResult courseContext =
        resolvePlayerCourseForEpisode(
          courses: courses,
          episodeId: widget.episodeId,
        );
    final PlayerSubtitleLine activeLine = state.hasLines
        ? state.visibleLine ?? _emptySubtitleLine
        : _emptySubtitleLine;
    final PronunciationTargetSelection visibleAssessment =
        selectPronunciationTarget(
          state: state,
          videoSource: _videoAsset,
          videoReady: _videoReady,
          videoDuration: _videoDuration,
        );
    final LibraryCourseData? course = courseContext.course;
    final LibraryEpisodeItem? episode = courseContext.episode;
    final LearningSettingsState settings = ref.watch(learningSettingsProvider);
    final Set<String> savedVocabularyWords =
        SubtitleVocabularyHighlight.savedWordsFromBook(
          ref.watch(wordBookProvider),
        );
    final Set<String> keyVocabularyWords =
        SubtitleVocabularyHighlight.keyWordsFromGlossary(
          state.generatedWordDefinitions,
        );
    final bool canGenerateAiSubtitles =
        (_videoAsset?.isNotEmpty ?? false) && !_usingAiSubtitles;
    final LearningDashboardStats dashboard = ref.watch(
      learningDashboardProvider,
    );
    if (widget.autoOpenFullscreen &&
        !_didAutoOpenFullscreen &&
        !_isBootstrapping) {
      _didAutoOpenFullscreen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _handleOpenFullscreen(course?.episodes ?? const <LibraryEpisodeItem>[]);
      });
    }
    final Uri libraryDetailUri = Uri(
      path: SGRoute.library.route,
      queryParameters: <String, String>{
        'view': 'detail',
        if (course != null) 'courseId': course.id,
        'episodeId': widget.episodeId,
      },
    );

    return PadScaffold(
      showContinueLearning: false,
      currentDestination: AppNavDestination.library,
      showNavigation: false,
      topBar: PlayerTopBar(
        courseTitle: course?.title ?? '课程名称',
        episodeTitle: episode == null ? '第 01 集' : '第 ${episode.numberStr} 集',
        episodeName: episode?.title,
        streakText: '${dashboard.streakDays} Day Streak',
        onTranscriptPressed: state.hasLines
            ? () => unawaited(
                _handleOpenTranscriptReader(
                  courseTitle: course?.title ?? '课程名称',
                  episodeTitle: episode == null
                      ? '第 01 集'
                      : '第 ${episode.numberStr} 集',
                ),
              )
            : null,
        onLearningGuidePressed: () =>
            unawaited(GuideScreen.showLearningGuideDialog(context)),
        onStatsPressed: () {
          final String progressMessage = dashboard.checkedIn
              ? '今日打卡已完成'
              : '今日仍在学习中，继续加油';
          _showMessage(
            '今日学习 ${dashboard.todayStudyMinutes} 分钟 | ${dashboard.todaySentenceCount} 句 '
            '| ${dashboard.todayShadowingCount} 次跟读 | ${dashboard.todaySavedPhrases} 收藏 - $progressMessage',
          );
        },
        onBack: () {
          if (context.canPop()) {
            context.pop();
            return;
          }
          context.go(libraryDetailUri.toString());
        },
      ),
      body: AppLoadingOverlay(
        isLoading: _isBootstrapping,
        message: '正在打开课程...',
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 18, 28, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: <Widget>[
                          Expanded(
                            child: PlayerVideoPanel(
                              episodeId: widget.episodeId,
                              paintSubtitlesOnVideo: false,
                              line: activeLine,
                              isPlaying: state.isPlaying,
                              speed: state.speed,
                              subtitleMode: state.subtitleMode,
                              subtitleModes: state.availableSubtitleModes,
                              embeddedSubtitleTracks: _embeddedSubtitleTracks,
                              selectedEmbeddedSubtitleId:
                                  _selectedEmbeddedSubtitleId,
                              currentWordIndex: state.currentWordIndex,
                              highlightWords: settings.highlightWords,
                              subtitleLetterCase: settings.subtitleLetterCase,
                              fontSize: settings.fontSize,
                              fontScale: settings.fontScale,
                              onSelectFontSize: ref
                                  .read(learningSettingsProvider.notifier)
                                  .setFontSize,
                              subtitleWordHighlightStyle:
                                  settings.subtitleWordHighlightStyle,
                              subtitleWordHighlightBorderWidth:
                                  settings.subtitleWordHighlightBorderWidth,
                              savedVocabularyWords: savedVocabularyWords,
                              keyVocabularyWords: keyVocabularyWords,
                              isShadowing: state.isShadowing,
                              isLooping: state.isLooping,
                              isMuted: _isMuted,
                              volumeLevel: _volumeLevel,
                              onTogglePlaying: _handleTogglePlaying,
                              onPreviousLine: _handlePreviousLine,
                              onReplayLine: _handleReplayLine,
                              onNextLine: _handleNextLine,
                              onSeekBackward: () => _handleSeekBySeconds(-10),
                              onSeekForward: () => _handleSeekBySeconds(10),
                              activeIndex: state.activeLineIndex,
                              totalLines: state.lines.length,
                              onSelectLine: _goToLine,
                              onSeek: _handleSeek,
                              onSpeedSelected: _handleSpeedSelected,
                              onSelectSubtitleMode: _handleSetSubtitleMode,
                              onSelectSubtitleLetterCase: _usingAiSubtitles
                                  ? ref
                                        .read(learningSettingsProvider.notifier)
                                        .setSubtitleLetterCase
                                  : null,
                              onSelectEmbeddedSubtitle:
                                  _handleSelectEmbeddedSubtitle,
                              onToggleShadowing: _handleToggleShadowing,
                              onToggleLoop: _handleToggleLoop,
                              onToggleMuted: _handleToggleMuted,
                              onVolumeChanged: _handleVolumeChanged,
                              onSubtitleLookupOpen: _stopVideo,
                              onAssessVisibleLine:
                                  visibleAssessment.target == null
                                  ? null
                                  : _handleAssessVisibleLine,
                              assessmentUnavailableReason:
                                  visibleAssessment.unavailableReason,
                              onCollectWord: (String word) =>
                                  _handleCollectWord(word, courseContext),
                              onCollectWordAtTime: (String word, String time) =>
                                  _handleCollectWord(word, courseContext, time),
                              onFavoriteWord: _handleFavoriteWord,
                              onPronounce: _stopVideo,
                              onToggleFullscreen: () => _handleOpenFullscreen(
                                course?.episodes ??
                                    const <LibraryEpisodeItem>[],
                              ),
                              videoSurface: _isFullscreenOpen
                                  ? null
                                  : _buildVideoSurface(),
                              videoAspectRatio: _videoAspectRatio,
                              videoReady: _videoReady,
                              videoLoading: _videoLoading,
                              videoDuration: _videoDuration,
                              videoPosition: _videoPosition,
                              videoErrorText: _videoErrorText,
                              showAiGenerateSubtitles: canGenerateAiSubtitles,
                              onGenerateAiSubtitles: _generatingAiSubtitles
                                  ? null
                                  : _handleGenerateAiSubtitles,
                            ),
                          ),
                          const SizedBox(height: 12),
                          PlayerEpisodeStrip(
                            episodes:
                                course?.episodes ??
                                const <LibraryEpisodeItem>[],
                            activeEpisodeId: widget.episodeId,
                            onOpenEpisode: _openEpisode,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 22),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x120F172A),
                              blurRadius: 20,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: <Widget>[
                            Expanded(
                              child: state.hasLines
                                  ? PlayerTranscriptPanel(
                                      episodeId: widget.episodeId,
                                      lines: state.lines,
                                      activeIndex: state.activeLineIndex,
                                      timelineFollowEpoch:
                                          state.timelineFollowEpoch,
                                      subtitleMode: state.subtitleMode,
                                      currentWordIndex: state.currentWordIndex,
                                      fontScale: settings.fontScale,
                                      highlightWords: settings.highlightWords,
                                      subtitleLetterCase:
                                          settings.subtitleLetterCase,
                                      subtitleWordHighlightStyle:
                                          settings.subtitleWordHighlightStyle,
                                      subtitleWordHighlightBorderWidth: settings
                                          .subtitleWordHighlightBorderWidth,
                                      fragmentsBySentenceStartMs:
                                          _usingAsrSentences
                                          ? _asrFragmentsBySentenceStartMs
                                          : const <
                                              int,
                                              List<PlayerSubtitleLine>
                                            >{},
                                      savedVocabularyWords:
                                          savedVocabularyWords,
                                      keyVocabularyWords: keyVocabularyWords,
                                      onTapLine: _goToLine,
                                      onCollectWord: (String word) =>
                                          _handleCollectWord(
                                            word,
                                            courseContext,
                                          ),
                                      onCollectWordAtTime:
                                          (String word, String time) =>
                                              _handleCollectWord(
                                                word,
                                                courseContext,
                                                time,
                                              ),
                                      onFavoriteWord: _handleFavoriteWord,
                                      onBookmarkLine: (int index) =>
                                          _handleBookmarkLine(
                                            index,
                                            courseContext,
                                          ),
                                      onLoopFromLine: _handleLoopFromLine,
                                      onDictationLine: _handleDictationLine,
                                      onAiExplain: _handleAiExplain,
                                      onAssessLine: _handleAssessLine,
                                      pronunciationUnavailableReasonForLine:
                                          _pronunciationUnavailableReasonForLine,
                                      loopingLineIndex: state.isLooping
                                          ? state.activeLineIndex
                                          : null,
                                      isPlaying: state.isPlaying,
                                      onTogglePlaying: _handleTogglePlaying,
                                      onPronounce: _stopVideo,
                                      onRegenerateAiSubtitles:
                                          !_generatingAiSubtitles
                                          ? () {
                                              unawaited(
                                                _restartEnglishFillFromChineseAndOcr(),
                                              );
                                            }
                                          : null,
                                      onDeleteAiSubtitles: _usingAiSubtitles
                                          ? _handleDeleteAiSubtitles
                                          : null,
                                      onRegenerateAiLine: _usingAiSubtitles
                                          ? _handleRegenerateAiLine
                                          : null,
                                      onEditEnglishLine: _editEnglishLine,
                                      onEditSubtitleLine: _editSubtitleLine,
                                      onEditLineNote: _editLineNote,
                                      lineNotesByStartMs: _lineNotesByStartMs,
                                      bilingualPipelineLabel:
                                          _bilingualPipelineLabel,
                                      showAiCompleteButton:
                                          _bilingualShowAiComplete,
                                      onAiComplete: _bilingualShowAiComplete
                                          ? _handleAiCompleteSubtitles
                                          : null,
                                      onCancelBilingualPipeline:
                                          _bilingualPhase ==
                                                  BilingualPipelinePhase
                                                      .ocrRunning ||
                                              _bilingualPhase ==
                                                  BilingualPipelinePhase.ocrSlow
                                          ? _handleCancelBilingualPipeline
                                          : null,
                                    )
                                  : canGenerateAiSubtitles
                                  ? PlayerSubtitleList(
                                      episodeId: widget.episodeId,
                                      lines: const <PlayerSubtitleLine>[],
                                      activeIndex: 0,
                                      subtitleMode: '隐藏',
                                      currentWordIndex: 0,
                                      fontScale: settings.fontScale,
                                      highlightWords: settings.highlightWords,
                                      subtitleLetterCase:
                                          settings.subtitleLetterCase,
                                      savedVocabularyWords:
                                          savedVocabularyWords,
                                      keyVocabularyWords: keyVocabularyWords,
                                      onTapLine: (_) {},
                                      onCollectWord: (_) {},
                                      onBookmarkLine: (_) {},
                                      onLoopFromLine: (_) {},
                                      onDictationLine: (_) {},
                                      onAiExplain: (_) {},
                                      onPronounce: _stopVideo,
                                      showAiGenerateSubtitles: true,
                                      generatingAiSubtitles:
                                          _generatingAiSubtitles,
                                      aiSubtitleProgressValue:
                                          _aiSubtitleProgressValue,
                                      aiSubtitleProgressText:
                                          _aiSubtitleProgressText,
                                      aiSubtitlePreviewText:
                                          _aiSubtitlePreviewText,
                                      aiSubtitleErrorText: _aiSubtitleErrorText,
                                      onGenerateAiSubtitles:
                                          _handleGenerateAiSubtitles,
                                      bilingualPipelineLabel:
                                          _bilingualPipelineLabel,
                                      showAiCompleteButton:
                                          _bilingualShowAiComplete,
                                      onAiComplete: _bilingualShowAiComplete
                                          ? _handleAiCompleteSubtitles
                                          : null,
                                      onCancelBilingualPipeline:
                                          _bilingualPhase ==
                                                  BilingualPipelinePhase
                                                      .ocrRunning ||
                                              _bilingualPhase ==
                                                  BilingualPipelinePhase.ocrSlow
                                          ? _handleCancelBilingualPipeline
                                          : null,
                                    )
                                  : const Center(
                                      child: Text(
                                        '当前剧集没有可用字幕或视频',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF5F6368),
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openEpisode(LibraryEpisodeItem episode) {
    if (episode.id == widget.episodeId) {
      return;
    }
    context.goNamed(
      SGRoute.player.name,
      pathParameters: <String, String>{'episodeId': episode.id},
    );
  }

  void _handleSpeedSelected(String nextSpeed) {
    setState(() {
      state.selectSpeed(nextSpeed);
    });
    _applyPlaybackMode();
  }

  void _handleSetSubtitleMode(String mode) {
    final String normalized = SubtitleDisplayMode.normalize(mode);
    setState(() {
      state.setSubtitleMode(normalized);
      _selectedEmbeddedSubtitleId = null;
    });
    if (normalized != SubtitleDisplayMode.hidden) {
      ref.read(learningSettingsProvider.notifier).setSubtitleMode(normalized);
    }
    final Player? player = _videoPlayer;
    if (player != null) {
      unawaited(suppressPlayerSoftSubtitles(player));
    }
    _applyPlaybackMode();
  }

  void _handleSelectEmbeddedSubtitle(SubtitleTrack? track) {
    setState(() {
      _selectedEmbeddedSubtitleId = null;
    });
    final Player? player = _videoPlayer;
    if (player != null) {
      unawaited(suppressPlayerSoftSubtitles(player));
    }
    if (track != null) {
      unawaited(_loadEmbeddedSubtitleReference(<SubtitleTrack>[track]));
    }
  }

  void _handleTogglePlaying() {
    if (_pronunciationDialogActive) return;
    setState(() {
      state.togglePlaying(
        allowWithoutLines:
            (_videoAsset?.isNotEmpty ?? false) && _videoErrorText == null,
      );
    });
    _applyPlaybackMode();
    if (state.isPlaying) {
      _lastTrackedVideoPosition = _currentVideoPosition();
      _recordCurrentSentenceStudy();
      _recordCurrentLineWords();
    }
  }

  void _handleSystemPlay() {
    if (!state.isPlaying) {
      _handleTogglePlaying();
    }
  }

  void _handleSystemPause() {
    if (state.isPlaying) {
      _handleTogglePlaying();
    }
  }

  void _handlePreviousLine() {
    setState(state.previousLine);
    _syncTranscriptReader();
    _seekToActiveLine();
    _recordCurrentSentenceStudy();
    _lastTrackedVideoPosition = _currentVideoPosition();
    _applyPlaybackMode();
  }

  void _handleReplayLine() {
    _goToLine(state.activeLineIndex);
    _showMessage('已重播当前句');
  }

  void _handleNextLine() {
    setState(state.nextLine);
    _syncTranscriptReader();
    _seekToActiveLine();
    _recordCurrentSentenceStudy();
    _lastTrackedVideoPosition = _currentVideoPosition();
    _applyPlaybackMode();
  }

  void _handleToggleShadowing() {
    setState(() {
      state.isShadowing = true;
      if (!state.pauseAtSentenceEnd) {
        state.togglePauseAtSentenceEnd();
      }
    });
    ref
        .read(learningActivityProvider.notifier)
        .recordShadowingToggle(enabled: true);
    _showMessage('已开启跟读：句末暂停，可点麦克风录音对照');
  }

  void _handleToggleLoop() {
    setState(state.toggleLoop);
    _syncTranscriptReader();
    _showMessage(state.isLooping ? '已开启单句循环' : '已关闭单句循环');
    if (state.isLooping && state.hasLines) {
      _seekToActiveLine();
    }
  }

  void _handleToggleMuted() {
    final double nextVolume = _isMuted ? 1 : 0;
    _handleVolumeChanged(nextVolume);
    _showMessage(_isMuted ? '已静音' : '已恢复声音');
  }

  Future<void> _handleGenerateAiSubtitles({
    bool forceRegenerate = false,
  }) async {
    if (_generatingAiSubtitles) {
      return;
    }
    final String? videoPath = _videoAsset;
    if (videoPath == null || videoPath.isEmpty) {
      _showMessage('当前视频不可用');
      return;
    }
    if (!forceRegenerate &&
        state.hasLines &&
        _linesMissingEnglish(state.lines)) {
      await _restartEnglishFillFromChineseAndOcr();
      return;
    }
    await _bilingualPipeline?.cancel();
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    final bool showProgressDialog = state.hasLines;
    setState(() {
      _generatingAiSubtitles = true;
      _aiSubtitleProgressValue = null;
      _aiSubtitleProgressText = '正在检查官方字幕...';
      _aiSubtitlePreviewText = null;
      _aiSubtitleErrorText = null;
      _bilingualPipelineLabel = null;
      _bilingualShowAiComplete = false;
      _bilingualPhase = BilingualPipelinePhase.cancelled;
    });
    final ValueNotifier<AsrSubtitleProgress> dialogProgress =
        ValueNotifier<AsrSubtitleProgress>(
          const AsrSubtitleProgress(completedChunks: 0, totalChunks: 0),
        );
    final Future<void>? progressDialogFuture = showProgressDialog
        ? showAiSubtitleGenerationProgressDialog(
            context: context,
            progress: dialogProgress,
          )
        : null;
    final AsrSubtitleCancellationToken cancellationToken =
        AsrSubtitleCancellationToken();
    _aiSubtitleCancellationToken = cancellationToken;
    try {
      final List<PlayerSubtitleLine> referenceLines =
          await _ensureOfficialReferenceSubtitles();
      final bool hasOfficialEnglish = usableReferenceSubtitles(
        referenceLines,
      ).isNotEmpty;
      if (!hasOfficialEnglish) {
        final String? configError = describeAsrConfigurationError(settings);
        if (configError != null) {
          setState(() => _aiSubtitleErrorText = configError);
          _showMessage(configError);
          return;
        }
      }
      final String asrVideoPath = await _resolveAsrVideoPath(videoPath);
      if (!forceRegenerate && !_usingAiSubtitles) {
        final String? cached = await const AsrSubtitleCache().read(
          episodeId: widget.episodeId,
          videoPath: videoPath,
          settings: settings,
          referenceSignature: referenceLines.isEmpty
              ? null
              : subtitleReferenceSignature(referenceLines),
        );
        if (cached != null) {
          final List<PlayerSubtitleLine> lines = parseSubtitleLines(cached);
          if (lines.isNotEmpty && mounted) {
            setState(() {
              state.loadLines(
                lines,
                wordDefinitions: parseSubtitleGlossary(cached),
              );
              _usingAiSubtitles = true;
            });
            _showMessage('已切换到 AI 字幕');
            return;
          }
        }
      }
      const AsrSubtitleJobRunner runner = AsrSubtitleJobRunner();
      final String raw = await runner.run(
        episodeId: widget.episodeId,
        videoPath: asrVideoPath,
        settings: settings,
        referenceSubtitleLines: referenceLines,
        forceRegenerate: forceRegenerate,
        cancellationToken: cancellationToken,
        onProgress: (AsrSubtitleProgress progress) {
          dialogProgress.value = progress;
          if (!mounted) {
            return;
          }
          setState(() {
            _aiSubtitleProgressValue = progress.value;
            _aiSubtitleProgressText = progress.label;
            _aiSubtitlePreviewText = progress.previewText;
          });
        },
      );
      final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
      if (!mounted) {
        return;
      }
      setState(() {
        state.loadLines(lines, wordDefinitions: parseSubtitleGlossary(raw));
        _usingAiSubtitles = true;
      });
      final SubtitleReferenceReview review = reviewGeneratedSubtitles(
        generated: lines,
        reference: referenceLines,
      );
      final AsrSubtitleRepairSummary repairSummary = await runner
          .readRepairSummary(
            episodeId: widget.episodeId,
            videoPath: videoPath,
            settings: settings,
          );
      final String? warning = subtitleGenerationWarning(raw);
      if (warning != null && warning.contains('官方')) {
        _showMessage(repairSummary.appendTo('已使用官方字幕生成跟读字幕'));
      } else if (warning != null) {
        _showMessage(repairSummary.appendTo('AI 字幕已生成；$warning'));
      } else if (subtitleReferenceSignature(referenceLines).isNotEmpty) {
        _showMessage(repairSummary.appendTo('AI 字幕已生成，已按原字幕校准'));
      } else if (review.comparedLines == 0) {
        _showMessage(repairSummary.appendTo('AI 字幕已生成（Whisper/云端识别）'));
      } else if (review.differentLines == 0) {
        _showMessage(repairSummary.appendTo('AI 字幕已生成，已通过参考字幕校对'));
      } else {
        _showMessage(repairSummary.appendTo('AI 字幕已生成'));
      }
    } catch (error) {
      if (cancellationToken.isCancelled) return;
      if (mounted) {
        final String message = humanizeAsrSubtitleError(error);
        setState(() {
          _aiSubtitleErrorText = message;
        });
        _showMessage('AI 字幕生成失败：$message');
      }
    } finally {
      if (identical(_aiSubtitleCancellationToken, cancellationToken)) {
        _aiSubtitleCancellationToken = null;
      }
      if (progressDialogFuture != null && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        await progressDialogFuture;
      }
      dialogProgress.dispose();
      if (mounted) {
        setState(() {
          _generatingAiSubtitles = false;
          _aiSubtitleProgressValue = null;
          _aiSubtitleProgressText = null;
          _aiSubtitlePreviewText = null;
        });
      }
    }
  }

  Future<List<PlayerSubtitleLine>> _ensureOfficialReferenceSubtitles() async {
    final List<PlayerSubtitleLine> existing = usableReferenceSubtitles(
      _referenceSubtitleLines,
    );
    if (existing.isNotEmpty) {
      return existing;
    }
    final PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: widget.episodeId,
    );
    final String? query =
        bilibiliSourceForEpisode(
          course: resource.course,
          episode: resource.episode,
          videoAsset: resource.videoAsset ?? _videoAsset,
        ) ??
        _bilibiliRecoverSource(resource.episode?.videoAsset ?? '') ??
        _bilibiliRecoverSource(_videoAsset ?? '') ??
        _bilibiliRecoverSource(resource.course?.description ?? '');
    if (query == null ||
        query.isEmpty ||
        (!BilibiliImport.isWatchPageUrl(query) &&
            !BilibiliImport.looksLikeBilibiliInput(query)) ||
        (BilibiliImport.isShortLink(query) &&
            BilibiliImport.extractIds(query) == null)) {
      return existing;
    }
    if (mounted) {
      setState(() {
        _aiSubtitleProgressText = '正在拉取 B 站官方字幕…';
        _aiSubtitlePreviewText = '有官方字幕则跳过 Whisper';
      });
    }
    try {
      final Map<String, String?> tracks =
          await BilibiliImportService.withCookie(
            ref.read(learningSettingsProvider).resolvedBilibiliCookieHeader,
          ).fetchOfficialSubtitleTracks(query);
      final String? enPath = tracks['en'];
      final String? zhPath = tracks['zh'];
      final bool hasEn = enPath != null && enPath.isNotEmpty;
      final bool hasZh = zhPath != null && zhPath.isNotEmpty;
      if (!hasEn && !hasZh) {
        return existing;
      }
      final LibraryCourseData? course = resource.course;
      final LibraryEpisodeItem? episode = resource.episode;
      if (course != null && episode != null) {
        unawaited(
          ref
              .read(libraryCatalogProvider.notifier)
              .updateEpisodeLocalMedia(
                courseId: course.id,
                episodeId: episode.id,
                enSubtitlePath: hasEn ? enPath : null,
                zhSubtitlePath: hasZh ? zhPath : null,
              ),
        );
      }
      if (!hasEn) {
        return existing;
      }
      final List<PlayerSubtitleLine> englishLines = await loadSubtitleLines(
        enPath,
      );
      List<PlayerSubtitleLine> chineseLines = const <PlayerSubtitleLine>[];
      if (hasZh) {
        chineseLines = await loadSubtitleLines(zhPath);
      }
      final List<PlayerSubtitleLine> merged = mergeSubtitleLines(
        englishLines: englishLines,
        chineseLines: chineseLines,
      );
      final List<PlayerSubtitleLine> usable = usableReferenceSubtitles(merged);
      if (usable.isEmpty) {
        return existing;
      }
      if (mounted) {
        setState(() => _referenceSubtitleLines = usable);
      }
      return usable;
    } catch (_) {
      return existing;
    }
  }

  Future<void> _restartEnglishFillFromChineseAndOcr() async {
    if (!mounted) {
      return;
    }
    _englishFillCancellationToken?.cancel();
    _englishFillInFlight = false;
    await _bilingualPipeline?.cancel();
    if (!mounted) {
      return;
    }
    await deletePersistedBilingualSubtitleFiles(episodeId: widget.episodeId);
    if (state.hasLines) {
      final List<PlayerSubtitleLine> cleared = state.lines
          .map((PlayerSubtitleLine line) {
            if (!looksChinese(line.chinese)) {
              return line;
            }
            return PlayerSubtitleLine(
              startTime: line.startTime,
              english: '',
              chinese: line.chinese,
              startMs: line.startMs,
              endMs: line.endMs,
            );
          })
          .toList(growable: false);
      setState(() {
        state.replaceLines(
          cleared,
          preferredSubtitleMode: SubtitleDisplayMode.bilingual,
        );
        _bilingualPhase = BilingualPipelinePhase.asrProofreading;
        _bilingualPipelineLabel = '正在用语音对齐英文…';
        _bilingualShowAiComplete = false;
        _usingAiSubtitles = false;
        _usingAsrSentences = false;
        _asrFragmentsBySentenceStartMs =
            const <int, List<PlayerSubtitleLine>>{};
        _aiSubtitleErrorText = null;
      });
    } else {
      setState(() {
        _bilingualPhase = BilingualPipelinePhase.asrProofreading;
        _bilingualPipelineLabel = '正在用语音对齐英文…';
        _bilingualShowAiComplete = false;
        _usingAiSubtitles = false;
        _usingAsrSentences = false;
        _asrFragmentsBySentenceStartMs =
            const <int, List<PlayerSubtitleLine>>{};
        _aiSubtitleErrorText = null;
      });
    }
    final PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: widget.episodeId,
    );
    unawaited(
      enqueueSubtitleCompletionForEpisode(
        episodeId: widget.episodeId,
        videoPath: _videoAsset ?? resource.videoAsset,
        zhSubtitlePath: resource.chineseSubtitleAsset,
        enSubtitlePath: null,
        sourceUrl: resource.episode?.sourceUrl,
        force: true,
      ),
    );
    _showMessage('正在按语音重新生成字幕（与语音不一致时以 ASR 为准）');
    unawaited(() async {
      await _maybeStartBilingualPipeline();
      try {
        await _bilingualPipeline?.proofreadEnglishWithAsr(force: true);
      } catch (_) {}
    }());
  }

  Future<void> _handleRegenerateAiSubtitles() async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('重新生成 AI 字幕？'),
            content: const Text(
              '有官方英文字幕时仍优先使用官方字幕；没有才会调用 Whisper/云端识别。生成失败时会保留当前字幕。',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('重新生成'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    _showMessage('正在重新生成 AI 字幕，当前字幕会保留到生成成功。');
    await _handleGenerateAiSubtitles(forceRegenerate: true);
  }

  Future<void> _handleRegenerateAiLine(int index) async {
    if (_generatingAiSubtitles || index < 0 || index >= state.lines.length) {
      _showMessage('AI 字幕正在处理中，请稍后再试');
      return;
    }
    final String? videoPath = _videoAsset;
    if (videoPath == null || videoPath.isEmpty) {
      _showMessage('当前视频不可用');
      return;
    }
    _showMessage('正在重新生成当前句，失败时会保留原句。');
    try {
      final String asrVideoPath = await _resolveAsrVideoPath(videoPath);
      const AsrSubtitleJobRunner runner = AsrSubtitleJobRunner();
      final LearningSettingsState settings = ref.read(learningSettingsProvider);
      final String referenceSignature = subtitleReferenceSignature(
        _referenceSubtitleLines,
      );
      final AsrRegeneratedLineResult result = await runner.regenerateLine(
        episodeId: widget.episodeId,
        videoPath: asrVideoPath,
        settings: settings,
        currentLines: List<PlayerSubtitleLine>.of(state.lines),
        lineIndex: index,
        referenceSignature: referenceSignature.isEmpty
            ? null
            : referenceSignature,
      );
      if (!mounted || index >= state.lines.length) return;
      setState(() {
        state.lines[index] = result.line;
        state.generatedWordDefinitions = parseSubtitleGlossary(result.raw);
      });
      _syncTranscriptReader();
      _showMessage('当前句已重新生成并保存');
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<void> _handleDeleteAiSubtitles() async {
    final String? videoPath = _videoAsset;
    if (videoPath == null || videoPath.isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }
    await _loadEpisodeResources();
    _showMessage('已切回原始字幕');
  }

  void _handleVolumeChanged(double nextVolume) {
    final double safeVolume = nextVolume.clamp(0.0, 1.0);
    setState(() {
      _volumeLevel = safeVolume;
      _isMuted = safeVolume <= 0.001;
    });
    if (_videoPlayer != null) {
      unawaited(_videoPlayer!.setVolume(safeVolume * 100));
    }
  }

  void _handleBookmarkLine(int index, PlayerCourseLookupResult courseContext) {
    final PlayerSubtitleLine line = state.lines[index];
    final LibraryCourseData? course = courseContext.course;
    final LibraryEpisodeItem? episode = courseContext.episode;
    final bool added = ref
        .read(phraseBookProvider.notifier)
        .addPhraseIfMissing(
          english: line.english,
          chinese: line.chinese,
          course: course?.title ?? '课程',
          episode: '第 ${episode?.numberStr ?? '01'} 集',
          time: line.startTime,
          courseId: course?.id,
          episodeId: episode?.id,
          endTime: _formatTimestamp(line.endMs),
        );
    if (added) {
      ref.read(learningActivityProvider.notifier).recordPhraseSaved();
    }
    _showMessage(added ? '成功收藏当前句型到短语库！' : '该例句已经在您的短语库中！');
  }

  void _handleCollectWord(
    String word,
    PlayerCourseLookupResult courseContext, [
    String? contextTime,
  ]) {
    final PlayerSubtitleLine line = contextTime == null
        ? state.activeLine
        : state.lines.firstWhere(
            (PlayerSubtitleLine item) => item.startTime == contextTime,
            orElse: () => state.activeLine,
          );
    final LibraryCourseData? course = courseContext.course;
    final LibraryEpisodeItem? episode = courseContext.episode;
    final bool added = ref
        .read(phraseBookProvider.notifier)
        .addPhraseIfMissing(
          english: line.english,
          chinese: '${line.chinese} (生词: $word)',
          course: course?.title ?? '课程',
          episode: '第 ${episode?.numberStr ?? '01'} 集',
          time: line.startTime,
          courseId: course?.id,
          episodeId: episode?.id,
          endTime: _formatTimestamp(line.endMs),
        );
    if (added) {
      ref.read(learningActivityProvider.notifier).recordPhraseSaved();
    }
    _showMessage(added ? '成功收藏单词 "$word" 到短语库！' : '该例句已经在您的短语库中！');
  }

  void _handleFavoriteWord(String word, [String? definitionCn]) {
    if (!state.hasLines) return;
    final PlayerSubtitleLine line = state.activeLine;
    final PlayerCourseLookupResult courseContext =
        resolvePlayerCourseForEpisode(
          courses: ref.read(libraryCatalogProvider),
          episodeId: widget.episodeId,
        );
    final LibraryEpisodeItem? episode = courseContext.episode;
    final String lexeme = normalizeLexeme(word);
    final String? fromCard = definitionCn?.trim();
    final bool added = ref
        .read(wordBookProvider.notifier)
        .addFavoriteWord(
          rawWord: lexeme,
          episodeId: widget.episodeId,
          videoFileName: episode?.videoAsset
              ?.replaceAll(r'\', '/')
              .split('/')
              .last,
          course: courseContext.course?.title ?? '课程',
          episode: '第 ${episode?.numberStr ?? '01'} 集',
          time: line.startTime,
          lineKey: '${line.startMs}-${line.endMs}',
          sentence: line.english,
          chinese: line.chinese,
          generatedDefinition:
              (fromCard != null && fromCard.isNotEmpty)
              ? fromCard
              : (state.generatedWordDefinitions[normalizeWord(lexeme)] ??
                    state.generatedWordDefinitions[lexeme]),
        );
    _showMessage(
      added
          ? (lexeme.contains(' ') ? '已收藏词组到词卡「$lexeme」' : '已收藏单词到词卡「$lexeme」')
          : '未能收藏，请选择英文单词或词组。',
    );
  }

  void _recordPlayDuration({required int durationMs}) {
    if (durationMs <= 0) {
      return;
    }
    ref
        .read(learningActivityProvider.notifier)
        .recordPlayDuration(duration: Duration(milliseconds: durationMs));
  }

  void _recordCurrentSentenceStudy() {
    if (!state.hasLines) {
      return;
    }
    final PlayerSubtitleLine line = state.activeLine;
    final String sentenceKey = _makeSentenceKey(line);
    ref
        .read(learningActivityProvider.notifier)
        .recordSentenceStudy(sentenceKey: sentenceKey);
  }

  void _recordCurrentLineWords() {
    if (!state.hasLines) return;
    final PlayerCourseLookupResult context = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: widget.episodeId,
    );
    final LibraryEpisodeItem? episode = context.episode;
    final PlayerSubtitleLine line = state.activeLine;
    ref
        .read(wordBookProvider.notifier)
        .recordLine(
          english: line.english,
          episodeId: widget.episodeId,
          videoFileName: episode?.videoAsset
              ?.replaceAll(r'\', '/')
              .split('/')
              .last,
          course: context.course?.title ?? '课程',
          episode: '第 ${episode?.numberStr ?? '01'} 集',
          time: line.startTime,
          lineKey: '${line.startMs}-${line.endMs}',
          chinese: line.chinese,
          generatedDefinitions: state.generatedWordDefinitions,
        );
  }

  void _trackPlayProgress(Duration position) {
    final int diff =
        position.inMilliseconds - _lastTrackedVideoPosition.inMilliseconds;
    _lastTrackedVideoPosition = position;
    _recordPlayDuration(durationMs: diff);
  }

  Duration _currentVideoPosition() {
    if (state.hasLines) {
      return Duration(milliseconds: state.lines[state.activeLineIndex].startMs);
    }
    return _videoPosition;
  }

  String _makeSentenceKey(PlayerSubtitleLine line) {
    return '${widget.episodeId}-${line.startMs}-${line.endMs}-${line.english}';
  }

  Future<void> _handlePlayFullTranscript() async {
    if (!state.hasLines || _videoPlayer == null || !_videoReady) {
      throw StateError('Original video playback is unavailable');
    }
    setState(() {
      if (state.isLooping) state.toggleLoop();
      state
        ..selectLine(0)
        ..isPlaying = true;
    });
    _syncTranscriptReader();
    _seekToActiveLine();
    _lastTrackedVideoPosition = _currentVideoPosition();
    _applyPlaybackMode();
  }

  void _handleLoopFromLine(int index) {
    late bool enabled;
    setState(() {
      enabled = state.toggleLineLoopAt(index);
    });
    _syncTranscriptReader();
    if (enabled) {
      _seekToActiveLine();
    }
    _applyPlaybackMode();
    _showMessage(enabled ? '已开启单句循环' : '已关闭单句循环');
  }

  void _handleDictationLine(int index) {
    setState(() {
      state.selectLine(index);
    });
    _seekToActiveLine();
    _showMessage('已加入听写练习');
  }

  void _handleAiExplain(int index) {
    if (index < 0 || index >= state.lines.length) {
      return;
    }
    final PlayerSubtitleLine line = state.lines[index];
    setState(() {
      state.selectLine(index);
    });
    unawaited(
      showAiGrammarAnalysisSheet(
        context,
        english: line.english,
        chinese: line.chinese,
      ),
    );
  }

  Future<void> _handleOpenFullscreen(List<LibraryEpisodeItem> episodes) async {
    final Widget? fullscreenVideoSurface = _buildVideoSurface();
    final bool highlightWords = ref
        .read(learningSettingsProvider)
        .highlightWords;
    final String subtitleWordHighlightStyle = ref
        .read(learningSettingsProvider)
        .subtitleWordHighlightStyle;
    final double subtitleWordHighlightBorderWidth = ref
        .read(learningSettingsProvider)
        .subtitleWordHighlightBorderWidth;
    final Set<String> savedVocabularyWords =
        SubtitleVocabularyHighlight.savedWordsFromBook(
          ref.read(wordBookProvider),
        );
    final Set<String> keyVocabularyWords =
        SubtitleVocabularyHighlight.keyWordsFromGlossary(
          state.generatedWordDefinitions,
        );
    final PlayerCourseLookupResult courseContext =
        resolvePlayerCourseForEpisode(
          courses: ref.read(libraryCatalogProvider),
          episodeId: widget.episodeId,
        );
    String? nextEpisodeId;
    setState(() {
      _isFullscreenOpen = true;
    });
    try {
      nextEpisodeId = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (BuildContext context) => PlayerFullscreenVideoScreen(
            playerState: state,
            highlightWords: highlightWords,
            subtitleLetterCase: ref
                .read(learningSettingsProvider)
                .subtitleLetterCase,
            subtitleWordHighlightStyle: subtitleWordHighlightStyle,
            subtitleWordHighlightBorderWidth: subtitleWordHighlightBorderWidth,
            savedVocabularyWords: savedVocabularyWords,
            keyVocabularyWords: keyVocabularyWords,
            isMuted: _isMuted,
            volumeLevel: _volumeLevel,
            onTogglePlaying: _handleTogglePlaying,
            onPreviousLine: _handlePreviousLine,
            onReplayLine: _handleReplayLine,
            onNextLine: _handleNextLine,
            onSeekBackward: () => _handleSeekBySeconds(-10),
            onSeekForward: () => _handleSeekBySeconds(10),
            onSelectLine: _goToLine,
            onSeek: _handleSeek,
            onSpeedSelected: _handleSpeedSelected,
            onSelectSubtitleMode: _handleSetSubtitleMode,
            onSelectSubtitleLetterCase: _usingAiSubtitles
                ? ref
                      .read(learningSettingsProvider.notifier)
                      .setSubtitleLetterCase
                : null,
            embeddedSubtitleTracks: _embeddedSubtitleTracks,
            selectedEmbeddedSubtitleId: _selectedEmbeddedSubtitleId,
            onSelectEmbeddedSubtitle: _handleSelectEmbeddedSubtitle,
            onToggleShadowing: _handleToggleShadowing,
            onToggleLoop: _handleToggleLoop,
            onToggleMuted: _handleToggleMuted,
            onVolumeChanged: _handleVolumeChanged,
            onSubtitleLookupOpen: _stopVideo,
            onCollectWord: (String word) =>
                _handleCollectWord(word, courseContext),
            onCollectWordAtTime: (String word, String time) =>
                _handleCollectWord(word, courseContext, time),
            onFavoriteWord: _handleFavoriteWord,
            onBookmarkLine: (int index) =>
                _handleBookmarkLine(index, courseContext),
            onLoopFromLine: _handleLoopFromLine,
            onDictationLine: _handleDictationLine,
            onAiExplain: _handleAiExplain,
            onRegenerateAiLine: _usingAiSubtitles
                ? _handleRegenerateAiLine
                : null,
            onEditEnglishLine: _editEnglishLine,
            onEditSubtitleLine: _editSubtitleLine,
            onEditLineNote: _editLineNote,
            lineNotesByStartMs: _lineNotesByStartMs,
            fontScale: ref.read(learningSettingsProvider).fontScale,
            fontSize: ref.read(learningSettingsProvider).fontSize,
            onSelectFontSize: ref
                .read(learningSettingsProvider.notifier)
                .setFontSize,
            episodes: episodes,
            activeEpisodeId: widget.episodeId,
            videoSource: _videoAsset,
            onAssessTarget: _openPronunciationAssessment,
            onExit: () => Navigator.of(context).maybePop(),
            videoSurface: fullscreenVideoSurface,
            videoAspectRatio: _videoAspectRatio,
            videoReady: _videoReady,
            videoLoading: _videoLoading,
            videoDuration: _videoDuration,
            videoErrorText: _videoErrorText,
            paintSubtitlesOnVideo: false,
          ),
        ),
      );
    } finally {
      if (mounted &&
          (nextEpisodeId == null || nextEpisodeId == widget.episodeId)) {
        setState(() {
          _isFullscreenOpen = false;
        });
      }
    }
    if (!mounted ||
        nextEpisodeId == null ||
        nextEpisodeId == widget.episodeId) {
      return;
    }
    await _videoPlayer?.pause();
    if (!mounted) {
      return;
    }
    context.goNamed(
      SGRoute.player.name,
      pathParameters: <String, String>{'episodeId': nextEpisodeId},
      queryParameters: const <String, String>{'fullscreen': '1'},
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatTimestamp(int milliseconds) {
    final int totalSeconds = milliseconds ~/ 1000;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Widget? _buildVideoSurface() {
    final VideoController? controller = _videoController;
    if (controller == null) {
      return null;
    }
    return Video(
      controller: controller,
      controls: null,
      subtitleViewConfiguration: kHiddenSubtitleViewConfiguration,
      pauseUponEnteringBackgroundMode: false,
      filterQuality: FilterQuality.medium,
    );
  }
}

const PlayerSubtitleLine _emptySubtitleLine = PlayerSubtitleLine(
  startTime: '00:00',
  english: '',
  chinese: '',
  startMs: 0,
  endMs: 0,
);
