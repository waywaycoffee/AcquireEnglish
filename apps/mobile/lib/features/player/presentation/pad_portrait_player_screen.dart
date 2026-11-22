import '../../words/presentation/vocabulary_placement_provider.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../config/theme/theme_logic.dart';
import '../../../router/app_router.dart';
import '../../daily_path/domain/course_plan.dart';
import '../../daily_path/data/course_unit_progress.dart';
import '../../daily_path/presentation/enable_course_mode_sheet.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import '../../home/presentation/learning_dashboard_provider.dart';
import '../../import_course/data/bilibili_episode_prepare.dart';
import '../../import_course/data/bilibili_import_service.dart';
import '../../import_course/data/bilibili_multipage.dart';
import '../../import_course/data/netdisk_local_download.dart';
import '../../import_course/data/subtitle_source_policy.dart';
import '../../import_course/domain/bilibili_import.dart';
import 'hardsub_asr_repair.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../phrases/presentation/phrase_book_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/audio/success_sfx.dart';
import '../../subtitle_completion/reset_episode_subtitles.dart';
import '../../subtitle_completion/spoken_language.dart';
import '../../subtitle_completion/subtitle_completion_enqueue.dart';
import '../../subtitle_completion/subtitle_completion_queue.dart';
import '../../subtitle_completion/subtitle_completion_scheduler.dart';
import '../../subtitle_completion/subtitle_completion_status_hub.dart';
import '../../subtitle_completion/subtitle_completion_status_provider.dart';
import '../../shared/data/word_lookup_service.dart';
import '../../shared/data/word_pronunciation_service.dart';
import '../../shared/presentation/app_loading_overlay.dart';
import '../../authentication/data/wechat_share_helper.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../daily_path/presentation/oral_core_series_provider.dart';
import '../../subtitle_completion/shared_bilibili_subtitle_sync.dart';
import '../../sync/data/personal_import_sync.dart';
import '../../sync/data/progress_sync_service.dart';
import '../../words/data/offline_word_dictionary.dart';
import '../../words/data/vocab_card_enrichment_service.dart';
import '../../reading/data/reading_gloss.dart';
import '../../words/presentation/learned_vocabulary_provider.dart';
import '../../words/presentation/learner_level_provider.dart';
import '../../words/presentation/word_book_provider.dart';
import '../data/dictation_queue_provider.dart';
import '../data/dub_accompaniment_service.dart';
import '../data/dub_export_service.dart';
import '../data/dub_session_store.dart';
import '../data/pronunciation_providers.dart';
import '../domain/dictation_diff.dart';
import '../domain/episode_word_cards.dart';
import '../domain/pronunciation_assessment.dart';
import 'asr_subtitle_cache.dart';
import 'asr_subtitle_job.dart';
import 'asr_subtitle_service.dart';
import 'bilingual_subtitle_helpers.dart';
import 'bilingual_subtitle_pipeline.dart';
import 'embedded_subtitle_reference.dart';
import 'full_transcript_reader.dart';
import 'learning_resume_provider.dart';
import 'manual_subtitle_guard.dart';
import 'manual_subtitle_persist.dart';
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
import 'ai_subtitle_resegment.dart';
import 'subtitle_sentence_merge.dart';
import 'subtitle_word_alignment.dart';
import 'transcript_reader_session.dart';
import 'widgets/ai_grammar_analysis_sheet.dart';
import 'widgets/ai_subtitle_generation_progress_dialog.dart';
import 'widgets/hardsub_mosaic_cover.dart';
import 'widgets/player_subtitle_list.dart';
import 'subtitle_chunk_lexicon_provider.dart';
import 'widgets/player_transcript_panel.dart';
import 'widgets/player_video_panel.dart';
import 'widgets/subtitle_chunk_highlight.dart';
import 'widgets/subtitle_vocabulary_highlight.dart';
import 'widgets/pronunciation_assessment_dialog.dart';
import 'widgets/study_bottom_controls.dart';
import 'widgets/study_dictation_tab.dart';
import 'widgets/study_loop_sheet.dart';
import 'widgets/study_mode_tabs.dart';
import 'widgets/study_practice_tab.dart';
import '../../digital_human/presentation/study_oral_coach_tab.dart';
import 'widgets/study_shadowing_tab.dart';
import 'widgets/study_shell_tokens.dart';
import 'widgets/study_top_bar.dart';
import 'widgets/study_word_cards_tab.dart';

/// Build a whole-episode English excerpt for oral-coach topic generation.
///
/// Samples start / middle / end so questions are not limited to the opening.
String _oralCoachSubtitleExcerpt(
  List<PlayerSubtitleLine> lines, {
  int maxChars = 3500,
}) {
  final List<String> english = <String>[];
  for (final PlayerSubtitleLine line in lines) {
    final String en = line.english.trim();
    if (en.isEmpty || !RegExp('[A-Za-z]').hasMatch(en)) {
      continue;
    }
    english.add(en);
  }
  if (english.isEmpty) {
    return '';
  }
  if (english.length <= 24) {
    final StringBuffer all = StringBuffer();
    for (final String en in english) {
      if (all.isNotEmpty) {
        all.write(' ');
      }
      if (all.length + en.length + 1 > maxChars) {
        break;
      }
      all.write(en);
    }
    return all.toString();
  }
  final int takeEach = 10;
  final int midStart = ((english.length - takeEach) / 2).floor().clamp(
    0,
    english.length - 1,
  );
  final List<String> sampled = <String>[
    ...english.take(takeEach),
    ...english.skip(midStart).take(takeEach),
    ...english.skip(english.length - takeEach),
  ];
  final Set<String> seen = <String>{};
  final StringBuffer buf = StringBuffer();
  for (final String en in sampled) {
    if (!seen.add(en)) {
      continue;
    }
    if (buf.isNotEmpty) {
      buf.write(' ');
    }
    if (buf.length + en.length + 1 > maxChars) {
      break;
    }
    buf.write(en);
  }
  return buf.toString();
}

class PadPortraitPlayerScreen extends ConsumerStatefulWidget {
  const PadPortraitPlayerScreen({
    required this.episodeId,
    this.initialStartTime,
    this.courseId,
    this.unitId,
    this.courseStartMs,
    this.courseEndMs,
    this.autoPlay = true,
    this.autoOpenFullscreen = false,
    this.initialLoopSentence = false,
    super.key,
  });

  final String episodeId;
  final String? initialStartTime;
  final String? courseId;
  final String? unitId;
  final int? courseStartMs;
  final int? courseEndMs;
  final bool autoPlay;
  final bool autoOpenFullscreen;

  /// When opened from review “原片”，auto-enable single-sentence loop.
  final bool initialLoopSentence;

  @override
  ConsumerState<PadPortraitPlayerScreen> createState() =>
      PadPortraitPlayerScreenState();
}

class PadPortraitPlayerScreenState
    extends ConsumerState<PadPortraitPlayerScreen> {
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
  /// Bound by [StudyShadowingTab] — mirrors the toolbar volume / 播放原声 action.
  VoidCallback? _shadowingPlayOriginal;
  bool _dubPlaybackActive = false;
  Player? _dubMixPlayer;
  StreamSubscription<Duration>? _dubPositionSubscription;
  PronunciationPreviewPlayer? _dubOverlayPlayer;
  Timer? _dubWindowTimer;
  final DubAccompanimentService _dubAccompanimentService =
      DubAccompanimentService();
  final DubExportService _dubExportService = const DubExportService();
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
  int _courseWatchedMs = 0;
  int? _courseLastPositionMs;
  int _courseLastSavedMs = 0;
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
  double? _bilingualPipelineProgress;
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
  StudyModeTab _studyTab = StudyModeTab.subtitles;
  bool _dictationQueueMode = false;
  int _dictationQueueIndex = 0;
  bool _hardsubMosaicEnabled = false;
  HardsubMosaicBand _hardsubMosaicBand = const HardsubMosaicBand();
  bool _oralCoachOpen = false;
  bool _pausedForLookup = false;
  bool _blindListening = false;
  StudyLoopSettings _loopSettings = const StudyLoopSettings();
  int _loopCompleted = 0;
  bool _loopIntervalPending = false;

  @override
  void initState() {
    super.initState();
    _releaseGraphicsCache = PlayerGraphicsCache.acquire();
    state = PlayerMockState(initialStartTime: widget.initialStartTime);
    // Intent to play as soon as the decoder is ready (avoids a paused first frame).
    state.isPlaying = widget.autoPlay;
    _syncSettingsToState(ref.read(learningSettingsProvider));
    ref.listenManual<String>(
      learningSettingsProvider.select(
        (LearningSettingsState settings) => settings.subtitleLetterCase,
      ),
      (String? previous, String next) => _syncTranscriptReader(),
    );
    ref.listenManual<SubtitleCompletionStatusState>(
      subtitleCompletionStatusProvider,
      (SubtitleCompletionStatusState? previous, SubtitleCompletionStatusState next) {
        final SubtitleCompletionEpisodeUi? fill = next.forEpisode(
          widget.episodeId,
        );
        if (!mounted) {
          return;
        }
        // Queue file may lag behind enqueue — keep local in-progress UI.
        if (fill == null) {
          return;
        }
        final SubtitleCompletionEpisodeUi? prevFill = previous?.forEpisode(
          widget.episodeId,
        );
        if (fill.status == SubtitleCompletionStatus.done) {
          // Pull fresh EN/ZH (+ karaoke words) onto the open player.
          if (prevFill != null &&
              prevFill.status != SubtitleCompletionStatus.done) {
            unawaited(_reloadAsrSentencesAfterCompletion());
          }
          if (_bilingualPipelineLabel != null ||
              _bilingualPipelineProgress != null) {
            setState(() {
              _bilingualPipelineLabel = null;
              _bilingualPipelineProgress = null;
              _bilingualPhase = BilingualPipelinePhase.completed;
            });
          }
          return;
        }
        if (fill.isActive || fill.isFailed) {
          final bool linesHaveChinese = state.lines.isNotEmpty &&
              state.lines
                      .where((PlayerSubtitleLine l) => looksChinese(l.chinese))
                      .length *
                  2 >=
              state.lines.length;
          // Softsub/display Chinese already present — never keep「翻译中文」UI.
          if (fill.needChinese && linesHaveChinese && !fill.isFailed) {
            unawaited(_settleChineseFillIfAlreadyPresent());
            if (!fill.needEnglish) {
              return;
            }
          }
          final SubtitleFillProgressSummary? summary = next.activeFillProgress;
          final String label = fill.isFailed
              ? fill.displayLabel
              : (summary?.compactLabel ?? fill.displayLabel);
          final double? progress = fill.isFailed
              ? null
              : (summary?.overallProgress ??
                    _progressFromProofreadLabel(fill.displayLabel) ??
                    fill.progressFraction ??
                    0.08);
          if (_bilingualPipelineLabel != label ||
              _bilingualPipelineProgress != progress) {
            setState(() {
              _bilingualPhase = fill.isFailed
                  ? BilingualPipelinePhase.idle
                  : BilingualPipelinePhase.asrProofreading;
              _bilingualPipelineLabel = label;
              _bilingualPipelineProgress = progress;
              _bilingualShowAiComplete = false;
            });
          }
        }
      },
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
    _dubWindowTimer?.cancel();
    unawaited(_dubPositionSubscription?.cancel());
    unawaited(_dubOverlayPlayer?.dispose());
    unawaited(_dubMixPlayer?.dispose());
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
    if (!resource.hasEpisode && widget.episodeId.startsWith('oral_core_9000-')) {
      final LibraryCatalogNotifier catalog = ref.read(libraryCatalogProvider.notifier);
      try {
        final series = await ref.read(oralCoreSeriesProvider.future);
        if (!mounted) return;
        await catalog.ensureOralCoreCourse(series);
      } catch (_) {
        // Existing playback fallbacks still apply if the course cannot load.
      }
      if (!mounted) return;
      resource = resolvePlayerCourseForEpisode(
        courses: ref.read(libraryCatalogProvider),
        episodeId: widget.episodeId,
      );
    }

    String? initialStartTime =
        widget.initialStartTime ??
        ((resource.episode?.completed ?? false)
            ? null
            : resource.episode?.progressTimeStr);
    _videoAsset = resource.videoAsset;

    // Cloud progress last-write-wins by updated_at (fallback: farther position).
    // Hard-cap so a slow/unreachable API cannot freeze「正在打开课程…」.
    try {
      final ProgressSyncService sync = ref.read(progressSyncServiceProvider);
      final Map<String, AcquireProgressDto> remote = await sync
          .pullIndexed()
          .timeout(const Duration(seconds: 2));
      final AcquireProgressDto? row = remote[widget.episodeId];
        final int localMs =
            PlayerMockState.parseTimestampToMsPublic(initialStartTime) ?? 0;
      final AcquireProgressDto? winner = await sync.pickWinner(
        lessonId: widget.episodeId,
        localPositionSec: localMs / 1000.0,
        remote: row,
      );
      if (winner != null) {
        initialStartTime = StudyBottomControls.formatClock(
          Duration(milliseconds: (winner.positionSec * 1000).round()),
        );
        await sync.rememberLocal(
          lessonId: widget.episodeId,
          positionSec: winner.positionSec,
          updatedAt: winner.updatedAt.toUtc(),
          completed: winner.completed,
        );
      }
    } catch (_) {}

    // Bilibili: pull official subs + force local MP4 before the player opens.
    String? enSub = resource.englishSubtitleAsset;
    String? zhSub = resource.chineseSubtitleAsset;
    // Never keep another episode's CC after 合集 local MP4 overwrite.
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
    final bool multiBili =
        (resource.course?.episodes.length ?? 0) > 1 &&
        ((resource.course?.category == 'bilibili') ||
            (resource.course?.sourceLabel.toLowerCase().contains('bilibili') ??
                false) ||
            (resource.course?.id.startsWith('bilibili-') ?? false));
    final String? resyncKey = bilibiliEpisodeCacheKey(
      course: resource.course,
      episode: resource.episode,
      videoAsset: resource.videoAsset ?? _videoAsset,
      sourceUrl: resource.episode?.sourceUrl,
    );
    final bool needsResync = multiBili &&
        await consumeBilibiliSubtitleResyncNeeded(
          episodeId: widget.episodeId,
          sourceKey: resyncKey,
        );
    if (needsResync) {
      // ignore: avoid_print
      print(
        'bilibili.episode cold-resync ep=${widget.episodeId} key=$resyncKey '
        '(keep softsubs; user may regenerate manually)',
      );
      // Do not auto-wipe official softsubs or catalog links. Re-prepare may
      // refresh aligned CC; wrong files stay until the user regenerates.
      resource = resolvePlayerCourseForEpisode(
        courses: ref.read(libraryCatalogProvider),
        episodeId: widget.episodeId,
      );
    }
    // needsResync only marks the cold-open once — do not force prepare when
    // local official EN already exists (合集分集 numberStr ≠ multi-P ?p=).
    ({String? enPath, String? zhPath})? recoveredSubtitles;
    if (enSub == null || zhSub == null) {
      final ids = resolveBilibiliSharedSubtitleIds(
        course: resource.course,
        episode: resource.episode,
        videoAsset: resource.videoAsset,
      );
      if (ids != null) {
        recoveredSubtitles = await tryApplySharedBilibiliSubtitles(
          api: ref.read(acquireApiClientProvider),
          ids: ids,
          existingEnPath: enSub,
          existingZhPath: zhSub,
        ).timeout(const Duration(seconds: 5), onTimeout: () => null);
        if (!mounted) return;
        enSub ??= recoveredSubtitles?.enPath;
        zhSub ??= recoveredSubtitles?.zhPath;
      }
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
        enSub = recoveredSubtitles?.enPath ?? prepared.enSubtitlePath;
      }
      if ((prepared.zhSubtitlePath ?? '').isNotEmpty) {
        zhSub = recoveredSubtitles?.zhPath ?? prepared.zhSubtitlePath;
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
      // Refresh resource after catalog persist.
      resource = resolvePlayerCourseForEpisode(
        courses: ref.read(libraryCatalogProvider),
        episodeId: widget.episodeId,
      );
    }

    // Open the decoder while subtitle files load — less blank wait before play.
    int resumeMs =
        PlayerMockState.parseTimestampToMsPublic(initialStartTime) ?? 0;
    if (widget.courseId != null && widget.unitId != null) {
      final CourseUnitProgress progress = await CourseUnitProgress.load(
        widget.courseId!, widget.unitId!);
      _courseWatchedMs = progress.watchedMs;
      final int start = widget.courseStartMs ?? 0;
      final int end = widget.courseEndMs ?? 0;
      if (progress.positionMs >= start && progress.positionMs < end) {
        resumeMs = progress.positionMs;
      }
    }
    if (resumeMs > 0) {
      state.positionMs = resumeMs;
    }
    if (widget.autoPlay) {
      state.isPlaying = true;
    }
    final Future<void> videoInitFuture = _initVideo();

    // Playing file is source of truth — drop CC that belongs to another BV/page.
    final String? playingKey = bilibiliIdKeyFromPath(
      _videoAsset ?? resource.videoAsset,
    );
    final String? expectKey =
        bilibiliEpisodeCacheKey(
          course: resource.course,
          episode: resource.episode,
          videoAsset: _videoAsset ?? resource.videoAsset,
          sourceUrl: resource.episode?.sourceUrl,
        ) ??
        resyncKey;
    final String? alignKey =
        ((playingKey ?? '').isNotEmpty ? playingKey : expectKey);
    if (isUsableSubtitlePath(enSub) &&
        (alignKey ?? '').isNotEmpty &&
        !bilibiliMediaKeysAligned(bilibiliIdKeyFromPath(enSub), alignKey)) {
      // ignore: avoid_print
      print('bilibili.episode drop en vs video en=$enSub align=$alignKey');
      enSub = null;
    }
    if (isUsableSubtitlePath(zhSub) &&
        (alignKey ?? '').isNotEmpty &&
        !bilibiliMediaKeysAligned(bilibiliIdKeyFromPath(zhSub), alignKey)) {
      // ignore: avoid_print
      print('bilibili.episode drop zh vs video zh=$zhSub align=$alignKey');
      zhSub = null;
    }
    List<PlayerSubtitleLine> resolvedLines = const <PlayerSubtitleLine>[];
    bool officialEnglish = false;
    // episode_subtitles/* has no BV in the path — never load it as "official"
    // without the source.key fingerprint (that was the 合集串台 vector).
    final bool enIsScopedPersist = (enSub ?? '').contains(
      '${Platform.pathSeparator}episode_subtitles${Platform.pathSeparator}',
    );
    final bool zhIsScopedPersist = (zhSub ?? '').contains(
      '${Platform.pathSeparator}episode_subtitles${Platform.pathSeparator}',
    );
    if (enIsScopedPersist) {
      enSub = null;
    }
    if (zhIsScopedPersist) {
      zhSub = null;
    }
    // Rediscover on-disk official softsubs when catalog/tracks were stale.
    final String? officialSourceKey = _episodeSourceKey(resource);
    if (!isUsableSubtitlePath(enSub)) {
      enSub = await existingOfficialBilibiliSubtitle(
        idKey: officialSourceKey,
        fileName: 'en.srt',
      );
    }
    if (!isUsableSubtitlePath(zhSub)) {
      zhSub = await existingOfficialBilibiliSubtitle(
        idKey: officialSourceKey,
        fileName: 'zh.srt',
      );
    }
    if (isUsableSubtitlePath(enSub) || isUsableSubtitlePath(zhSub)) {
      unawaited(
        _persistBilibiliEpisodeAssets(
          resource: resource,
          enSubtitlePath: enSub,
          zhSubtitlePath: zhSub,
          sourceUrl: resource.episode?.sourceUrl,
        ),
      );
    }
    final SubtitleSourceDecision sourcePolicy =
        SubtitleSourcePolicy.decideEpisode(
          episode: resource.episode,
          course: resource.course,
          sourceUrl: resource.episode?.sourceUrl,
        );
    // Prefer official softsubs whenever present. Speech ASR only fills gaps.
    final bool preferSpeech = sourcePolicy.ignoreAllOfficialSoftsubs;
    final bool hardsubHint = SubtitleSourcePolicy.isHardsubHint(
      episode: resource.episode,
      course: resource.course,
      sourceUrl: resource.episode?.sourceUrl,
    );
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
    } else if (isUsableSubtitlePath(zhSub) && !preferSpeech) {
      // Chinese-only official track (non-hardsub): show until Whisper/AI runs.
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
    if (!preferSpeech &&
        !resolvedLines.any(
          (PlayerSubtitleLine line) => looksChinese(line.chinese),
        )) {
      final String? officialZh = await existingOfficialBilibiliSubtitle(
        idKey: officialSourceKey,
        fileName: 'zh.srt',
      );
      if (officialZh != null) {
        try {
          final List<PlayerSubtitleLine> zhOnly =
              normalizeChineseOnlySubtitleLines(
                await loadSubtitleLines(officialZh),
              );
          // Never wipe already-loaded English — merge ZH onto EN timeline.
          if (officialEnglish && resolvedLines.isNotEmpty) {
            resolvedLines = mergeSubtitleLines(
              englishLines: resolvedLines,
              chineseLines: zhOnly,
            );
          } else {
            resolvedLines = zhOnly;
          }
        } catch (e) {
          // ignore: avoid_print
          print('bilibili official zh load error: $e');
        }
      }
    }
    // Official Chinese cues are the timeline. Cached OCR must not replace them.
    if (_linesMissingEnglish(resolvedLines)) {
      final List<PlayerSubtitleLine>? persisted =
          await _loadPersistedBilingualSubtitleFiles();
      if (persisted != null && persisted.isNotEmpty) {
        final bool officialChinese = resolvedLines.any(
          (PlayerSubtitleLine line) => looksChinese(line.chinese),
        );
        final bool trustTranslation = await persistedEnglishIsZhTranslation(
          episodeId: widget.episodeId,
        );
        resolvedLines = officialChinese
            ? subtitleBaseFromOfficialChinese(
                officialChinese: resolvedLines,
                cachedLines: persisted,
                cachedEnglishIsTranslation: trustTranslation,
              )
            : persisted;
      }
    }
    Map<int, List<PlayerSubtitleLine>> asrFragments =
        const <int, List<PlayerSubtitleLine>>{};
    bool usingAsrSentences = false;
    bool strippedHardsubChinese = false;
    final MergedSubtitleBundle? asrBundle = await loadAsrSentenceSubtitles(
      episodeId: widget.episodeId,
      sourceKey: _episodeSourceKey(resource),
      videoFingerprint: videoFileFingerprint(
        _videoAsset ?? resource.videoAsset,
      ),
    );
    // Official softsubs win when present. ASR only fills when English is missing.
    if (asrBundle != null &&
        asrBundle.sentences.isNotEmpty &&
        !officialEnglish) {
      resolvedLines = asrBundle.sentenceLines;
      asrFragments = asrBundle.fragmentsBySentenceStartMs();
      usingAsrSentences = true;
      officialEnglish = false;
      final ({List<PlayerSubtitleLine> lines, bool strippedChinese})
      repaired = await repairHardsubAsrDisplayLines(
        lines: resolvedLines,
        episodeId: widget.episodeId,
        videoPath: _videoAsset ?? resource.videoAsset,
        settings: ref.read(learningSettingsProvider),
        hardsub: hardsubHint,
        sourceKey: _episodeSourceKey(resource),
        bilibiliCookieHeader: ref
            .read(learningSettingsProvider)
            .resolvedBilibiliCookieHeader,
      );
      resolvedLines = repaired.lines;
      strippedHardsubChinese = repaired.strippedChinese;
      if (repaired.strippedChinese) {
        // ignore: avoid_print
        print(
          'bilibili.episode strip softsub ZH under hardsub ASR '
          'ep=${widget.episodeId}',
        );
      }
      // ASR English + official ZH softsub: always try merge when ZH is missing.
      if (!resolvedLines.any(
        (PlayerSubtitleLine l) => looksChinese(l.chinese),
      )) {
        String? officialZhPath = isUsableSubtitlePath(zhSub) ? zhSub : null;
        officialZhPath ??= await existingOfficialBilibiliSubtitle(
          idKey: officialSourceKey,
          fileName: 'zh.srt',
        );
        // Uppercased cache folders still hold the right zh.srt — try aliases.
        officialZhPath ??= await existingOfficialBilibiliSubtitle(
          idKey: (officialSourceKey ?? '').toUpperCase(),
          fileName: 'zh.srt',
        );
        if (isUsableSubtitlePath(officialZhPath)) {
          try {
            final List<PlayerSubtitleLine> zhOnly =
                normalizeChineseOnlySubtitleLines(
                  await loadSubtitleLines(officialZhPath!),
                );
            if (zhOnly.any((PlayerSubtitleLine l) => looksChinese(l.chinese))) {
              resolvedLines = mergeSubtitleLines(
                englishLines: resolvedLines,
                chineseLines: zhOnly,
              );
              strippedHardsubChinese = false;
              zhSub = officialZhPath;
            }
          } catch (e) {
            // ignore: avoid_print
            print('bilibili.episode merge official ZH onto ASR error: $e');
          }
        }
      }
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
    // Reject wrong official/AI CC before first paint (e.g. 3-min phone-review
    // AI-zh on a ~13-min English hardsub lesson). Prefer real video duration.
    final int episodeDurMs =
        (resource.episode?.durationMinutes ?? 0) * 60 * 1000;
    final int mediaDurMs = _videoDuration.inMilliseconds > 0
        ? _videoDuration.inMilliseconds
        : episodeDurMs;
    final bool hasReliableEn = resolvedLines.any(
      (PlayerSubtitleLine line) => isReliableOcrEnglish(line.english),
    );
    final bool chineseOnlySoft = resolvedLines.any(
          (PlayerSubtitleLine line) => looksChinese(line.chinese),
        ) &&
        !hasReliableEn;
    final bool dropDurationMismatch =
        resolvedLines.isNotEmpty &&
        mediaDurMs >= 120000 &&
        subtitleTimelineMismatchesMedia(
          subtitleEndMs: subtitleLinesEndMs(resolvedLines),
          mediaDurationMs: mediaDurMs,
        );
    final SubtitleSourceDecision loadDecision =
        SubtitleSourcePolicy.refineLoaded(
          base: sourcePolicy,
          hasReliableEnglish: hasReliableEn,
          chineseOnlySoft: chineseOnlySoft,
          durationMismatch: dropDurationMismatch,
          usingAsrSentences: usingAsrSentences,
        );
    // Never auto-drop softsubs here — user fixes bad CC via「重新生成/重置字幕」.
    if (loadDecision.dropLoadedSoftsubs && resolvedLines.isNotEmpty) {
      // ignore: avoid_print
      print(
        'bilibili.episode keep CC despite policy hint ep=${widget.episodeId} '
        'reason=${loadDecision.reason}',
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
      if (widget.initialLoopSentence) {
        _loopSettings = const StudyLoopSettings(mode: StudyLoopMode.sentence);
        state.isLooping = true;
      }
      _usingAiSubtitles = usingAsrSentences;
      _usingAsrSentences = usingAsrSentences;
      _asrFragmentsBySentenceStartMs = asrFragments;
      _hasOfficialEnglish = officialEnglish;
      _referenceSubtitleLines = resolvedLines;
      _isBootstrapping = false;
      if (!usingAsrSentences && _linesMissingEnglish(resolvedLines)) {
        _bilingualPhase = BilingualPipelinePhase.asrProofreading;
        _bilingualPipelineLabel = '正在用语音补全英文字幕…';
        _bilingualShowAiComplete = false;
      } else if (strippedHardsubChinese ||
          (usingAsrSentences &&
              resolvedLines.isNotEmpty &&
              resolvedLines.every(
                (PlayerSubtitleLine l) => !looksChinese(l.chinese),
              ))) {
        _bilingualPhase = BilingualPipelinePhase.asrProofreading;
        _bilingualPipelineLabel = '导入后台补中文中…';
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
        final String videoKey = widget.episodeId.trim();
        if (videoKey.isNotEmpty) {
          ref
              .read(learningActivityProvider.notifier)
              .recordVideoWatched(videoKey: videoKey);
        }
      });
    }
    // Empty / missing sides → import queue Whisper. Existing Chinese is kept.
    final bool missingChineseSide = resolvedLines.isNotEmpty &&
        resolvedLines.every(
          (PlayerSubtitleLine l) => !looksChinese(l.chinese),
        );
    final bool hasChineseCoverage = resolvedLines.isNotEmpty &&
        resolvedLines.where((PlayerSubtitleLine l) => looksChinese(l.chinese)).length *
                2 >=
            resolvedLines.length;
    // Official/ASR already shows Chinese — clear stale「正在翻译中文」UI and
    // settle any leftover needChinese-only queue row for this episode.
    if (hasChineseCoverage) {
      unawaited(_settleChineseFillIfAlreadyPresent());
    }
    if ((!usingAsrSentences &&
            (resolvedLines.isEmpty ||
                _linesMissingEnglish(resolvedLines) ||
                missingChineseSide)) ||
        strippedHardsubChinese ||
        (usingAsrSentences && missingChineseSide)) {
      unawaited(_ensureImportTimeSubtitleCompletion());
    }
    if (needsResync) {
      unawaited(
        markBilibiliSubtitleResyncDone(
          episodeId: widget.episodeId,
          sourceKey: expectKey ?? resyncKey,
        ),
      );
    }
    await videoInitFuture;
    if (mounted) {
      _applyPlaybackMode();
    }
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
    final bool isSeason = course.id.startsWith('bilibili-season-');
    final String? source = bilibiliSourceForEpisode(
      course: course,
      episode: resource.episode,
      videoAsset: resource.videoAsset,
    );
    // UGC 合集: numberStr is episode index, NOT multi-P ?p=.
    final int page = isSeason
        ? (BilibiliImport.extractPage(source ?? '') ?? 1)
        : (BilibiliImport.extractPage(source ?? '') ??
              int.tryParse(resource.episode?.numberStr ?? '') ??
              1);
    // Multi-P P2+ must re-pull page-scoped official CC (folder may look right
    // while still holding an older page-1 download).
    if (page > 1) {
      return true;
    }
    final bool hasLocalVideo = isUsableLocalVideoPath(resource.videoAsset);
    final bool hasEnglish = isUsableSubtitlePath(resource.englishSubtitleAsset);
    final bool hasChinese = isUsableSubtitlePath(resource.chineseSubtitleAsset);
    // Official series with ECS softsubs: stream B站 + load cloud SRT, no local
    // MP4 / B站官方字幕预拉（否则会误报「没有字幕」并卡下载）.
    final String courseId = resource.course?.id ?? '';
    final String episodeId = resource.episode?.id ?? widget.episodeId;
    final bool officialCloudSubs =
        (courseId == 'oral_core_9000' ||
            episodeId.startsWith('oral_core_9000-')) &&
        (hasEnglish || hasChinese);
    if (officialCloudSubs) {
      return false;
    }
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
    // Per-episode update so concurrent 合集 background downloads are not wiped.
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

  /// Log duration mismatch only — never auto-wipe softsubs / catalog links.
  Future<void> _rejectSubtitlesThatExceedVideo(Duration mediaDuration) async {
    if (!mounted || !state.hasLines || mediaDuration.inMilliseconds <= 0) {
      return;
    }
    final int endMs = subtitleLinesEndMs(state.lines);
    final int mediaMs = mediaDuration.inMilliseconds;
    if (!subtitleTimelineMismatchesMedia(
      subtitleEndMs: endMs,
      mediaDurationMs: mediaMs,
    )) {
      return;
    }
    // ignore: avoid_print
    print(
      'bilibili.episode keep mismatched-duration subs ep=${widget.episodeId} '
      'subEndMs=$endMs mediaMs=$mediaMs (user may regenerate manually)',
    );
  }

  /// Drop catalog/persisted CC that belongs to a different BV than this episode.
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
      // Still pin durable sourceUrl when missing.
      if ((resource.episode?.sourceUrl ?? '').trim().isEmpty) {
        await _persistBilibiliEpisodeAssets(
          resource: resource,
          sourceUrl: source,
        );
      }
      return (en: enSub, zh: zhSub, dropped: false);
    }
    // ignore: avoid_print
    print(
      'bilibili.episode ignore foreign subs for load ep=${widget.episodeId} '
      'source=$source enForeign=$enForeign zhForeign=$zhForeign '
      '(keep files/catalog; user may regenerate)',
    );
    // Session load only — do not delete files or clear catalog links.
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
          // If the old single-episode id vanished, prefer the episode that
          // already holds the imported local MP4 — not always index 0.
          if (resource.course == null) {
            final String fallbackId = _preferredExpandedEpisodeId(expanded);
            resource = resolvePlayerCourseForEpisode(
              courses: ref.read(libraryCatalogProvider),
              episodeId: fallbackId,
            );
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print('bilibili.prepare expand pages error: $e');
      }
    }
    final LibraryCourseData? resolvedCourse = resource.course ?? course;
    final bool isSeason =
        resolvedCourse?.id.startsWith('bilibili-season-') ?? false;
    final String? rawSource =
        bilibiliSourceForEpisode(
          course: resolvedCourse,
          episode: resource.episode,
          videoAsset: resource.videoAsset,
        ) ??
        _bilibiliRecoverSource(resource.videoAsset ?? '') ??
        // Course description is ONE BV — never reuse it for other 合集分集.
        (isSeason
            ? null
            : _bilibiliRecoverSource(resolvedCourse?.description ?? ''));
    if (rawSource == null || rawSource.isEmpty) {
      return const BilibiliEpisodePrepareResult(
        note: '无法识别本集 B 站来源（合集分集需各自 BV）',
      );
    }
    String source = rawSource;
    // Catalog may hold uppercased BVs (view/playurl → 啥都木有). Repair via
    // aid= on the URL or UGC season archives, then persist the canonical URL.
    try {
      final String repaired = await repairBilibiliSourceCase(
        service: service,
        source: source,
        course: resolvedCourse,
        episode: resource.episode,
      );
      if (repaired != source) {
        // ignore: avoid_print
        print(
          'bilibili.prepare repaired source $source -> $repaired '
          'ep=${widget.episodeId}',
        );
        source = repaired;
        await _persistBilibiliEpisodeAssets(
          resource: resource,
          sourceUrl: repaired,
        );
      }
    } catch (e) {
      // ignore: avoid_print
      print('bilibili.prepare source repair error: $e');
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
      // Hardsubs stay in-frame; never let mpv/libass softsubs cover them.
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
      // Avoid pause→play stutter on open: start immediately when autoplay is on.
      final bool shouldPlay = widget.autoPlay || state.isPlaying;
      if (shouldPlay) {
        state.isPlaying = true;
        await player.play();
      } else {
        await player.pause();
      }
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
        if (shouldPlay) {
          state.isPlaying = true;
        }
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
        // A timed Chinese track stays the subtitle. Do not replace it with
        // an OCR/ASR cache.
        unawaited(_loadCachedAiSubtitles(validateReferenceSignature: false));
      }
      if (!mounted) return;
      _applyPlaybackMode();
      // Do not start live OCR/ZH→EN fill on open — import queue owns completion.
      unawaited(_ensureImportTimeSubtitleCompletion());
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
      unawaited(_ensureImportTimeSubtitleCompletion());
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
      final PlayerCourseLookupResult lookup = resolvePlayerCourseForEpisode(
        courses: ref.read(libraryCatalogProvider),
        episodeId: widget.episodeId,
      );
      final String playSource = await repairBilibiliSourceCase(
        service: service,
        source: biliSource,
        course: lookup.course,
        episode: lookup.episode,
      );
      // Prefer the import cache before resolvePlayable starts a CDN download.
      final String? cached = await service.findExistingLocalCache(playSource);
      if (isUsableLocalVideoPath(cached)) {
        await _persistLocalBilibiliVideo(cached!);
        if (mounted) {
          setState(() => _videoAsset = cached);
        }
        onProgress?.call(1, '使用已缓存视频');
        return (uri: cached, headers: null);
      }
      final BilibiliPlayableMedia media = await service
          .resolvePlayableForPlayback(playSource, onProgress: onProgress);
      // Always write the cache/local path back so the next open skips prepare
      // and does not look like a fresh download.
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
    if (expanded.episodes.isEmpty) {
      return widget.episodeId;
    }
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
    // Course description is ONE BV — never reuse it for 合集分集.
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
    // Prefer any already-downloaded episode MP4 — never re-resolve short links
    // when the catalog (or live playback asset) already points at a local file.
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
    // Short links / season ids must already be BV/av here — refuse raw b23.
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

  String _videoLoadErrorMessage(Object error, String? source) {
    String text = error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Exception: ', '')
        .replaceFirst('B站视频无法播放：', '');
    // Collapse noisy DioException walls of text into a short status.
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
    // Incomplete Chinese-only caches must NOT replace official/seed lines —
    // that was re-applying broken AI subs after「切回原始字幕」and blocking EN fill.
    if (BilingualSubtitlePipeline.shouldAutoStart(lines)) {
      if (mounted && _videoReady) {
        unawaited(_ensureImportTimeSubtitleCompletion());
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

  /// After import-queue Whisper/translate finishes, refresh the open player.
  Future<void> _reloadAsrSentencesAfterCompletion() async {
    if (!mounted) {
      return;
    }
    final PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: widget.episodeId,
    );
    final String? videoPath = _videoAsset ?? resource.videoAsset;
    final MergedSubtitleBundle? asrBundle = await loadAsrSentenceSubtitles(
      episodeId: widget.episodeId,
      sourceKey: _episodeSourceKey(resource),
      videoFingerprint: videoFileFingerprint(videoPath),
    );
    if (!mounted || asrBundle == null || asrBundle.sentences.isEmpty) {
      return;
    }
    // Keep official softsubs on screen when the catalog still points at them.
    final String? catalogEn = resource.englishSubtitleAsset;
    final bool catalogHasOfficialEn =
        isUsableSubtitlePath(catalogEn) &&
        !(catalogEn ?? '').contains('episode_subtitles');
    if (catalogHasOfficialEn || _hasOfficialEnglish) {
      return;
    }
    List<PlayerSubtitleLine> lines = asrBundle.sentenceLines;
    final bool hardsubHint = SubtitleSourcePolicy.isHardsubHint(
      episode: resource.episode,
      course: resource.course,
      sourceUrl: resource.episode?.sourceUrl,
    );
    if (hardsubHint) {
      final ({List<PlayerSubtitleLine> lines, bool strippedChinese}) repaired =
          await repairHardsubAsrDisplayLines(
            lines: lines,
            episodeId: widget.episodeId,
            videoPath: videoPath,
            settings: ref.read(learningSettingsProvider),
            hardsub: true,
            sourceKey: _episodeSourceKey(resource),
            bilibiliCookieHeader: ref
                .read(learningSettingsProvider)
                .resolvedBilibiliCookieHeader,
          );
      lines = repaired.lines;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      state.replaceLines(lines);
      _usingAiSubtitles = true;
      _usingAsrSentences = true;
      _asrFragmentsBySentenceStartMs = asrBundle.fragmentsBySentenceStartMs();
      _referenceSubtitleLines = lines;
      _hasOfficialEnglish = false;
    });
  }

  /// Subtitles are completed at import time. Opening the player only re-queues
  /// unfinished work and surfaces status — it must not ZH→EN / OCR-fill live.
Future<void> _settleChineseFillIfAlreadyPresent() async {
    if (!mounted) {
      return;
    }
    if (_bilingualPipelineLabel != null &&
        (_bilingualPipelineLabel!.contains('翻译中文') ||
            _bilingualPipelineLabel!.contains('补中文') ||
            _bilingualPipelineLabel!.contains('重译中文') ||
            _bilingualPipelineLabel!.contains('中英字幕'))) {
      setState(() {
        _bilingualPipelineLabel = null;
        _bilingualPipelineProgress = null;
        _bilingualPhase = BilingualPipelinePhase.completed;
        _bilingualShowAiComplete = false;
      });
    }
    try {
      final SubtitleCompletionQueue store = SubtitleCompletionQueue.shared;
      final List<SubtitleCompletionJob> jobs = await store.loadJobs();
      SubtitleCompletionJob? job;
      for (final SubtitleCompletionJob row in jobs) {
        if (row.episodeId == widget.episodeId) {
          job = row;
          break;
        }
      }
      if (job == null) {
        return;
      }
      final bool active =
          job.status == SubtitleCompletionStatus.pending ||
          job.status == SubtitleCompletionStatus.running ||
          job.status == SubtitleCompletionStatus.failed;
      if (!active || !job.needChinese) {
        return;
      }
      // Official/display Chinese already covers this episode — stop ZH fill.
      await store.clearSatisfiedNeeds(widget.episodeId, clearChinese: true);
      SubtitleCompletionStatusHub.instance.notifyChanged();
      if (mounted) {
        final bool stillEnglish = job.needEnglish;
        ref.read(subtitleCompletionStatusProvider.notifier).reportProgress(
          widget.episodeId,
          stillEnglish ? '正在用语音生成英文字幕…' : '字幕已补全',
          needEnglish: stillEnglish,
          needChinese: false,
          status: stillEnglish
              ? SubtitleCompletionStatus.running
              : SubtitleCompletionStatus.done,
        );
        if (!stillEnglish &&
            (_bilingualPipelineLabel != null ||
                _bilingualPipelineProgress != null)) {
          setState(() {
            _bilingualPipelineLabel = null;
            _bilingualPipelineProgress = null;
            _bilingualPhase = BilingualPipelinePhase.completed;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _ensureImportTimeSubtitleCompletion() async {
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
    final String? sourceKey = bilibiliEpisodeCacheKey(
      course: resource.course,
      episode: resource.episode,
      videoAsset: videoPath,
      sourceUrl: resource.episode?.sourceUrl,
    );
    final SubtitleSourceDecision fillPolicy =
        SubtitleSourcePolicy.decideEpisode(
          episode: resource.episode,
          course: resource.course,
          sourceUrl: resource.episode?.sourceUrl,
        );
    final SubtitleCompletionNeed need = await detectSubtitleCompletionNeed(
      episodeId: widget.episodeId,
      zhSubtitlePath: fillPolicy.ignoreAllOfficialSoftsubs
          ? null
          : resource.chineseSubtitleAsset,
      enSubtitlePath: fillPolicy.ignoreAllOfficialSoftsubs
          ? null
          : resource.englishSubtitleAsset,
      sourceKey: sourceKey,
      videoPath: videoPath,
      ignoreOfficialChinese:
          fillPolicy.ignoreOfficialChinese ||
          fillPolicy.ignoreAllOfficialSoftsubs,
    );
    if (!need.any) {
      if (mounted &&
          (_bilingualPipelineLabel != null ||
              _bilingualPhase == BilingualPipelinePhase.ocrRunning ||
              _bilingualPhase == BilingualPipelinePhase.asrProofreading)) {
        setState(() {
          _bilingualPipelineLabel = null;
          _bilingualPipelineProgress = null;
          _bilingualPhase = BilingualPipelinePhase.completed;
          _bilingualShowAiComplete = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _bilingualPhase = BilingualPipelinePhase.asrProofreading;
        _bilingualShowAiComplete = false;
        _bilingualPipelineProgress = 0;
        // Speech owns English — never advertise ZH→EN on open.
        _bilingualPipelineLabel = need.needProofread && !need.needEnglish
            ? '导入后台语音校对英文中…'
            : (need.needEnglish && need.needChinese
                  ? '导入后台语音补全中英字幕中…'
                  : (need.needEnglish
                        ? '导入后台语音补英文中…'
                        : '导入后台补中文中…'));
      });
    }
    await enqueueSubtitleCompletionForEpisode(
      episodeId: widget.episodeId,
      videoPath: videoPath,
      zhSubtitlePath: resource.chineseSubtitleAsset,
      enSubtitlePath: resource.englishSubtitleAsset,
      sourceUrl: resource.episode?.sourceUrl,
      course: resource.course,
      episode: resource.episode,
      bilibiliCookieHeader: ref
          .read(learningSettingsProvider)
          .resolvedBilibiliCookieHeader,
    );
    SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
  }

  Future<void> _maybeStartBilingualPipeline({
    bool forRegenerate = false,
  }) async {
    if (!mounted || _generatingAiSubtitles) {
      return;
    }
    final String? rawVideoPath = _videoAsset;
    if (rawVideoPath == null || rawVideoPath.isEmpty || !_videoReady) {
      return;
    }
    String videoPath = rawVideoPath;
    // Whisper needs a local MP4. Prefer the import cache over a CDN URL.
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
    // Opening the player must NOT ZH→EN or OCR-fill live. Import queue owns
    // missing-side fill + speech proofread;「重新识别」uses ASR only.
    if (!forRegenerate) {
      await _ensureImportTimeSubtitleCompletion();
      return;
    }
    // Incomplete AI/OCR caches used to set this true and skip fill forever.
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
        // Debounced local save: OCR English timed to the video clock.
        _scheduleOcrSubtitlePersist(kept);
      },
      onNeedTranslationFallback: () {
        // Import queue owns missing-side fill; player OCR only upgrades hardsubs.
        unawaited(_ensureImportTimeSubtitleCompletion());
      },
      onPhaseChanged: (BilingualPipelinePhase phase) {
        if (!mounted) {
          return;
        }
        setState(() {
          _bilingualPhase = phase;
          _bilingualShowAiComplete = phase == BilingualPipelinePhase.ocrSlow;
          if (phase == BilingualPipelinePhase.completed) {
            final bool stillMissing = BilingualSubtitlePipeline.shouldAutoStart(
              state.lines,
            );
            // Never mark AI-complete while the list is still Chinese-only.
            _usingAiSubtitles = !stillMissing;
            _bilingualPipelineLabel = stillMissing ? '英文字幕仍不完整' : null;
            _bilingualPipelineProgress = null;
            _bilingualShowAiComplete = stillMissing;
          } else if (phase == BilingualPipelinePhase.cancelled) {
            _bilingualPipelineLabel = null;
            _bilingualPipelineProgress = null;
            _bilingualShowAiComplete = false;
          }
        });
        if (phase == BilingualPipelinePhase.ocrSlow &&
            _linesMissingEnglish(state.lines)) {
          unawaited(_ensureImportTimeSubtitleCompletion());
        }
      },
      onProgress: (String label) {
        if (!mounted) {
          return;
        }
        setState(() {
          _bilingualPipelineLabel = label;
          _bilingualPipelineProgress =
              _progressFromProofreadLabel(label) ?? _bilingualPipelineProgress;
        });
      },
      onProofreadProgress: (double value) {
        if (!mounted) {
          return;
        }
        setState(() => _bilingualPipelineProgress = value.clamp(0.0, 1.0));
      },
      onBilingualReady: (List<PlayerSubtitleLine> lines) async {
        await _persistCompletedBilingualSubtitles(_withManualEnglish(lines));
        if (mounted) {
          _showMessage('双语字幕已保存到本机，下次打开不用重译');
        }
      },
    );
    _bilingualPipeline = pipeline;
    setState(() {
      _bilingualPhase = BilingualPipelinePhase.asrProofreading;
      _bilingualPipelineLabel = '语音校对：正在准备…';
      _bilingualPipelineProgress = 0;
      _bilingualShowAiComplete = false;
    });
    await pipeline.startOcr(
      isPlaying: () => state.isPlaying || _videoIsPlaying,
      positionMs: () => _videoPosition.inMilliseconds > 0
          ? _videoPosition.inMilliseconds
          : state.positionMs,
      proofreadExisting: true,
    );
  }

  String? _episodeSourceKey([PlayerCourseLookupResult? resource]) {
    final PlayerCourseLookupResult resolved =
        resource ??
        resolvePlayerCourseForEpisode(
          courses: ref.read(libraryCatalogProvider),
          episodeId: widget.episodeId,
        );
    return bilibiliEpisodeCacheKey(
      course: resolved.course,
      episode: resolved.episode,
      videoAsset: resolved.videoAsset ?? _videoAsset,
      sourceUrl: resolved.episode?.sourceUrl,
    );
  }

  Future<List<PlayerSubtitleLine>?>
  _loadPersistedBilingualSubtitleFiles() async {
    try {
      final String? sourceKey = _episodeSourceKey();
      // 合集 without a BV fingerprint must not reuse unscoped EN/ZH caches.
      final bool isSeason =
          resolvePlayerCourseForEpisode(
            courses: ref.read(libraryCatalogProvider),
            episodeId: widget.episodeId,
          ).course?.id.startsWith('bilibili-season-') ??
          false;
      if (isSeason && (sourceKey == null || sourceKey.isEmpty)) {
        await deletePersistedBilingualSubtitleFiles(
          episodeId: widget.episodeId,
        );
        return null;
      }
      final PersistedBilingualSubtitleFiles? files =
          await locatePersistedBilingualSubtitleFiles(
            episodeId: widget.episodeId,
            sourceKey: sourceKey,
            videoFingerprint: videoFileFingerprint(
              _videoAsset ??
                  resolvePlayerCourseForEpisode(
                    courses: ref.read(libraryCatalogProvider),
                    episodeId: widget.episodeId,
                  ).videoAsset,
            ),
          );
      if (files == null) {
        return null;
      }
      if (!isUsableSubtitlePath(files.englishPath) ||
          !isUsableSubtitlePath(files.chinesePath)) {
        return null;
      }
      final List<PlayerSubtitleLine> merged =
          mergePartialEnglishOntoChineseBase(
            chineseLines: await loadSubtitleLines(files.chinesePath),
            englishLines: await loadSubtitleLines(files.englishPath),
            allowIndexFallback: false,
          );
      final bool hasAnyEnglish = merged.any(
        (PlayerSubtitleLine line) => looksEnglish(line.english),
      );
      if (merged.isEmpty || !hasAnyEnglish) {
        return null;
      }
      return merged;
    } catch (_) {
      return null;
    }
  }

  bool _linesMissingEnglish(List<PlayerSubtitleLine> lines) {
    if (lines.isEmpty) {
      return true;
    }
    return BilingualSubtitlePipeline.shouldAutoStart(lines);
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
    // JSON ASR cache is only reused when fully bilingual (loader rejects holes).
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
    // Partial or complete: write EN/ZH .srt so the next open reuses English holes.
    final PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: widget.episodeId,
    );
    final PersistedBilingualSubtitleFiles? files =
        await persistBilingualSubtitleFiles(
          episodeId: widget.episodeId,
          lines: lines,
          sourceKey: _episodeSourceKey(resource),
          videoFingerprint: videoFileFingerprint(videoPath),
          translatedFromChinese: lines.any(
            (PlayerSubtitleLine line) => looksChinese(line.chinese),
          ),
        );
    if (files == null) {
      return;
    }
    // Only attach complete pairs to the catalog path — partial EN is shorter
    // than ZH and would drop cues via mergeSubtitleLines.
    if (!complete) {
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
      // Never paint softsubs on the video surface (hardsubs already burn in;
      // learners read the list under the player). Force-disable every update.
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
      setState(() {
        _videoDuration = duration;
      });
      // Re-check whenever duration is known — first event often arrives before
      // lines load, so a one-shot "became known" flag missed 3-min 串台 CC.
      if (duration.inMilliseconds >= 120000 && state.hasLines) {
        unawaited(_rejectSubtitlesThatExceedVideo(duration));
      }
    });
    _videoPlayingSubscription = player.stream.playing.listen((bool playing) {
      _videoIsPlaying = playing;
      final Player? mix = _dubMixPlayer;
      if (mix != null) unawaited(playing ? mix.play() : mix.pause());
      _syncIdleSchedulerWithPlayback(playing);
    });
    _videoCompletedSubscription = player.stream.completed.listen((
      bool completed,
    ) {
      if (!completed) {
        return;
      }
      if (_loopSettings.mode == StudyLoopMode.full ||
          _loopSettings.mode == StudyLoopMode.ab) {
        unawaited(_applyLoopRestart());
        return;
      }
      _stopVideo();
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

  void _saveCoursePosition(int positionMs, {bool force = false}) {
    final String? courseId = widget.courseId;
    final String? unitId = widget.unitId;
    if (courseId == null || unitId == null) return;
    final int start = widget.courseStartMs ?? 0;
    final int end = widget.courseEndMs ?? 0;
    if (end <= start || positionMs < start || positionMs > end) return;
    final int? last = _courseLastPositionMs;
    if (_videoIsPlaying && last != null) {
      final int delta = positionMs - last;
      if (delta > 0 && delta <= 1500) _courseWatchedMs += delta;
    }
    _courseLastPositionMs = positionMs;
    if (force || (positionMs - _courseLastSavedMs).abs() >= 2000) {
      _courseLastSavedMs = positionMs;
      unawaited(CourseUnitProgress.save(courseId, unitId,
          CourseUnitProgress(positionMs: positionMs, watchedMs: _courseWatchedMs)));
    }
  }

  void _onVideoProgress(Duration position) {
    if (!mounted || _ignoreStaleScrubPosition(position)) {
      return;
    }

    final int? courseEnd = widget.courseEndMs;
    final int? courseStart = widget.courseStartMs;
    if (courseEnd != null && courseStart != null &&
        courseEnd > courseStart && position.inMilliseconds >= courseEnd) {
      if (_videoIsPlaying) {
        _saveCoursePosition(courseEnd, force: true);
        unawaited(_videoPlayer?.pause());
        unawaited(_videoPlayer?.seek(Duration(milliseconds: courseEnd)));
        setState(() {
          _videoPosition = Duration(milliseconds: courseEnd);
          state.positionMs = courseEnd;
          state.isPlaying = false;
        });
      }
      return;
    }
    if (courseStart != null && position.inMilliseconds < courseStart - 400 &&
        _videoReady) {
      unawaited(_videoPlayer?.seek(Duration(milliseconds: courseStart)));
      return;
    }
    _saveCoursePosition(position.inMilliseconds);

    final bool wasPlaying = _videoIsPlaying;
    bool lineChanged = false;
    bool loopRestarted = false;

    if (wasPlaying &&
        _loopSettings.mode == StudyLoopMode.ab &&
        _loopSettings.hasAbRange &&
        position.inMilliseconds >= _loopSettings.abEndMs!) {
      unawaited(_applyLoopRestart());
      return;
    }

    // 句末暂停 / 跟读：听完末词（含宽限）后停在句首，方便影子跟读再开口。
    if (wasPlaying &&
        state.pauseAtSentenceEnd &&
        state.hasLines &&
        !state.isLooping &&
        state.shouldPauseAtSentenceEnd(position.inMilliseconds)) {
      final int lineIndex = state.activeLineIndex;
      final Duration start = Duration(
        milliseconds: state.videoStartMsForLine(lineIndex),
      );
      setState(() {
        _videoPosition = start;
        state.positionMs = start.inMilliseconds;
        state.isPlaying = false;
      });
      PlayerSystemMediaControls.updatePlaybackState(isPlaying: false);
      unawaited(_videoPlayer?.pause());
      unawaited(_videoPlayer?.seek(start));
      return;
    }

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
      if (_loopSettings.mode == StudyLoopMode.sentence &&
          (_loopSettings.intervalSec > 0 || _loopSettings.countLimit > 0)) {
        unawaited(_applyLoopRestart());
        return;
      }
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

  bool _resegmentingSubtitles = false;

  Future<void> _resegmentSubtitleLines(int index, int count) async {
    if (_resegmentingSubtitles || index < 0 || index + count > state.lines.length) return;
    final List<PlayerSubtitleLine> snapshot = state.lines;
    final List<PlayerSubtitleLine> source = snapshot.sublist(index, index + count);
    _resegmentingSubtitles = true;
    _stopVideo();
    _showMessage('AI 正在处理字幕…');
    try {
      final List<PlayerSubtitleLine> replacement = await resegmentSubtitles(
        source: source,
        merge: count > 1,
        settings: ref.read(learningSettingsProvider),
        formatTime: _formatTimestamp,
      );
      if (!mounted || !identical(snapshot, state.lines)) return;
      final List<PlayerSubtitleLine> next = List<PlayerSubtitleLine>.of(snapshot)
        ..replaceRange(index, index + count, replacement);
      await persistManualSubtitleEdits(
        episodeId: widget.episodeId,
        lines: next,
        sourceKey: _episodeSourceKey(),
        videoPath: _videoAsset,
      );
      if (!mounted || !identical(snapshot, state.lines)) return;
      setState(() {
        state.replaceLines(next, preferredSubtitleMode: SubtitleDisplayMode.bilingual);
        _referenceSubtitleLines = next;
      });
      unawaited(_syncManualSubtitlesToCloud(next));
      _showMessage('字幕已保存');
    } catch (_) {
      if (mounted) _showMessage('字幕处理失败，请检查 AI 设置后重试');
    } finally {
      _resegmentingSubtitles = false;
    }
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
    }
    if (nextChinese.isNotEmpty) {
      _manualChineseByStartMs[current.startMs] = nextChinese;
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
    await persistManualSubtitleEdits(
      episodeId: widget.episodeId,
      lines: next,
      sourceKey: _episodeSourceKey(),
      videoPath: _videoAsset,
    );
    unawaited(_syncManualSubtitlesToCloud(next));
    if (mounted) {
      _showMessage('已保存手工字幕，并同步云端字幕库');
    }
  }

  Future<void> _syncManualSubtitlesToCloud(List<PlayerSubtitleLine> lines, {
    String sourceOrigin = 'mixed',
  }) async {
    final AuthSessionState auth = ref.read(authSessionProvider);
    if (!auth.isLoggedIn) {
      return;
    }
    final ({LibraryCourseData course, LibraryEpisodeItem episode})? hit =
        findCatalogEpisode(
          courses: ref.read(libraryCatalogProvider),
          episodeId: widget.episodeId,
        );
    await syncEpisodeSubtitleLinesToCloud(
      api: ref.read(acquireApiClientProvider),
      isLoggedIn: true,
      lines: lines,
      sourceKey: _episodeSourceKey(),
      sourceUrl: hit?.episode.sourceUrl ?? _bilibiliRecoverSource(_videoAsset ?? ''),
      course: hit?.course,
      episode: hit?.episode,
      durationSec: (hit?.episode.durationMinutes ?? 0) > 0
          ? hit!.episode.durationMinutes * 60
          : null,
      sourceOrigin: sourceOrigin,
    );
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

  /// Prefer catalog-local media so Android MediaExtractor can cut a WAV.
  String? _assessmentVideoSource() =>
      _localPlayableVideoPath() ?? _videoAsset;

  PronunciationTargetSelection _selectPronunciationForLine(int index) =>
      selectPronunciationTarget(
        state: state,
        videoSource: _assessmentVideoSource(),
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
      videoSource: _assessmentVideoSource(),
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
      await showPronunciationAssessmentDialog(context, target: target, episodeId: widget.episodeId);
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
    if (state.lines.isEmpty) {
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

  @visibleForTesting
  void debugHandleVideoProgress(Duration position) =>
      _onVideoProgress(position);

  @visibleForTesting
  ValueListenable<TranscriptReaderProgress> get debugTranscriptReaderProgress =>
      _transcriptReaderSession.progress;

  void _syncTranscriptReader() {
    if (!state.hasLines) return;
    _transcriptReaderSession.updateProgress(
      subtitleLetterCase: ref.read(learningSettingsProvider).subtitleLetterCase,
      lineIndex: state.activeLineIndex,
      wordIndex: state.currentWordIndex,
      loopingLineIndex: state.isLooping ? state.activeLineIndex : null,
    );
  }

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
    final ThemeMode themeMode = ref.watch(themeLogicProvider).themeMode;
    final Brightness platformBrightness = MediaQuery.platformBrightnessOf(
      context,
    );
    final Brightness studyBrightness = switch (themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platformBrightness,
    };
    final StudyShellColors studyColors = studyBrightness == Brightness.light
        ? StudyShellColors.light
        : StudyShellColors.dark;
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final bool compactPlayer = screenWidth < 700;
    final double playerHorizontalPadding = compactPlayer ? 0 : 12;
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
          videoSource: _assessmentVideoSource(),
          videoReady: _videoReady,
          videoDuration: _videoDuration,
        );
    final LibraryCourseData? course = courseContext.course;
    final LibraryEpisodeItem? episode = courseContext.episode;
    final LearningSettingsState settings = ref.watch(learningSettingsProvider);
    final bool bingeMode = settings.isBingeWatchMode;
    final Set<String> savedVocabularyWords =
        SubtitleVocabularyHighlight.savedWordsFromBook(
          ref.watch(wordBookProvider),
        );
    final Set<String> learnedVocabularyWords = ref.watch(learnedVocabularyProvider);
    final Set<String> keyVocabularyWords =
        ref.watch(recommendedWordsProvider);
    final SubtitleChunkHighlighter? chunkHighlighter = ref
        .watch(subtitleChunkHighlighterProvider)
        .asData
        ?.value;
    final bool canGenerateAiSubtitles =
        (_videoAsset?.isNotEmpty ?? false) && !_usingAiSubtitles;
    final bool landscapeFirst = widget.autoOpenFullscreen ||
        prefersNetdiskLandscapePlayback(course);
    if (landscapeFirst &&
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

    return Theme(
      data: Theme.of(context).copyWith(brightness: studyBrightness),
      child: Scaffold(
        backgroundColor: studyColors.background,
      body: AppLoadingOverlay(
        isLoading: _isBootstrapping,
        message: '正在打开课程...',
        child: Column(
          children: <Widget>[
            StudyTopBar(
              title: course?.title ?? episode?.title ?? '爱快英语',
              lessonBadge: course == null || episode == null
                  ? null
                  : '${episode.numberStr}/${course.totalEpisodes}',
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                  return;
                }
                context.go(libraryDetailUri.toString());
              },
              isFavorite: state.hasLines && _isLineBookmarked(state.activeLineIndex),
              onFavorite: () => _handleToggleEpisodeFavorite(courseContext),
              onEnableCourseMode: () {
                unawaited(
                  showEnableCourseModeSheet(
                    context: context,
                    ref: ref,
                    type: CoursePlanType.video,
                    sourceId: widget.episodeId,
                    title: course?.title ??
                        episode?.title ??
                        '视频课程',
                    subtitleLines: state.lines,
                  ),
                );
              },
              watchModeLabel: settings.playerWatchMode,
              onToggleWatchMode: () {
                final String next =
                    settings.isBingeWatchMode ? '精听' : '追剧';
                ref
                    .read(learningSettingsProvider.notifier)
                    .setPlayerWatchMode(next);
                if (next == '追剧') {
                  setState(() {
                    state.pauseAtSentenceEnd = false;
                    _hardsubMosaicEnabled = false;
                  });
                  _showMessage('追剧模式：少打断，点「精听」回到学习壳');
                } else {
                  _showMessage('精听模式：字幕 / 跟读 / 听写 / 背单词');
                }
              },
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(0, compactPlayer ? 2 : 6, 0, 0),
                child: Column(
                  children: <Widget>[
                    Flexible(
                      flex: bingeMode ? 1 : 0,
                      fit: bingeMode ? FlexFit.tight : FlexFit.loose,
                      child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: playerHorizontalPadding,
                      ),
                      child: PlayerVideoPanel(
                        episodeId: widget.episodeId,
                        showSceneHeader: false,
                          hideOverlayControls: true,
                          paintSubtitlesOnVideo: false,
                        hardsubMosaicEnabled: _hardsubMosaicEnabled,
                        hardsubMosaicBand: _hardsubMosaicBand,
                        onHardsubMosaicBandChanged: (HardsubMosaicBand band) {
                          setState(() => _hardsubMosaicBand = band);
                        },
                        onHardsubMosaicDismiss: () {
                          setState(() => _hardsubMosaicEnabled = false);
                        },
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
                          learnedVocabularyWords: learnedVocabularyWords,
                          keyVocabularyWords: keyVocabularyWords,
                          chunkHighlighter: chunkHighlighter,
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
                          // Always enter 跟读 when the episode has cues —
                          // never gate on subtitle display mode / duration.
                          onAssessVisibleLine: state.hasLines
                              ? () => _enterShadowingMode()
                              : null,
                        assessmentUnavailableReason: state.hasLines
                            ? null
                            : '当前没有可跟读的字幕',
                        onCollectWord: (String word) =>
                            _handleCollectWord(word, courseContext),
                        onCollectWordAtTime: (String word, String time) =>
                            _handleCollectWord(word, courseContext, time),
                        onFavoriteWord: _handleFavoriteWord,
                        onPronounce: _stopVideo,
                        onToggleFullscreen: () => _handleOpenFullscreen(
                          course?.episodes ?? const <LibraryEpisodeItem>[],
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
                    ),
                    if (_videoErrorText != null &&
                        !_videoLoading &&
                        !(_videoErrorText!.startsWith('正在')))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: Text(
                          _videoErrorText!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: StudyShellColors.of(context).favorite,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    if (!bingeMode) ...<Widget>[
                      SizedBox(height: compactPlayer ? 4 : 8),
                      StudyModeTabs(
                        value: _studyTab,
                        onChanged: (StudyModeTab tab) {
                          if (tab == StudyModeTab.coach) {
                            unawaited(_openOralCoach(courseContext, activeLine));
                            return;
                          }
                          if (tab == StudyModeTab.shadowing) {
                            _enterShadowingMode();
                            return;
                          }
                          setState(() {
                            _studyTab = tab;
                            _hardsubMosaicEnabled =
                                tab == StudyModeTab.dictation;
                          });
                        },
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                          child: _buildStudyTabBody(
                            courseContext: courseContext,
                            settings: settings,
                            canGenerateAiSubtitles: canGenerateAiSubtitles,
                            visibleAssessment: visibleAssessment,
                            activeLine: activeLine,
                            savedVocabularyWords: savedVocabularyWords,
                            learnedVocabularyWords: learnedVocabularyWords,
                            keyVocabularyWords: keyVocabularyWords,
                            chunkHighlighter: chunkHighlighter,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            StudyBottomControls(
                subtitleMode: state.subtitleMode,
              speed: state.speed,
              isPlaying: state.isPlaying,
                isLooping: _loopSettings.isLooping || state.isLooping,
              position: _videoPosition,
              duration: _videoDuration,
                onSelectSubtitleMode: _handleSetSubtitleMode,
              onCycleSpeed: _handleCycleSpeed,
                onSpeedSelected: _handleSpeedSelected,
                onOpenSpeedSheet: _handleOpenSpeedSheet,
                onOpenQualitySheet: _handleOpenQualitySheet,
              onTogglePlaying: _effectiveTogglePlaying,
                onOpenLoopSheet: _handleOpenLoopSheet,
              onSeek: _handleSeek,
              onToggleFullscreen: () => _handleOpenFullscreen(
                course?.episodes ?? const <LibraryEpisodeItem>[],
              ),
              onOpenOralCoach: () =>
                  unawaited(_openOralCoach(courseContext, activeLine)),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Future<void> _openOralCoach(
    PlayerCourseLookupResult courseContext,
    PlayerSubtitleLine activeLine,
  ) async {
    if (_oralCoachOpen) return;
    _oralCoachOpen = true;
    try {
      setState(() => state.isPlaying = false);
      PlayerSystemMediaControls.updatePlaybackState(isPlaying: false);
      await _videoPlayer?.pause();
      if (!mounted) return;
      final String courseTitle = courseContext.course?.title ?? '';
      final String episodeTitle = courseContext.episode?.title ?? '';
      final String topicSummary = <String>[
        if (courseTitle.trim().isNotEmpty) courseTitle.trim(),
        if (episodeTitle.trim().isNotEmpty) episodeTitle.trim(),
      ].join(' · ');
      final String excerpt = _oralCoachSubtitleExcerpt(state.lines);
      final String currentLine = activeLine.english.trim();
      final Widget coach = StudyOralCoachTab(
        topicSummary: currentLine.isNotEmpty
            ? '当前句 · $currentLine'
            : (topicSummary.isNotEmpty ? topicSummary : '本集视频'),
        articleExcerpt: <String>[
          if (currentLine.isNotEmpty) currentLine,
          if (excerpt.trim().isNotEmpty) excerpt.trim(),
        ].join('\n'),
        courseTitle: courseTitle,
        episodeTitle: episodeTitle,
        hasTranscript: excerpt.isNotEmpty || currentLine.isNotEmpty,
        episodeId: courseContext.episode?.id ?? widget.episodeId,
        // Close the loop: video line → scenario speak → later review weak items.
        initialScenarioId: 'video_line',
      );
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (BuildContext context) => Scaffold(
            backgroundColor: const Color(0xFF14102A),
            appBar: AppBar(title: const Text('英语口语')),
            body: SafeArea(top: false, child: coach),
          ),
        ),
      );
    } finally {
      _oralCoachOpen = false;
    }
  }

  Widget _buildStudyTabBody({
    required PlayerCourseLookupResult courseContext,
    required LearningSettingsState settings,
    required bool canGenerateAiSubtitles,
    required PronunciationTargetSelection visibleAssessment,
    required PlayerSubtitleLine activeLine,
    required Set<String> savedVocabularyWords,
    required Set<String> learnedVocabularyWords,
    required Set<String> keyVocabularyWords,
    SubtitleChunkHighlighter? chunkHighlighter,
  }) {
    switch (_studyTab) {
      case StudyModeTab.subtitles:
        if (state.hasLines) {
          return PlayerTranscriptPanel(
            episodeId: widget.episodeId,
            lines: state.lines,
            activeIndex: state.activeLineIndex,
            timelineFollowEpoch: state.timelineFollowEpoch,
            subtitleMode: state.subtitleMode,
            currentWordIndex: state.currentWordIndex,
            fontScale: settings.fontScale,
            highlightWords: settings.highlightWords,
            subtitleLetterCase: settings.subtitleLetterCase,
            subtitleWordHighlightStyle: settings.subtitleWordHighlightStyle,
            subtitleWordHighlightBorderWidth:
                settings.subtitleWordHighlightBorderWidth,
            fragmentsBySentenceStartMs: _usingAsrSentences
                ? _asrFragmentsBySentenceStartMs
                : const <int, List<PlayerSubtitleLine>>{},
            savedVocabularyWords: savedVocabularyWords,
            learnedVocabularyWords: learnedVocabularyWords,
            keyVocabularyWords: keyVocabularyWords,
            chunkHighlighter: chunkHighlighter,
            onTapLine: _goToLine,
            onCollectWord: (String word) =>
                _handleCollectWord(word, courseContext),
            onCollectWordAtTime: (String word, String time) =>
                _handleCollectWord(word, courseContext, time),
            onFavoriteWord: _handleFavoriteWord,
            onBookmarkLine: (int index) =>
                _handleBookmarkLine(index, courseContext),
            isLineBookmarked: _isLineBookmarked,
            onLoopFromLine: _handleLoopFromLine,
            onDictationLine: _handleDictationLine,
            onAiExplain: _handleAiExplain,
            onAssessLine: _handleAssessLine,
            pronunciationUnavailableReasonForLine:
                _pronunciationUnavailableReasonForLine,
            loopingLineIndex: state.isLooping ? state.activeLineIndex : null,
            isPlaying: state.isPlaying,
            onTogglePlaying: _handleTogglePlaying,
            onPronounce: _stopVideo,
            onRerecognizeEnglish: !_generatingAiSubtitles
                ? () => unawaited(
                    _handleResetEpisodeSubtitles(SubtitleResetSide.english),
                  )
                : null,
            onRerecognizeChinese: !_generatingAiSubtitles
                ? () => unawaited(
                    _handleResetEpisodeSubtitles(SubtitleResetSide.chinese),
                  )
                : null,
            onRegenerateAiLine: _usingAiSubtitles
                ? _handleRegenerateAiLine
                : null,
            onEditEnglishLine: _editEnglishLine,
            onEditSubtitleLine: _editSubtitleLine,
            onResegment: _resegmentSubtitleLines,
            onEditLineNote: _editLineNote,
            lineNotesByStartMs: _lineNotesByStartMs,
            studyDarkStyle: true,
            blindListening:
                _blindListening ||
                SubtitleDisplayMode.isBlind(state.subtitleMode),
            showAiGenerateSubtitles: canGenerateAiSubtitles,
            generatingAiSubtitles: _generatingAiSubtitles,
            aiSubtitleProgressValue: _aiSubtitleProgressValue,
            aiSubtitleProgressText: _aiSubtitleProgressText,
            aiSubtitlePreviewText: _aiSubtitlePreviewText,
            aiSubtitleErrorText: _aiSubtitleErrorText,
            onGenerateAiSubtitles: _generatingAiSubtitles
                ? null
                : _handleGenerateAiSubtitles,
            bilingualPipelineLabel: _bilingualPipelineLabel,
            bilingualPipelineProgressValue: _bilingualPipelineProgress,
            showAiCompleteButton: _bilingualShowAiComplete,
            onAiComplete: _bilingualShowAiComplete
                ? _handleAiCompleteSubtitles
                : null,
            onCancelBilingualPipeline:
                _bilingualPhase == BilingualPipelinePhase.asrProofreading ||
                    _bilingualPhase == BilingualPipelinePhase.ocrRunning ||
                    _bilingualPhase == BilingualPipelinePhase.ocrSlow
                ? _handleCancelBilingualPipeline
                : null,
            onDictionaryOpened: _handleDictionaryOpened,
            onDictionaryClosed: _handleDictionaryClosed,
          );
        }
        if (canGenerateAiSubtitles || _generatingAiSubtitles) {
          return PlayerSubtitleList(
            episodeId: widget.episodeId,
            lines: const <PlayerSubtitleLine>[],
            activeIndex: 0,
            subtitleMode: '双语',
            currentWordIndex: 0,
            fontScale: settings.fontScale,
            highlightWords: settings.highlightWords,
            subtitleLetterCase: settings.subtitleLetterCase,
            savedVocabularyWords: savedVocabularyWords,
            learnedVocabularyWords: learnedVocabularyWords,
            keyVocabularyWords: keyVocabularyWords,
            chunkHighlighter: chunkHighlighter,
            onTapLine: (_) {},
            onCollectWord: (_) {},
            onBookmarkLine: (_) {},
            onLoopFromLine: (_) {},
            onDictationLine: (_) {},
            onAiExplain: (_) {},
            onPronounce: _stopVideo,
            showAiGenerateSubtitles: true,
            generatingAiSubtitles: _generatingAiSubtitles,
            aiSubtitleProgressValue: _aiSubtitleProgressValue,
            aiSubtitleProgressText: _aiSubtitleProgressText,
            aiSubtitlePreviewText: _aiSubtitlePreviewText,
            aiSubtitleErrorText: _aiSubtitleErrorText,
            onGenerateAiSubtitles: _generatingAiSubtitles
                ? null
                : _handleGenerateAiSubtitles,
            bilingualPipelineLabel: _bilingualPipelineLabel,
            bilingualPipelineProgressValue: _bilingualPipelineProgress,
            showAiCompleteButton: _bilingualShowAiComplete,
            onAiComplete: _bilingualShowAiComplete
                ? _handleAiCompleteSubtitles
                : null,
            onCancelBilingualPipeline:
                _bilingualPhase == BilingualPipelinePhase.asrProofreading ||
                    _bilingualPhase == BilingualPipelinePhase.ocrRunning ||
                    _bilingualPhase == BilingualPipelinePhase.ocrSlow
                ? _handleCancelBilingualPipeline
                : null,
            studyDarkStyle: true,
          );
        }
        return const Center(
          child: Text(
            '当前剧集没有可用字幕或视频\n导入本地视频后可用语音识别生成字幕',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.5,
              color: StudyShellTokens.textSecondary,
            ),
          ),
        );
      case StudyModeTab.shadowing:
        // Use active-line target (not on-screen subtitle mode), so 中文/隐藏字幕
        // modes still unlock in-tab mic recording.
        final PronunciationTargetSelection shadowAssessment =
            state.hasLines
            ? _selectPronunciationForLine(state.activeLineIndex)
            : visibleAssessment;
        return StudyShadowingTab(
          // Pin the practice cue — never use visibleLine (null at sentence end).
          line: state.hasLines ? state.activeLine : activeLine,
          hasLine: state.hasLines,
          assessmentTarget: shadowAssessment.target,
          pauseAtSentenceEnd: state.pauseAtSentenceEnd,
          onTogglePauseAtSentenceEnd: () {
            setState(() => state.togglePauseAtSentenceEnd());
          },
          onPreviousSentence: state.hasLines ? _handlePreviousLine : null,
          onNextSentence: state.hasLines ? _handleNextLine : null,
          onReplaySentence: state.hasLines ? _handleReplayLine : null,
          onPlayOriginalBound: (VoidCallback playOriginal) {
            _shadowingPlayOriginal = playOriginal;
          },
          unavailableReason: shadowAssessment.unavailableReason,
          onOpenFullDialog: shadowAssessment.target == null
              ? null
              : () => _handleAssessLine(state.activeLineIndex),
          onUpgradeToCoach: () {
            setState(() => _studyTab = StudyModeTab.coach);
          },
          isSentenceBookmarked:
              state.hasLines && _isLineBookmarked(state.activeLineIndex),
          onBookmarkSentence: state.hasLines
              ? () => _handleBookmarkLine(state.activeLineIndex, courseContext)
              : null,
          episodeId: widget.episodeId,
          videoSource: _localPlayableVideoPath(),
          onRecordingStarted: ({required bool pauseVideo}) {
            if (!pauseVideo) {
              return;
            }
            if (state.isPlaying) {
              setState(() => state.isPlaying = false);
              PlayerSystemMediaControls.updatePlaybackState(isPlaying: false);
              unawaited(_videoPlayer?.pause());
            }
          },
          onDubPlaybackRequested: ({
            required int startMs,
            required int endMs,
            required String userWavPath,
            bool continuous = false,
          }) {
            return _handleDubPlayback(
              startMs: startMs,
              endMs: endMs,
              userWavPath: userWavPath,
              continuous: continuous,
            );
          },
          onExportShareRequested: ({required bool fullEpisode}) {
            return _handleDubExportShare(fullEpisode: fullEpisode);
          },
          onPracticeCompleted: () {
            ref
                .read(learningActivityProvider.notifier)
                .recordShadowingToggle(enabled: true);
            _recordCurrentSentenceStudy();
          },
          onScoreForReview: (int scorePercent) {
            if (!state.hasLines) return;
            final PlayerSubtitleLine line = state.activeLine;
            final PlayerCourseLookupResult ctx =
                resolvePlayerCourseForEpisode(
              courses: ref.read(libraryCatalogProvider),
              episodeId: widget.episodeId,
            );
            unawaited(
              ref.read(dailyReviewProvider.notifier).ingestShadowingFail(
                    episodeId: widget.episodeId,
                    english: line.english,
                    chinese: line.chinese,
                    startMs: line.startMs,
                    endMs: line.endMs,
                    startTime: line.startTime,
                    scorePercent: scorePercent,
                    courseTitle: ctx.course?.title,
                    episodeTitle: ctx.episode == null
                        ? null
                        : '第 ${ctx.episode!.numberStr} 集',
                  ),
            );
          },
        );
      case StudyModeTab.coach:
        return const SizedBox.shrink();
      case StudyModeTab.dictation:
        final List<DictationQueueItem> queue = ref.watch(
          dictationQueueProvider,
        );
        final bool usingQueue = _dictationQueueMode && queue.isNotEmpty;
        final PlayerSubtitleLine dictationLine;
        if (usingQueue) {
          final DictationQueueItem item =
              queue[_dictationQueueIndex.clamp(0, queue.length - 1)];
          dictationLine = PlayerSubtitleLine(
            startTime: item.startTime,
            english: item.english,
            chinese: item.chinese,
            startMs: item.startMs,
            endMs: item.endMs,
          );
        } else {
          dictationLine = activeLine;
        }
        return StudyDictationTab(
          line: dictationLine,
          hasLine: usingQueue || state.hasLines,
          isPlaying: state.isPlaying,
          hardsubMosaicEnabled: _hardsubMosaicEnabled,
          onToggleHardsubMosaic: (bool enabled) {
            setState(() => _hardsubMosaicEnabled = enabled);
          },
          queue: queue,
          queueIndex: usingQueue
              ? _dictationQueueIndex.clamp(0, queue.length - 1)
              : 0,
          usingQueue: usingQueue,
          onSelectQueueIndex: (int index) {
            if (index < 0 || index >= queue.length) return;
            setState(() {
              _dictationQueueMode = true;
              _dictationQueueIndex = index;
            });
            final DictationQueueItem item = queue[index];
            final int lineIndex = state.lines.indexWhere(
              (PlayerSubtitleLine line) =>
                  line.startMs == item.startMs && line.english == item.english,
            );
            if (lineIndex >= 0) {
              _goToLine(lineIndex);
            }
          },
          onClearQueue: () async {
            await ref.read(dictationQueueProvider.notifier).clear();
            if (!mounted) return;
            setState(() {
              _dictationQueueMode = false;
              _dictationQueueIndex = 0;
            });
            _showMessage('已清空听写队列');
          },
          onReplay: () {
            if (state.speed != '0.8×') {
              _handleSpeedSelected('0.8×');
            }
            _handleReplayLine();
          },
          onPrevious: () {
            if (usingQueue && _dictationQueueIndex > 0) {
              setState(() => _dictationQueueIndex -= 1);
              return;
            }
            _handlePreviousLine();
          },
          onNext: () {
            if (usingQueue && _dictationQueueIndex < queue.length - 1) {
              setState(() => _dictationQueueIndex += 1);
              return;
            }
            _handleNextLine();
          },
          onAddToQueue: () =>
              _handleAddDictationQueue(courseContext, difficult: false),
          onMarkDifficult: () =>
              _handleAddDictationQueue(courseContext, difficult: true),
          onDictationResult: (DictationDiffResult result) {
            _handleDictationResult(result, courseContext, dictationLine);
          },
        );
      case StudyModeTab.practice:
        return StudyPracticeTab(
          lines: state.lines,
          activeIndex: state.activeLineIndex,
          onCollectWord: (String word) {
            _handleFavoriteWord(word);
          },
          onGoToLine: _goToLine,
          onReplayLine: _handleReplayLine,
        );
      case StudyModeTab.wordCards:
        final int learnThreshold =
            ref.watch(adaptiveReadingFreqThresholdProvider);
        syncAdaptiveFreqThresholdToPrefs(learnThreshold);
        final ReadingFrequencyLexicon? lexicon =
            ref.watch(readingFrequencyLexiconProvider).asData?.value;
        final List<EpisodeWordCard> cards = buildEpisodeWordCards(
          episodeId: widget.episodeId,
          lines: state.lines,
          words: ref.watch(wordBookProvider),
          phrases: ref.watch(phraseBookProvider),
          learnThreshold: learnThreshold,
          freqRankOf: lexicon?.rankOf,
        );
        return StudyWordCardsTab(
          cards: cards,
          episodeId: widget.episodeId,
          onJumpToCard: _handleJumpToWordCard,
          onFavorite: (EpisodeWordCard card) {
            _handleFavoriteWord(card.text);
          },
          onSpeak: (EpisodeWordCard card) {
            unawaited(_speakWordCard(card));
          },
        );
    }
  }

  void _handleJumpToWordCard(EpisodeWordCard card) {
    if (!state.hasLines) return;
    int lineIndex = -1;
    if (card.startMs != null) {
      lineIndex = state.lines.indexWhere(
        (PlayerSubtitleLine line) =>
            line.startMs <= card.startMs! && card.startMs! < line.endMs,
      );
      if (lineIndex < 0) {
        // Nearest line by start time.
        int best = 0;
        int bestDelta = 1 << 30;
        for (int i = 0; i < state.lines.length; i++) {
          final int delta = (state.lines[i].startMs - card.startMs!).abs();
          if (delta < bestDelta) {
            bestDelta = delta;
            best = i;
          }
        }
        lineIndex = best;
      }
    }
    if (lineIndex < 0 && card.exampleEn != null) {
      lineIndex = state.lines.indexWhere(
        (PlayerSubtitleLine line) =>
            line.english.trim().toLowerCase() ==
            card.exampleEn!.trim().toLowerCase(),
      );
    }
    if (lineIndex < 0) {
      final String needle = card.text.toLowerCase();
      lineIndex = state.lines.indexWhere(
        (PlayerSubtitleLine line) =>
            line.english.toLowerCase().contains(needle),
      );
    }
    if (lineIndex >= 0) {
      setState(() => _studyTab = StudyModeTab.subtitles);
      _goToLine(lineIndex);
      _handleReplayLine();
    } else {
      _showMessage('未找到对应字幕句');
    }
  }

  Future<void> _speakWordCard(EpisodeWordCard card) async {
    try {
      final String text = card.text.trim();
      if (text.isEmpty) return;
      String? recorded = card.audioUrl?.trim();
      if (recorded == null || recorded.isEmpty) {
        final LearningSettingsState settings =
            ref.read(learningSettingsProvider);
        final entry = await ref
            .read(wordLookupServiceProvider)
            .publicLookup
            ?.call(text, settings);
        recorded = entry?.audioUrl;
      }
      await ref.read(wordPronunciationServiceProvider).speak(
            text,
            recordedUrl: recorded,
            allowSynthesisFallback: true,
          );
    } on WordPronunciationException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  void _handleSpeedSelected(String nextSpeed) {
    setState(() {
      state.selectSpeed(nextSpeed);
    });
    _applyPlaybackMode();
  }

  void _handleCycleSpeed() {
    _handleSpeedSelected(StudyBottomControls.nextSpeed(state.speed));
  }

  void _handleSetSubtitleMode(String mode) {
    final String normalized = SubtitleDisplayMode.normalize(mode);
    setState(() {
      state.setSubtitleMode(normalized);
      _blindListening = SubtitleDisplayMode.isBlind(normalized);
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
    // Embedded tracks are reference-only — never paint them on the video.
    setState(() {
      _selectedEmbeddedSubtitleId = null;
      if (track != null) {
        _blindListening = false;
      }
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
    _pausedForLookup = false;
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

  /// On the 跟读 tab, bottom play matches the toolbar volume button.
  void _handleShadowingTogglePlaying() {
    if (_pronunciationDialogActive) return;
    _pausedForLookup = false;
    if (state.isPlaying) {
      setState(() => state.isPlaying = false);
      _applyPlaybackMode();
      return;
    }
    final VoidCallback? playOriginal = _shadowingPlayOriginal;
    if (playOriginal != null) {
      playOriginal();
      return;
    }
    if (state.hasLines) {
      _handleReplayLine();
      return;
    }
    _handleTogglePlaying();
  }

  VoidCallback get _effectiveTogglePlaying =>
      _studyTab == StudyModeTab.shadowing
      ? _handleShadowingTogglePlaying
      : _handleTogglePlaying;

  void _handleSystemPlay() {
    if (!_oralCoachOpen && !state.isPlaying) {
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

  void _enterShadowingMode() {
    setState(() {
      state.isShadowing = true;
      if (!state.pauseAtSentenceEnd) {
        state.togglePauseAtSentenceEnd();
      }
      _studyTab = StudyModeTab.shadowing;
      _hardsubMosaicEnabled = false;
    });
  }

  void _handleToggleShadowing() {
    _enterShadowingMode();
  }

  void _handleDictionaryOpened() {
    if (!state.isPlaying || _pronunciationDialogActive) {
      return;
    }
    _pausedForLookup = true;
    setState(() => state.isPlaying = false);
    PlayerSystemMediaControls.updatePlaybackState(isPlaying: false);
    unawaited(_videoPlayer?.pause());
  }

  void _handleDictionaryClosed() {
    if (!_pausedForLookup) {
      return;
    }
    _pausedForLookup = false;
    if (_pronunciationDialogActive || !mounted) {
      return;
    }
    setState(() => state.isPlaying = true);
    _applyPlaybackMode();
  }

  void _handleToggleEpisodeFavorite(PlayerCourseLookupResult courseContext) {
    if (!state.hasLines) {
      _showMessage('当前没有可收藏的句子');
      return;
    }
    _handleBookmarkLine(state.activeLineIndex, courseContext);
  }

  bool _isLineBookmarked(int index) {
    if (!state.hasLines || index < 0 || index >= state.lines.length) {
      return false;
    }
    final PlayerSubtitleLine line = state.lines[index];
    return ref.read(wordBookProvider.notifier).containsFavoriteSentence(
          english: line.english,
          lineKey: '${line.startMs}-${line.endMs}',
          episodeId: widget.episodeId,
        );
  }

  void _handleOpenSpeedSheet() {
    final StudyShellColors colors = StudyShellColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.card,
      builder: (BuildContext context) {
        final StudyShellColors sheetColors = StudyShellColors.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: Text(
                  '选择倍速',
                  style: TextStyle(
                    color: sheetColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final String option in PlayerVideoPanel.kSpeedOptions)
                ListTile(
                  title: Text(
                    option,
                    style: TextStyle(
                      color: option == state.speed
                          ? sheetColors.accent
                          : sheetColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: option == state.speed
                      ? Icon(Icons.check_rounded, color: sheetColors.accent)
                      : null,
                  onTap: () {
                    Navigator.of(context).pop();
                    _handleSpeedSelected(option);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _handleOpenQualitySheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: StudyShellColors.of(context).card,
      builder: (BuildContext context) {
        final StudyShellColors colors = StudyShellColors.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '画质',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '本地视频按源文件清晰度播放，当前为「超清」。网络课程的多码率切换将在后续版本接入。',
                  style: TextStyle(color: colors.textSecondary, height: 1.45),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleAddDictationQueue(
    PlayerCourseLookupResult courseContext, {
    required bool difficult,
  }) async {
    if (!state.hasLines) {
      return;
    }
    final PlayerSubtitleLine line = state.activeLine;
    final LibraryCourseData? course = courseContext.course;
    final LibraryEpisodeItem? episode = courseContext.episode;
    final DictationQueueItem item = DictationQueueItem(
      id: DictationQueueItem.buildId(
        episodeId: episode?.id ?? widget.episodeId,
        startMs: line.startMs,
        endMs: line.endMs,
        english: line.english,
      ),
      english: line.english,
      chinese: line.chinese,
      startMs: line.startMs,
      endMs: line.endMs,
      startTime: line.startTime,
      episodeId: episode?.id ?? widget.episodeId,
      courseTitle: course?.title,
      episodeTitle: episode == null ? null : '第 ${episode.numberStr} 集',
      difficult: difficult,
      addedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final bool added = await ref
        .read(dictationQueueProvider.notifier)
        .addOrUpdate(item);
    if (difficult) {
      await ref.read(dictationQueueProvider.notifier).markDifficult(item.id);
    }
    // Always enroll the line into the unified FSRS clip queue.
    unawaited(
      ref.read(dailyReviewProvider.notifier).ingestClip(
            episodeId: episode?.id ?? widget.episodeId,
            english: line.english,
            chinese: line.chinese,
            startMs: line.startMs,
            endMs: line.endMs,
            startTime: line.startTime,
            courseTitle: course?.title,
            episodeTitle:
                episode == null ? '本集' : '第 ${episode.numberStr} 集',
            origin: difficult ? 'dictation_hard' : 'dictation',
            softGrade: difficult ? fsrs.Rating.hard : null,
          ),
    );
    if (!mounted) return;
    setState(() {
      _dictationQueueMode = true;
      final List<DictationQueueItem> queue = ref.read(dictationQueueProvider);
      final int index = queue.indexWhere(
        (DictationQueueItem e) => e.id == item.id,
      );
      _dictationQueueIndex = index >= 0 ? index : 0;
    });
    if (difficult) {
      _showMessage(
        added ? '已加入听写队列，并进入统一复习' : '已标记困难并同步到统一复习',
      );
    } else {
      _showMessage(added ? '已加入听写队列（同步复习）' : '该句已在听写队列中');
    }
  }

  void _handleDictationResult(
    DictationDiffResult result,
    PlayerCourseLookupResult courseContext,
    PlayerSubtitleLine line,
  ) {
    if (result.exact) return;
    final LibraryCourseData? course = courseContext.course;
    final LibraryEpisodeItem? episode = courseContext.episode;
    unawaited(
      ref.read(dailyReviewProvider.notifier).ingestClip(
            episodeId: episode?.id ?? widget.episodeId,
            english: line.english,
            chinese: line.chinese,
            startMs: line.startMs,
            endMs: line.endMs,
            startTime: line.startTime,
            courseTitle: course?.title,
            episodeTitle:
                episode == null ? '本集' : '第 ${episode.numberStr} 集',
            origin: 'dictation',
            softGrade: fsrs.Rating.again,
          ),
    );
    int saved = 0;
    for (final String word in result.reviewWords) {
      final bool ok = ref.read(wordBookProvider.notifier).addFavoriteWord(
            rawWord: word,
            episodeId: episode?.id ?? widget.episodeId,
            course: course?.title ?? '课程',
            episode: episode == null ? '本集' : '第 ${episode.numberStr} 集',
            time: line.startTime,
            lineKey: '${line.startMs}-${line.endMs}',
            sentence: line.english,
            chinese: line.chinese,
          );
      if (ok) saved += 1;
    }
    if (saved > 0) {
      _showMessage('已将 $saved 个错/漏词加入单词本，整句进入统一复习');
    } else {
      _showMessage('本句已进入统一复习队列');
    }
  }

  void _handleToggleLoop() {
    setState(state.toggleLoop);
    _syncTranscriptReader();
    _showMessage(state.isLooping ? '已开启单句循环' : '已关闭单句循环');
    if (state.isLooping && state.hasLines) {
      _seekToActiveLine();
    }
  }

  Future<void> _handleOpenLoopSheet() async {
    final StudyLoopSettings? next = await showStudyLoopSheet(
      context,
      initial: _loopSettings,
      currentPositionMs: _videoPosition.inMilliseconds,
    );
    if (!mounted || next == null) {
      return;
    }
    setState(() {
      _loopSettings = next;
      _loopCompleted = 0;
      _loopIntervalPending = false;
      state.isLooping = next.mode == StudyLoopMode.sentence;
    });
    _syncTranscriptReader();
    switch (next.mode) {
      case StudyLoopMode.off:
        _showMessage('已关闭循环');
      case StudyLoopMode.sentence:
        _showMessage('已开启单句循环');
        if (state.hasLines) {
          _seekToActiveLine();
        }
      case StudyLoopMode.ab:
        _showMessage('已开启 A-B 复读');
        final int? start = next.abStartMs;
        if (start != null) {
          final Duration target = Duration(milliseconds: start);
          setState(() {
            _videoPosition = target;
            state.positionMs = start;
            state.isPlaying = true;
          });
          await _videoPlayer?.seek(target);
          await _videoPlayer?.play();
        }
      case StudyLoopMode.full:
        _showMessage('已开启全片循环');
    }
  }

  Future<void> _applyLoopRestart() async {
    if (_loopSettings.countLimit > 0) {
      _loopCompleted += 1;
      if (_loopCompleted >= _loopSettings.countLimit) {
        setState(() {
          _loopSettings = _loopSettings.copyWith(mode: StudyLoopMode.off);
          state.isLooping = false;
          state.isPlaying = false;
          _loopCompleted = 0;
        });
        await _videoPlayer?.pause();
        _showMessage('循环次数已完成');
        return;
      }
    }
    if (_loopSettings.intervalSec > 0) {
      if (_loopIntervalPending) {
        return;
      }
      _loopIntervalPending = true;
      setState(() => state.isPlaying = false);
      await _videoPlayer?.pause();
      await Future<void>.delayed(Duration(seconds: _loopSettings.intervalSec));
      _loopIntervalPending = false;
      if (!mounted || _loopSettings.mode == StudyLoopMode.off) {
        return;
      }
    }
    if (_loopSettings.mode == StudyLoopMode.full) {
      setState(() {
        state.selectLine(0);
        state.isPlaying = true;
        _videoPosition = Duration.zero;
      });
      await _videoPlayer?.seek(Duration.zero);
      await _videoPlayer?.play();
      return;
    }
    if (_loopSettings.mode == StudyLoopMode.ab && _loopSettings.hasAbRange) {
      final Duration target = Duration(milliseconds: _loopSettings.abStartMs!);
      setState(() {
        _videoPosition = target;
        state.positionMs = target.inMilliseconds;
        state.isPlaying = true;
      });
      await _videoPlayer?.seek(target);
      await _videoPlayer?.play();
      return;
    }
    _seekToActiveLine();
    setState(() => state.isPlaying = true);
    await _videoPlayer?.play();
  }

  void _handleToggleMuted() {
    final double nextVolume = _isMuted ? 1 : 0;
    _handleVolumeChanged(nextVolume);
    _showMessage(_isMuted ? '已静音' : '已恢复声音');
  }

  Future<void> _handleGenerateAiSubtitles({
    bool forceRegenerate = false,
    bool speechOnly = false,
  }) async {
    if (_generatingAiSubtitles) {
      return;
    }
    final String? videoPath = _videoAsset;
    if (videoPath == null || videoPath.isEmpty) {
      _showMessage('当前视频不可用');
      return;
    }
    // Chinese softsubs with missing English: fill via OCR/translate instead of
    // Whisper (avoids short-link / season-id ArgumentError toast).
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
          speechOnly ? const <PlayerSubtitleLine>[] : await _ensureOfficialReferenceSubtitles();
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
      final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner();
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
      if (lines.isNotEmpty) {
        await _persistCompletedBilingualSubtitles(lines);
        if (!mounted) return;
        await _syncManualSubtitlesToCloud(lines, sourceOrigin: 'asr');
        if (!mounted) return;
      }
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
    // Prefer a real BV/av watch URL — never pass bilibili-season-* ids or raw
    // short links into fetchOfficialSubtitleTracks (throws ArgumentError).
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
      // Official pull is best-effort — never abort AI / ASR for short-link noise.
      return existing;
    }
  }

  Future<void> _handleUserRegenerateSubtitles() async {
    final bool hasManual = await episodeHasManualSubtitleEdits(
      episodeId: widget.episodeId,
      englishLocks: _manualEnglishByStartMs,
      chineseLocks: _manualChineseByStartMs,
    );
    if (!mounted) {
      return;
    }
    if (hasManual) {
      final bool confirmed = await confirmManualSubtitleDestructiveAction(
        context,
        action: ManualSubtitleDestructiveAction.overwrite,
      );
      if (!confirmed || !mounted) {
        return;
      }
      _manualEnglishByStartMs.clear();
      _manualChineseByStartMs.clear();
    }
    final PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: widget.episodeId,
    );
    // Explicit「重新识别」on hardsub/双语课 still uses speech; otherwise OCR path.
    if (SubtitleSourcePolicy.isHardsubHint(
      episode: resource.episode,
      course: resource.course,
      sourceUrl: resource.episode?.sourceUrl,
    )) {
      await _forceHardsubSpeechRegenerate(resource);
      return;
    }
    await _restartEnglishFillFromChineseAndOcr();
  }

  Future<void> _forceHardsubSpeechRegenerate(
    PlayerCourseLookupResult resource,
  ) async {
    if (!mounted) {
      return;
    }
    final String? sourceKey = _episodeSourceKey(resource);
    await deletePersistedBilingualSubtitleFiles(episodeId: widget.episodeId);
    await clearHardsubChineseTranslationMarker(episodeId: widget.episodeId);
    if ((sourceKey ?? '').isNotEmpty) {
      try {
        await BilibiliImportService.withCookie(
          ref.read(learningSettingsProvider).resolvedBilibiliCookieHeader,
        ).clearOfficialSubtitleFiles(sourceKey);
      } catch (_) {}
    }
    final String? videoPath = _videoAsset ?? resource.videoAsset;
    if (isUsableLocalVideoPath(videoPath)) {
      try {
        await const AsrSubtitleCache().delete(
          episodeId: widget.episodeId,
          videoPath: videoPath!,
        );
      } catch (_) {}
    }
    if (!mounted) {
      return;
    }
    setState(() {
      state.loadLines(const <PlayerSubtitleLine>[]);
      _usingAiSubtitles = false;
      _usingAsrSentences = false;
      _asrFragmentsBySentenceStartMs = const <int, List<PlayerSubtitleLine>>{};
      _referenceSubtitleLines = const <PlayerSubtitleLine>[];
      _hasOfficialEnglish = false;
      _bilingualPhase = BilingualPipelinePhase.asrProofreading;
      _bilingualPipelineLabel = '正在用语音重新识别英文字幕…';
      _bilingualShowAiComplete = false;
    });
    _showMessage('硬字幕课正在用语音重新识别，完成后会自动翻译中文');
    // One owner: import queue Whisper EN → EN→ZH (persists sentences + marker).
    unawaited(
      enqueueSubtitleCompletionForEpisode(
        episodeId: widget.episodeId,
        videoPath: videoPath,
        zhSubtitlePath: null,
        enSubtitlePath: null,
        sourceUrl: resource.episode?.sourceUrl,
        course: resource.course,
        episode: resource.episode,
        force: true,
        forceSpokenLanguage: SpokenLanguage.english,
      ),
    );
    SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
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
    // Drop machine-translation / ASR sentence cache so speech can rewrite.
    await deletePersistedBilingualSubtitleFiles(episodeId: widget.episodeId);
    _manualEnglishByStartMs.clear();
    _manualChineseByStartMs.clear();
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
        course: resource.course,
        episode: resource.episode,
        force: true,
      ),
    );
    _showMessage('正在按语音重新生成字幕（与语音不一致时以 ASR 为准）');
    SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
    unawaited(() async {
      await _maybeStartBilingualPipeline(forRegenerate: true);
      try {
        await _bilingualPipeline?.proofreadEnglishWithAsr(force: true);
      } catch (_) {}
    }());
  }

  Future<void> _handleRegenerateAiSubtitles() async {
    final bool hasManual = await episodeHasManualSubtitleEdits(
      episodeId: widget.episodeId,
      englishLocks: _manualEnglishByStartMs,
      chineseLocks: _manualChineseByStartMs,
    );
    if (!mounted) {
      return;
    }
    final bool confirmed;
    if (hasManual) {
      confirmed = await confirmManualSubtitleDestructiveAction(
        context,
        action: ManualSubtitleDestructiveAction.overwrite,
      );
    } else {
      confirmed =
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
    }
    if (!confirmed || !mounted) return;
    if (hasManual) {
      _manualEnglishByStartMs.clear();
      _manualChineseByStartMs.clear();
      await clearManualSubtitleLocks(episodeId: widget.episodeId);
    }
    if (!mounted) return;
    _showMessage('正在重新生成 AI 字幕，当前字幕会保留到生成成功。');
    await _handleGenerateAiSubtitles(forceRegenerate: true);
  }

  Future<void> _handleResetEpisodeSubtitles(SubtitleResetSide side) async {
    if (!mounted) {
      return;
    }

    final bool hasManual = await episodeHasManualSubtitleEdits(
      episodeId: widget.episodeId,
      englishLocks: _manualEnglishByStartMs,
      chineseLocks: _manualChineseByStartMs,
    );
    if (!mounted) {
      return;
    }
    if (hasManual) {
      final bool confirmed = await confirmManualSubtitleDestructiveAction(
        context,
        action: ManualSubtitleDestructiveAction.delete,
      );
      if (!confirmed || !mounted) {
        return;
      }
    }

    if (widget.episodeId.startsWith('oral_core_9000-') &&
        side != SubtitleResetSide.chinese) {
      await _handleGenerateAiSubtitles(forceRegenerate: true, speechOnly: true);
      return;
    }

    final PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: widget.episodeId,
    );
    final LibraryCourseData? course = resource.course;
    final LibraryEpisodeItem? episode = resource.episode;
    if (course == null || episode == null) {
      if (side == SubtitleResetSide.chinese) {
        _showMessage('当前无法单独重译中文，请先重新识别英文字幕。');
      } else {
        await _handleGenerateAiSubtitles(forceRegenerate: true, speechOnly: true);
      }
      return;
    }
    _manualEnglishByStartMs.clear();
    _manualChineseByStartMs.clear();
    final String cookie = ref
        .read(learningSettingsProvider)
        .resolvedBilibiliCookieHeader;
    final LibraryCatalogNotifier catalog = ref.read(
      libraryCatalogProvider.notifier,
    );
    try {
      switch (side) {
        case SubtitleResetSide.chinese:
          final bool hasEnglish = state.lines.any(
            (PlayerSubtitleLine line) => looksEnglish(line.english),
          );
          if (!hasEnglish) {
            _showMessage('当前没有英文字幕，无法重译中文。请先重新识别英文字幕（语音 ASR）。');
            return;
          }
          await resetEpisodeChineseSubtitles(
            catalog: catalog,
            course: course,
            episode: episode,
            bilibiliCookieHeader: cookie,
            fallbackEnglishLines: state.lines,
          );
          if (!mounted) {
            return;
          }
          setState(() {
            state.replaceLines(
              state.lines
                  .map(
                    (PlayerSubtitleLine line) => PlayerSubtitleLine(
                      startTime: line.startTime,
                      english: line.english,
                      chinese: '',
                      startMs: line.startMs,
                      endMs: line.endMs,
                      words: line.words,
                    ),
                  )
                  .toList(growable: false),
            );
            _bilingualPhase = BilingualPipelinePhase.asrProofreading;
            _bilingualPipelineLabel = '正在用英文重译中文字幕…';
            _bilingualPipelineProgress = 0.08;
            _bilingualShowAiComplete = false;
          });
          ref.read(subtitleCompletionStatusProvider.notifier).reportProgress(
            episode.id,
            '正在用英文重译中文字幕…',
            needEnglish: false,
            needChinese: true,
            status: SubtitleCompletionStatus.running,
          );
          _showMessage('已清空中文，正在用英文字幕重新翻译');
          break;
        case SubtitleResetSide.english:
          await resetEpisodeEnglishSubtitles(
            catalog: catalog,
            course: course,
            episode: episode,
            bilibiliCookieHeader: cookie,
            fallbackChineseLines: state.lines,
          );
          if (!mounted) {
            return;
          }
          setState(() {
            state.replaceLines(
              state.lines
                  .map(
                    (PlayerSubtitleLine line) => PlayerSubtitleLine(
                      startTime: line.startTime,
                      english: '',
                      chinese: line.chinese,
                      startMs: line.startMs,
                      endMs: line.endMs,
                    ),
                  )
                  .toList(growable: false),
            );
            _usingAiSubtitles = false;
            _usingAsrSentences = false;
            _bilingualPhase = BilingualPipelinePhase.asrProofreading;
            _bilingualPipelineLabel = '正在用语音重新识别英文字幕…';
            _bilingualPipelineProgress = 0.08;
            _bilingualShowAiComplete = false;
          });
          ref.read(subtitleCompletionStatusProvider.notifier).reportProgress(
            episode.id,
            '正在用语音重新识别英文字幕…',
            needEnglish: true,
            needChinese: false,
            status: SubtitleCompletionStatus.running,
          );
          _showMessage('已清空英文，正在语音 ASR（不会用中文翻译英文）');
          break;
        case SubtitleResetSide.both:
          await resetEpisodeSubtitles(
            catalog: catalog,
            course: course,
            episode: episode,
            bilibiliCookieHeader: cookie,
            requeueFill: true,
          );
          if (!mounted) {
            return;
          }
          setState(() {
            state.replaceLines(const <PlayerSubtitleLine>[]);
            _referenceSubtitleLines = const <PlayerSubtitleLine>[];
            _usingAiSubtitles = false;
            _usingAsrSentences = false;
            _asrFragmentsBySentenceStartMs =
                const <int, List<PlayerSubtitleLine>>{};
            _bilingualPhase = BilingualPipelinePhase.asrProofreading;
            _bilingualPipelineLabel = '正在重新识别：先 ASR 英文，再翻译中文…';
            _bilingualPipelineProgress = 0.08;
            _bilingualShowAiComplete = false;
          });
          ref.read(subtitleCompletionStatusProvider.notifier).reportProgress(
            episode.id,
            '正在重新识别：先 ASR 英文，再翻译中文…',
            needEnglish: true,
            needChinese: true,
            status: SubtitleCompletionStatus.running,
          );
          _showMessage('本集字幕已清空，正在后台：ASR 英文 → 翻译中文');
          break;
      }
      SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
    } catch (e) {
      if (!mounted) {
        return;
      }
      _showMessage('重新识别失败：$e');
    }
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
    final int startMs = state.lines[index].startMs;
    final bool lineManual = lineHasManualSubtitleEdit(
      startMs: startMs,
      englishLocks: _manualEnglishByStartMs,
      chineseLocks: _manualChineseByStartMs,
    );
    if (lineManual) {
      final bool confirmed = await confirmManualSubtitleDestructiveAction(
        context,
        action: ManualSubtitleDestructiveAction.overwrite,
        forSingleLine: true,
      );
      if (!confirmed || !mounted) {
        return;
      }
      _manualEnglishByStartMs.remove(startMs);
      _manualChineseByStartMs.remove(startMs);
      await saveManualEnglishLocks(
        episodeId: widget.episodeId,
        locks: _manualEnglishByStartMs,
      );
      await saveManualChineseLocks(
        episodeId: widget.episodeId,
        locks: _manualChineseByStartMs,
      );
      if (!mounted) {
        return;
      }
    }
    _showMessage('正在重新生成当前句，失败时会保留原句。');
    try {
      final String asrVideoPath = await _resolveAsrVideoPath(videoPath);
      final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner();
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
    final String lineKey = '${line.startMs}-${line.endMs}';
    if (ref.read(wordBookProvider.notifier).containsFavoriteSentence(
          english: line.english,
          lineKey: lineKey,
          episodeId: widget.episodeId,
        )) {
      _showMessage('该句子已在句子库中');
      return;
    }
    // Sentence favorite → 句子库 (VocabCardKind.pattern). Never paint every word.
    final bool added = _favoriteLexemeToWordCard(
      line.english,
      line: line,
      courseContext: courseContext,
      definitionCn: line.chinese.trim().isEmpty ? null : line.chinese.trim(),
      cardKind: VocabCardKind.pattern,
    );
    if (added) {
      ref.read(learningActivityProvider.notifier).recordSentenceSaved();
    }
    _showMessage(added ? '已收藏到句子库' : '未能收藏该句子');
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
    // Primary: collect the lexeme onto 词卡 with AI enrichment.
    final bool isPhrase = normalizeLexeme(word).contains(' ');
    final bool addedCard = _favoriteLexemeToWordCard(
      word,
      line: line,
      courseContext: courseContext,
      cardKind: isPhrase ? VocabCardKind.phrase : null,
    );
    if (addedCard) {
      if (isPhrase) {
        ref.read(learningActivityProvider.notifier).recordPhraseSaved();
      } else {
        ref.read(learningActivityProvider.notifier).recordWordSaved();
      }
      _showMessage('已收藏「${normalizeLexeme(word)}」到单词本');
      return;
    }
    // Fallback: keep whole-line phrase book for non-lexeme selections.
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
      ref.read(learningActivityProvider.notifier).recordSentenceSaved();
    }
    _showMessage(added ? '成功收藏例句到短语库！' : '该例句已经在您的短语库中！');
  }

  void _handleFavoriteWord(String word, [String? definitionCn]) {
    if (!state.hasLines) return;
    final PlayerSubtitleLine line = state.activeLine;
    final PlayerCourseLookupResult courseContext =
        resolvePlayerCourseForEpisode(
          courses: ref.read(libraryCatalogProvider),
          episodeId: widget.episodeId,
        );
    final String lexeme = normalizeLexeme(word);
    final bool isPhrase = lexeme.contains(' ');
    final bool added = _favoriteLexemeToWordCard(
      lexeme,
      line: line,
      courseContext: courseContext,
      definitionCn: definitionCn,
      cardKind: isPhrase ? VocabCardKind.phrase : null,
    );
    if (added) {
      if (isPhrase) {
        ref.read(learningActivityProvider.notifier).recordPhraseSaved();
      } else {
        ref.read(learningActivityProvider.notifier).recordWordSaved();
      }
    }
    _showMessage(
      added
          ? '已收藏到单词本「$lexeme」，正在生成 AI 解析 / 助记 / 例句…'
          : '未能收藏，请选择英文单词、词组或短句型。',
    );
  }

  bool _favoriteLexemeToWordCard(
    String raw, {
    required PlayerSubtitleLine line,
    required PlayerCourseLookupResult courseContext,
    String? definitionCn,
    VocabCardKind? cardKind,
  }) {
    final LibraryEpisodeItem? episode = courseContext.episode;
    final String lexeme = normalizeLexeme(raw);
    final String? fromCard = definitionCn?.trim();
    final bool added = ref
        .read(wordBookProvider.notifier)
        .addFavoriteWord(
          rawWord: lexeme,
          cardKind: cardKind,
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
    if (added) {
      unawaited(
        ref
            .read(vocabCardEnrichmentServiceProvider)
            .enrichFavorite(
              rawWord: lexeme,
              contextSentence: line.english,
              contextChinese: line.chinese,
            ),
      );
    }
    return added;
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
    final PlayerCourseLookupResult lookup = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: widget.episodeId,
    );
    final String? courseId = lookup.course?.id;
    if (courseId == null) {
      return;
    }
    unawaited(
      ref
          .read(progressSyncServiceProvider)
          .pushThrottled(
            courseId: courseId,
            lessonId: widget.episodeId,
            positionSec: position.inMilliseconds / 1000.0,
          ),
    );
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
      _studyTab = StudyModeTab.dictation;
      _hardsubMosaicEnabled = true;
    });
    _seekToActiveLine();
    final PlayerCourseLookupResult courseContext =
        resolvePlayerCourseForEpisode(
          courses: ref.read(libraryCatalogProvider),
          episodeId: widget.episodeId,
        );
    unawaited(_handleAddDictationQueue(courseContext, difficult: false));
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
    final Set<String> learnedVocabularyWords = ref.watch(learnedVocabularyProvider);
    final Set<String> keyVocabularyWords =
        ref.read(recommendedWordsProvider);
    final SubtitleChunkHighlighter? chunkHighlighter = ref
        .read(subtitleChunkHighlighterProvider)
        .asData
        ?.value;
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
            learnedVocabularyWords: learnedVocabularyWords,
            keyVocabularyWords: keyVocabularyWords,
            chunkHighlighter: chunkHighlighter,
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
            isLineBookmarked: _isLineBookmarked,
            onLoopFromLine: _handleLoopFromLine,
            onDictationLine: _handleDictationLine,
            onAiExplain: _handleAiExplain,
            onRegenerateAiLine: _usingAiSubtitles
                ? _handleRegenerateAiLine
                : null,
            onEditEnglishLine: _editEnglishLine,
            onEditSubtitleLine: _editSubtitleLine,
            onResegment: _resegmentSubtitleLines,
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

  String? _localPlayableVideoPath() {
    return _catalogLocalVideoPath();
  }

  Future<void> _stopDubPlayback() async {
    _dubPlaybackActive = false;
    await _dubMixPlayer?.dispose();
    _dubMixPlayer = null;
    _dubWindowTimer?.cancel();
    _dubWindowTimer = null;
    await _dubPositionSubscription?.cancel();
    _dubPositionSubscription = null;
    try {
      await _dubOverlayPlayer?.stop();
    } catch (_) {}
    try {
      await _videoPlayer?.setVolume(_volumeLevel * 100);
    } catch (_) {}
  }

  Future<void> _handleDubPlayback({
    required int startMs,
    required int endMs,
    required String userWavPath,
    bool continuous = false,
  }) async {
    final Player? player = _videoPlayer;
    if (player == null || !_videoReady) {
      _showMessage('视频尚未就绪，无法配音回放。');
      return;
    }
    await _stopDubPlayback();
    _dubOverlayPlayer ??= ref.read(pronunciationPreviewPlayerFactoryProvider)();

    final List<DubTake> takes;
    if (continuous) {
      takes = await DubSessionStore.instance.loadTakes(widget.episodeId);
    } else {
      takes = <DubTake>[
        DubTake(
          episodeId: widget.episodeId,
          lineId: '$startMs-$endMs',
          startMs: startMs,
          endMs: endMs,
          english: '',
          userWavPath: userWavPath,
          createdAt: DateTime.now(),
        ),
      ];
    }
    if (takes.isEmpty) {
      _showMessage('还没有可回放的配音。');
      return;
    }

    final int playStart = continuous ? takes.first.startMs : startMs;
    final int playEnd = continuous ? takes.last.endMs : endMs;
    final String? videoPath = _localPlayableVideoPath();
    if (videoPath == null) {
      _showMessage('请先下载视频，再生成环境音配音。');
      return;
    }
    _showMessage('正在分离环境音并合成配音…');
    try {
      final String? accompaniment = await _dubAccompanimentService
          .ensureAccompaniment(
            episodeId: widget.episodeId,
            videoSource: videoPath,
          );
      if (accompaniment == null) {
        _showMessage('环境音分离不可用，请配置人声分离服务后重试。');
        return;
      }
      final DubExportResult mix = await _dubExportService.export(
        episodeId: widget.episodeId,
        videoSource: videoPath,
        takes: takes,
        rangeStartMs: playStart,
        rangeEndMs: playEnd,
        accompanimentPath: accompaniment,
      );
      if (!mounted) return;
      final Player audio = Player();
      _dubMixPlayer = audio;
      await audio.open(Media(Uri.file(mix.outputPath).toString()), play: false);
      await audio.setRate(state.playbackRate);
      await audio.setVolume(_volumeLevel * 100);
      await player.pause();
      await player.seek(Duration(milliseconds: playStart));
      _dubPlaybackActive = true;
      await player.setVolume(0);
      _dubPositionSubscription = player.stream.position.listen((
        Duration position,
      ) {
        if (!_dubPlaybackActive) return;
        final int ms = position.inMilliseconds;
        if (ms < playStart || ms >= playEnd) {
          unawaited(_stopDubPlayback());
          return;
        }
        final Duration expected = Duration(milliseconds: ms - playStart);
        if ((audio.state.position - expected).inMilliseconds.abs() > 180) {
          unawaited(audio.seek(expected));
        }
        if (audio.state.rate != state.playbackRate) {
          unawaited(audio.setRate(state.playbackRate));
        }
      });
      await audio.play();
      await player.play();
      if (mounted) setState(() => state.isPlaying = true);
      _showMessage('正在播放环境音＋我的配音');
    } catch (error) {
      await _stopDubPlayback();
      _showMessage('配音合成失败，请检查分离服务或设备混音支持。');
    }
  }

  Future<void> _handleDubExportShare({required bool fullEpisode}) async {
    final String? videoPath = _localPlayableVideoPath();
    if (videoPath == null) {
      _showMessage('需要本地视频才能导出配音。');
      return;
    }
    final List<DubTake> takes =
        await DubSessionStore.instance.loadTakes(widget.episodeId);
    if (takes.isEmpty) {
      _showMessage('还没有配音录音可分享。');
      return;
    }

    _showMessage('正在准备配音视频…');
    String? accompaniment;
    try {
      accompaniment = await _dubAccompanimentService.ensureAccompaniment(
        episodeId: widget.episodeId,
        videoSource: videoPath,
      );
    } catch (_) {}

    final int? rangeStart = fullEpisode ? null : state.activeLine.startMs;
    final int? rangeEnd = fullEpisode ? null : state.activeLine.endMs;
    try {
      final DubExportResult exported = await _dubExportService.export(
        episodeId: widget.episodeId,
        videoSource: videoPath,
        takes: takes,
        rangeStartMs: rangeStart,
        rangeEndMs: rangeEnd,
        accompanimentPath: accompaniment,
      );
      final WechatShareOutcome share = await WechatShareHelper.shareVideoFile(
        filePath: exported.outputPath,
        title: fullEpisode ? '整段配音练习' : '本句配音练习',
      );
      if (!mounted) {
        return;
      }
      if (!share.success) {
        _showMessage(share.errorMessage ?? '分享失败');
        return;
      }
      if (!share.countsForMomentsPoints) {
        _showMessage(
          share.errorMessage ??
              '已分享（系统分享不计朋友圈积分）'
              '${exported.duckedDialogue ? ' · 对白窗已压低原声' : ''}',
        );
        return;
      }
      final AuthSessionState auth = ref.read(authSessionProvider);
      if (!auth.isLoggedIn) {
        _showMessage('朋友圈分享成功。登录后可领取积分。');
        return;
      }
      try {
        final String clientShareId =
            'dub-${widget.episodeId}-${fullEpisode ? 'full' : '${rangeStart}_$rangeEnd'}-${DateTime.now().millisecondsSinceEpoch ~/ 60000}';
        final AcquireShareRewardResult reward =
            await ref.read(acquireApiClientProvider).claimShareReward(
                  episodeId: widget.episodeId,
                  clientShareId: clientShareId,
                );
        if (!mounted) {
          return;
        }
        if (reward.awarded) {
          playSuccessSfx(SuccessSfxKind.reward);
          _showMessage('分享成功 · +${reward.delta} 积分（余额 ${reward.balance}）');
        } else if (reward.reason == 'daily_cap') {
          _showMessage('分享成功 · 今日积分已达上限（余额 ${reward.balance}）');
        } else if (reward.reason == 'already_awarded') {
          _showMessage('分享成功 · 该分享已领过积分（余额 ${reward.balance}）');
        } else {
          playSuccessSfx(SuccessSfxKind.nudge);
          _showMessage('分享成功 · 积分 ${reward.balance}');
        }
      } catch (_) {
        if (mounted) {
          _showMessage('分享成功，但积分领取失败，请稍后在设置页查看。');
        }
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          error
              .toString()
              .replaceFirst(RegExp(r'^Bad state:\s*'), '')
              .replaceFirst(RegExp(r'^Exception:\s*'), ''),
        );
      }
    }
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
    // Never paint media_kit softsubs on the video surface — hardsubs are
    // already in the frame, and learners read the list under the player.
        return Video(
          controller: controller,
          controls: null,
      subtitleViewConfiguration: kHiddenSubtitleViewConfiguration,
          pauseUponEnteringBackgroundMode: false,
          filterQuality: FilterQuality.medium,
    );
  }
}

double? _progressFromProofreadLabel(String label) {
  final Match? pct = RegExp(r'（(\d{1,3})%）').firstMatch(label);
  if (pct != null) {
    final int? value = int.tryParse(pct.group(1)!);
    if (value != null) {
      return (value / 100).clamp(0.0, 1.0);
    }
  }
  final Match? parts = RegExp(r'(\d+)\s*/\s*(\d+)\s*段').firstMatch(label);
  if (parts != null) {
    final int? done = int.tryParse(parts.group(1)!);
    final int? total = int.tryParse(parts.group(2)!);
    if (done != null && total != null && total > 0) {
      return (done / total).clamp(0.0, 1.0);
    }
  }
  return null;
}

const PlayerSubtitleLine _emptySubtitleLine = PlayerSubtitleLine(
  startTime: '00:00',
  english: '',
  chinese: '',
  startMs: 0,
  endMs: 0,
);
