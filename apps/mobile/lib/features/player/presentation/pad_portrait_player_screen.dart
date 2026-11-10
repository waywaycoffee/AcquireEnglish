import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../config/theme/theme_logic.dart';
import '../../../router/app_router.dart';
import '../../home/presentation/learning_dashboard_provider.dart';
import '../../import_course/data/bilibili_episode_prepare.dart';
import '../../import_course/data/bilibili_import_service.dart';
import '../../import_course/data/bilibili_multipage.dart';
import '../../import_course/domain/bilibili_import.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../phrases/presentation/phrase_book_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_lookup_service.dart';
import '../../shared/data/word_pronunciation_service.dart';
import '../../shared/presentation/app_loading_overlay.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/data/progress_sync_service.dart';
import '../../words/data/offline_word_dictionary.dart';
import '../../words/presentation/word_book_provider.dart';
import '../data/dictation_queue_provider.dart';
import '../domain/episode_word_cards.dart';
import '../domain/pronunciation_assessment.dart';
import 'asr_subtitle_cache.dart';
import 'asr_subtitle_job.dart';
import 'asr_subtitle_service.dart';
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
import 'subtitle_reference_review.dart';
import 'subtitle_word_alignment.dart';
import 'transcript_reader_session.dart';
import 'widgets/ai_grammar_analysis_sheet.dart';
import 'widgets/ai_subtitle_generation_progress_dialog.dart';
import 'widgets/player_subtitle_list.dart';
import 'widgets/player_transcript_panel.dart';
import 'widgets/player_video_panel.dart';
import 'widgets/subtitle_vocabulary_highlight.dart';
import 'widgets/pronunciation_assessment_dialog.dart';
import 'widgets/study_bottom_controls.dart';
import 'widgets/study_dictation_tab.dart';
import 'widgets/study_loop_sheet.dart';
import 'widgets/study_mode_tabs.dart';
import 'widgets/study_practice_tab.dart';
import 'widgets/study_oral_coach_tab.dart';
import 'widgets/study_shadowing_tab.dart';
import 'widgets/study_shell_tokens.dart';
import 'widgets/study_top_bar.dart';
import 'widgets/study_word_cards_tab.dart';

class PadPortraitPlayerScreen extends ConsumerStatefulWidget {
  const PadPortraitPlayerScreen({
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
  ConsumerState<PadPortraitPlayerScreen> createState() =>
      _PadPortraitPlayerScreenState();
}

class _PadPortraitPlayerScreenState
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
  bool _videoReady = false;
  bool _videoLoading = false;
  bool _isBootstrapping = true;
  bool _videoIsPlaying = false;
  Duration _videoDuration = Duration.zero;
  Duration _videoPosition = Duration.zero;
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
  BilingualSubtitlePipeline? _bilingualPipeline;
  BilingualPipelinePhase _bilingualPhase = BilingualPipelinePhase.idle;
  String? _bilingualPipelineLabel;
  bool _bilingualShowAiComplete = false;
  List<SubtitleTrack> _embeddedSubtitleTracks = const <SubtitleTrack>[];
  String? _selectedEmbeddedSubtitleId;
  List<PlayerSubtitleLine> _referenceSubtitleLines =
      const <PlayerSubtitleLine>[];
  StudyModeTab _studyTab = StudyModeTab.subtitles;
  bool _dictationQueueMode = false;
  int _dictationQueueIndex = 0;
  bool _pausedForLookup = false;
  bool _episodeFavorited = false;
  bool _blindListening = false;
  StudyLoopSettings _loopSettings = const StudyLoopSettings();
  int _loopCompleted = 0;
  bool _loopIntervalPending = false;

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
    _aiSubtitleCancellationToken?.cancel();
    unawaited(_bilingualPipeline?.dispose());
    _bilingualPipeline = null;
    PlayerSystemMediaControls.unbind();
    unawaited(_disposeVideo().whenComplete(_releaseGraphicsCache));
    _transcriptReaderSession.dispose();
    super.dispose();
  }

  Future<void> _loadEpisodeResources() async {
    final List<LibraryCourseData> courses = ref.read(libraryCatalogProvider);
    PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: courses,
      episodeId: widget.episodeId,
    );
    String? initialStartTime =
        widget.initialStartTime ??
        ((resource.episode?.completed ?? false)
            ? null
            : resource.episode?.progressTimeStr);
    _videoAsset = resource.videoAsset;

    // Cloud progress last-write-wins: prefer remote position when newer/farther.
    try {
      final Map<String, AcquireProgressDto> remote = await ref
          .read(progressSyncServiceProvider)
          .pullIndexed();
      final AcquireProgressDto? row = remote[widget.episodeId];
      if (row != null && row.positionSec > 1) {
        final String cloudTime = StudyBottomControls.formatClock(
          Duration(milliseconds: (row.positionSec * 1000).round()),
        );
        final int localMs =
            PlayerMockState.parseTimestampToMsPublic(initialStartTime) ?? 0;
        final int cloudMs = (row.positionSec * 1000).round();
        if (cloudMs > localMs + 1500) {
          initialStartTime = cloudTime;
        }
      }
    } catch (_) {}

    // Bilibili: pull official subs + force local MP4 before the player opens.
    String? enSub = resource.englishSubtitleAsset;
    String? zhSub = resource.chineseSubtitleAsset;
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
              SnackBar(content: Text(note), duration: const Duration(seconds: 4)),
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

    List<PlayerSubtitleLine> resolvedLines = const <PlayerSubtitleLine>[];
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
      } catch (e) {
        // ignore: avoid_print
        print('bilibili.prepare load en/zh subs error: $e');
        resolvedLines = const <PlayerSubtitleLine>[];
      }
    } else if (isUsableSubtitlePath(zhSub)) {
      // Chinese-only official track: still show something until Whisper/AI runs.
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
    if (!mounted) {
      return;
    }

    setState(() {
      state
        ..loadLines(resolvedLines, initialStartTime: initialStartTime)
        ..isPlaying = widget.autoPlay && (_videoAsset?.isNotEmpty ?? false);
      _usingAiSubtitles = false;
      _referenceSubtitleLines = resolvedLines;
      _isBootstrapping = false;
    });
    if (resource.episode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
        ref.read(lastLearningEpisodeProvider.notifier).record(widget.episodeId);
      });
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
    final bool hasSubs =
        isUsableSubtitlePath(resource.englishSubtitleAsset) ||
        isUsableSubtitlePath(resource.chineseSubtitleAsset);
    return !hasLocalVideo || !hasSubs;
  }

  Future<void> _persistBilibiliEpisodeAssets({
    required PlayerCourseLookupResult resource,
    String? localVideoPath,
    String? enSubtitlePath,
    String? zhSubtitlePath,
  }) async {
    final LibraryCourseData? course = resource.course;
    final LibraryEpisodeItem? episode = resource.episode;
    if (course == null || episode == null) {
      return;
    }
    final bool hasEn = isUsableSubtitlePath(enSubtitlePath);
    final bool hasZh = isUsableSubtitlePath(zhSubtitlePath);
    final bool hasVideo = isUsableLocalVideoPath(localVideoPath);
    if (!hasEn && !hasZh && !hasVideo) {
      return;
    }
    final LibraryEpisodeItem current = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: episode.id,
    ).episode ??
        episode;
    await ref.read(libraryCatalogProvider.notifier).importCourse(
      course.copyWith(
        episodes: course.episodes
            .map(
              (LibraryEpisodeItem item) => item.id == episode.id
                  ? item.copyWith(
                      videoAsset: hasVideo
                          ? localVideoPath
                          : item.videoAsset,
                      videoMissing: hasVideo ? false : item.videoMissing,
                      enSubtitleAsset: hasEn
                          ? enSubtitlePath
                          : item.enSubtitleAsset,
                      cnSubtitleAsset: hasZh
                          ? zhSubtitlePath
                          : item.cnSubtitleAsset,
                      hasEnglishSubtitles: hasEn || item.hasEnglishSubtitles,
                      hasChineseSubtitles: hasZh || item.hasChineseSubtitles,
                      subtitleTracks: <LibrarySubtitleTrackItem>[
                        if (hasEn ||
                            isUsableSubtitlePath(current.enSubtitleAsset))
                          LibrarySubtitleTrackItem(
                            languageCode: 'en',
                            languageLabel: 'English',
                            path: hasEn
                                ? enSubtitlePath!
                                : current.enSubtitleAsset!,
                          ),
                        if (hasZh ||
                            isUsableSubtitlePath(current.cnSubtitleAsset))
                          LibrarySubtitleTrackItem(
                            languageCode: 'zh',
                            languageLabel: '中文',
                            path: hasZh
                                ? zhSubtitlePath!
                                : current.cnSubtitleAsset!,
                          ),
                      ],
                    )
                  : item,
            )
            .toList(growable: false),
      ),
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
          await ref.read(libraryCatalogProvider.notifier).importCourse(expanded);
          course = expanded;
          resource = resolvePlayerCourseForEpisode(
            courses: ref.read(libraryCatalogProvider),
            episodeId: widget.episodeId,
          );
          // If the old single-episode id vanished, keep preparing against page 1.
          if (resource.course == null) {
            resource = resolvePlayerCourseForEpisode(
              courses: ref.read(libraryCatalogProvider),
              episodeId: expanded.episodes.first.id,
            );
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print('bilibili.prepare expand pages error: $e');
      }
    }
    final String? source = bilibiliSourceForEpisode(
          course: resource.course ?? course,
          episode: resource.episode,
          videoAsset: resource.videoAsset,
        ) ??
        _bilibiliRecoverSource(resource.videoAsset ?? '') ??
        _bilibiliRecoverSource(resource.course?.description ?? '');
    if (source == null || source.isEmpty) {
      return const BilibiliEpisodePrepareResult(
        note: '无法识别 B 站视频来源',
      );
    }
    final BilibiliEpisodePrepareResult prepared = await prepareBilibiliEpisode(
      service: service,
      source: source,
      currentVideoAsset: resource.videoAsset,
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
            );
          },
    );
    await _persistBilibiliEpisodeAssets(
      resource: resource,
      localVideoPath: prepared.localVideoPath,
      enSubtitlePath: prepared.enSubtitlePath,
      zhSubtitlePath: prepared.zhSubtitlePath,
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

    final Player player = Player();
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
            onTimeout: () => throw StateError(
              isBilibili
                  ? '缓存 B 站视频超时，请检查网络后重试'
                  : '视频加载超时',
            ),
          );
      if (!mounted || !identical(_videoPlayer, player)) return;
      setState(() {
        _videoErrorText = isBilibili ? '正在连接播放器…' : null;
      });
      await waitForVideoInitialization(
        () async {
          await player.open(
            Media(
              createPlayerMediaUri(media.uri),
              httpHeaders: media.headers ?? const <String, String>{},
            ),
          );
        },
        timeout: Duration(seconds: isBilibili ? 30 : 8),
      );
      if (!mounted || !identical(_videoPlayer, player)) return;
      await waitForPlayerReady(
        player,
        timeout: Duration(seconds: isBilibili ? 30 : 8),
      );
      if (!mounted || !identical(_videoPlayer, player)) return;
      await player.setSubtitleTrack(SubtitleTrack.no());
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
      } else if (!state.hasLines) {
        await _loadCachedAiSubtitles();
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

    final String? biliSource = _bilibiliRecoverSource(trimmed);
    if (biliSource == null) {
      if (looksLocal) {
        throw StateError('本地视频文件不存在，且无法从课程信息恢复 B 站链接');
      }
      return (uri: trimmed, headers: null);
    }

    try {
      final BilibiliPlayableMedia media =
          await BilibiliImportService.withCookie(
            ref.read(learningSettingsProvider).resolvedBilibiliCookieHeader,
          ).resolvePlayableForPlayback(biliSource, onProgress: onProgress);
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
    if (courseId == null || courseId.isEmpty) {
      return;
    }
    final String? current = resource.episode?.videoAsset?.trim();
    if (current == localPath) {
      return;
    }
    await ref.read(libraryCatalogProvider.notifier).updateCourseVideoAsset(
          courseId: courseId,
          videoAsset: localPath,
        );
  }

  Future<String> _resolveAsrVideoPath(String source) async {
    // Import now downloads first — prefer an existing local file.
    if (!source.startsWith('http://') &&
        !source.startsWith('https://') &&
        File(source).existsSync() &&
        File(source).lengthSync() > 64 * 1024) {
      return source;
    }
    final bool needsBilibiliCache =
        BilibiliImport.isWatchPageUrl(source) ||
        BilibiliImport.looksLikeBilibiliInput(source) ||
        source.startsWith('http://127.0.0.1');
    if (!needsBilibiliCache) {
      return source;
    }
    // Proxy streams are not real files — ASR needs a downloaded MP4.
    final String input = source.startsWith('http://127.0.0.1')
        ? (_videoAsset ?? source)
        : source;
    if (!BilibiliImport.isWatchPageUrl(input) &&
        !BilibiliImport.looksLikeBilibiliInput(input)) {
      throw StateError('当前是在线流，请先等待视频缓存完成后再生成字幕');
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
    final int positionMs = state.positionMs;
    setState(() {
      state
        ..loadLines(lines, wordDefinitions: parseSubtitleGlossary(cached))
        ..seekToMilliseconds(positionMs)
        ..setSubtitleMode(settings.subtitleMode);
      _usingAiSubtitles = true;
    });
  }

  Future<void> _maybeStartBilingualPipeline() async {
    if (!mounted || _usingAiSubtitles || _generatingAiSubtitles) {
      return;
    }
    final String? videoPath = _videoAsset;
    if (videoPath == null ||
        videoPath.isEmpty ||
        !_videoReady ||
        !state.hasLines) {
      return;
    }
    if (!BilingualSubtitlePipeline.shouldAutoStart(state.lines)) {
      return;
    }
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
        setState(() {
          state.loadLines(lines);
        });
      },
      onPhaseChanged: (BilingualPipelinePhase phase) {
        if (!mounted) {
          return;
        }
        setState(() {
          _bilingualPhase = phase;
          _bilingualShowAiComplete =
              phase == BilingualPipelinePhase.ocrSlow;
          if (phase == BilingualPipelinePhase.completed) {
            _usingAiSubtitles = true;
            _bilingualPipelineLabel = null;
            _bilingualShowAiComplete = false;
          } else if (phase == BilingualPipelinePhase.cancelled) {
            _bilingualPipelineLabel = null;
            _bilingualShowAiComplete = false;
          }
        });
      },
      onProgress: (String label) {
        if (!mounted) {
          return;
        }
        setState(() => _bilingualPipelineLabel = label);
      },
    );
    _bilingualPipeline = pipeline;
    setState(() {
      _bilingualPhase = BilingualPipelinePhase.ocrRunning;
      _bilingualPipelineLabel = '正在识别画面字幕…';
      _bilingualShowAiComplete = false;
    });
    await pipeline.startOcr(
      isPlaying: () => state.isPlaying || _videoIsPlaying,
      positionMs: () =>
          _videoPosition.inMilliseconds > 0
          ? _videoPosition.inMilliseconds
          : state.positionMs,
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
      setState(() {
        _usingAiSubtitles = true;
        _bilingualPipelineLabel = null;
        _bilingualShowAiComplete = false;
      });
      _showMessage('双语字幕已补全');
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
      if (listEquals(_embeddedSubtitleTracks, subtitles)) return;
      setState(() {
        _embeddedSubtitleTracks = subtitles;
        if (!subtitles.any(
          (SubtitleTrack track) => track.id == _selectedEmbeddedSubtitleId,
        )) {
          _selectedEmbeddedSubtitleId = null;
        }
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
    });
    _videoPlayingSubscription = player.stream.playing.listen((bool playing) {
      _videoIsPlaying = playing;
    });
    _videoCompletedSubscription = player.stream.completed.listen((
      bool completed,
    ) {
      if (!completed) {
        return;
      }
      if (_loopSettings.mode == StudyLoopMode.full) {
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

  void _onVideoProgress(Duration position) {
    if (!mounted) {
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
      if (_loopSettings.mode == StudyLoopMode.sentence &&
          (_loopSettings.intervalSec > 0 || _loopSettings.countLimit > 0)) {
        unawaited(_applyLoopRestart());
        return;
      }
      unawaited(_videoPlayer?.seek(_videoPosition));
      return;
    }

    if (wasPlaying &&
        state.shouldPauseAtSentenceEnd(position.inMilliseconds)) {
      final Duration end = Duration(
        milliseconds: state.videoEndMsForLine(state.activeLineIndex),
      );
      setState(() {
        _videoPosition = end;
        state.positionMs = end.inMilliseconds;
        state.isPlaying = false;
      });
      unawaited(_videoPlayer?.pause());
      unawaited(_videoPlayer?.seek(end));
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
    final Brightness platformBrightness =
        MediaQuery.platformBrightnessOf(context);
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
                title: course?.title ?? episode?.title ?? 'AcquireEnglish',
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
                isFavorite: _episodeFavorited,
                onFavorite: () => _handleToggleEpisodeFavorite(courseContext),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(0, compactPlayer ? 2 : 6, 0, 0),
                  child: Column(
                    children: <Widget>[
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: playerHorizontalPadding,
                        ),
                        child: PlayerVideoPanel(
                        episodeId: widget.episodeId,
                        showSceneHeader: false,
                        hideOverlayControls: true,
                        line: activeLine,
                        isPlaying: state.isPlaying,
                        speed: state.speed,
                        subtitleMode: state.subtitleMode,
                        subtitleModes: state.availableSubtitleModes,
                        embeddedSubtitleTracks: _embeddedSubtitleTracks,
                        selectedEmbeddedSubtitleId: _selectedEmbeddedSubtitleId,
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
                        onSelectEmbeddedSubtitle: _handleSelectEmbeddedSubtitle,
                        onToggleShadowing: _handleToggleShadowing,
                        onToggleLoop: _handleToggleLoop,
                        onToggleMuted: _handleToggleMuted,
                        onVolumeChanged: _handleVolumeChanged,
                        onSubtitleLookupOpen: _stopVideo,
                        onAssessVisibleLine: () {
                          setState(() => _studyTab = StudyModeTab.shadowing);
                          if (!state.pauseAtSentenceEnd) {
                            setState(() => state.togglePauseAtSentenceEnd());
                          }
                        },
                        assessmentUnavailableReason:
                            visibleAssessment.unavailableReason,
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
                    SizedBox(height: compactPlayer ? 4 : 8),
                    StudyModeTabs(
                      value: _studyTab,
                      onChanged: (StudyModeTab tab) {
                        setState(() => _studyTab = tab);
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
                          keyVocabularyWords: keyVocabularyWords,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            StudyBottomControls(
              bilingual: state.subtitleMode == '双语',
              blindListening: _blindListening,
              speed: state.speed,
              isPlaying: state.isPlaying,
              isLooping: _loopSettings.isLooping || state.isLooping,
              position: _videoPosition,
              duration: _videoDuration,
              onToggleBlindListening: () {
                setState(() => _blindListening = !_blindListening);
              },
              onToggleBilingual: _handleToggleBilingual,
              onLongPressBlind: _handleCycleSubtitleMode,
              onCycleSpeed: _handleCycleSpeed,
              onSpeedSelected: _handleSpeedSelected,
              onOpenSpeedSheet: _handleOpenSpeedSheet,
              onOpenQualitySheet: _handleOpenQualitySheet,
              onTogglePlaying: _handleTogglePlaying,
              onOpenLoopSheet: _handleOpenLoopSheet,
              onSeek: _handleSeek,
              onToggleFullscreen: () => _handleOpenFullscreen(
                course?.episodes ?? const <LibraryEpisodeItem>[],
              ),
              onOpenWordCards: () {
                setState(() => _studyTab = StudyModeTab.wordCards);
              },
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildStudyTabBody({
    required PlayerCourseLookupResult courseContext,
    required LearningSettingsState settings,
    required bool canGenerateAiSubtitles,
    required PronunciationTargetSelection visibleAssessment,
    required PlayerSubtitleLine activeLine,
    required Set<String> savedVocabularyWords,
    required Set<String> keyVocabularyWords,
  }) {
    switch (_studyTab) {
      case StudyModeTab.subtitles:
        if (state.hasLines) {
          return PlayerTranscriptPanel(
            episodeId: widget.episodeId,
            lines: state.lines,
            activeIndex: state.activeLineIndex,
            subtitleMode: state.subtitleMode,
            currentWordIndex: state.currentWordIndex,
            fontScale: settings.fontScale,
            highlightWords: settings.highlightWords,
            subtitleLetterCase: settings.subtitleLetterCase,
            subtitleWordHighlightStyle: settings.subtitleWordHighlightStyle,
            subtitleWordHighlightBorderWidth:
                settings.subtitleWordHighlightBorderWidth,
            savedVocabularyWords: savedVocabularyWords,
            keyVocabularyWords: keyVocabularyWords,
            onTapLine: _goToLine,
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
            onAssessLine: _handleAssessLine,
            pronunciationUnavailableReasonForLine:
                _pronunciationUnavailableReasonForLine,
            loopingLineIndex: state.isLooping ? state.activeLineIndex : null,
            isPlaying: state.isPlaying,
            onTogglePlaying: _handleTogglePlaying,
            onPronounce: _stopVideo,
            onRegenerateAiSubtitles:
                _usingAiSubtitles && !_generatingAiSubtitles
                ? _handleRegenerateAiSubtitles
                : null,
            onDeleteAiSubtitles: _usingAiSubtitles
                ? _handleDeleteAiSubtitles
                : null,
            onRegenerateAiLine: _usingAiSubtitles
                ? _handleRegenerateAiLine
                : null,
            studyDarkStyle: true,
            blindListening: _blindListening,
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
            showAiCompleteButton: _bilingualShowAiComplete,
            onAiComplete: _bilingualShowAiComplete
                ? _handleAiCompleteSubtitles
                : null,
            onCancelBilingualPipeline:
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
            keyVocabularyWords: keyVocabularyWords,
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
            showAiCompleteButton: _bilingualShowAiComplete,
            onAiComplete: _bilingualShowAiComplete
                ? _handleAiCompleteSubtitles
                : null,
            onCancelBilingualPipeline:
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
        return StudyShadowingTab(
          line: activeLine,
          hasLine: state.hasLines,
          assessmentTarget: visibleAssessment.target,
          pauseAtSentenceEnd: state.pauseAtSentenceEnd,
          onTogglePauseAtSentenceEnd: () {
            setState(() => state.togglePauseAtSentenceEnd());
          },
          onNextSentence: state.hasLines ? _handleNextLine : null,
          onReplaySentence: state.hasLines ? _handleReplayLine : null,
          unavailableReason: visibleAssessment.unavailableReason,
          onOpenFullDialog: visibleAssessment.target == null
              ? null
              : _handleAssessVisibleLine,
        );
      case StudyModeTab.coach:
        return StudyOralCoachTab(
          line: activeLine,
          hasLine: state.hasLines,
          assessmentTarget: visibleAssessment.target,
          unavailableReason: visibleAssessment.unavailableReason,
          onReplaySentence: state.hasLines ? _handleReplayLine : null,
          onNextSentence: state.hasLines ? _handleNextLine : null,
          onOpenAssessment: visibleAssessment.target == null
              ? null
              : _handleAssessVisibleLine,
        );
      case StudyModeTab.dictation:
        final List<DictationQueueItem> queue = ref.watch(dictationQueueProvider);
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
          onAddToQueue: () => _handleAddDictationQueue(
            courseContext,
            difficult: false,
          ),
          onMarkDifficult: () => _handleAddDictationQueue(
            courseContext,
            difficult: true,
          ),
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
        final List<EpisodeWordCard> cards = buildEpisodeWordCards(
          episodeId: widget.episodeId,
          lines: state.lines,
          words: ref.watch(wordBookProvider),
          phrases: ref.watch(phraseBookProvider),
        );
        return StudyWordCardsTab(
          cards: cards,
          onJumpToCard: _handleJumpToWordCard,
          onFavorite: (EpisodeWordCard card) {
            _handleFavoriteWord(card.text);
          },
          onSpeak: (EpisodeWordCard card) {
            unawaited(_speakWordCard(card.text));
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

  Future<void> _speakWordCard(String text) async {
    try {
      await ref.read(wordPronunciationServiceProvider).speak(text);
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

  void _handleToggleBilingual() {
    final String nextMode = state.subtitleMode == '双语' ? '单英' : '双语';
    _handleSetSubtitleMode(nextMode);
  }

  void _handleCycleSubtitleMode() {
    final List<String> modes = state.availableSubtitleModes;
    if (modes.isEmpty) {
      return;
    }
    final int index = modes.indexOf(state.subtitleMode);
    final String next = modes[(index + 1) % modes.length];
    _handleSetSubtitleMode(next);
  }

  void _handleSetSubtitleMode(String mode) {
    setState(() {
      state.setSubtitleMode(mode);
      _selectedEmbeddedSubtitleId = null;
    });
    ref.read(learningSettingsProvider.notifier).setSubtitleMode(mode);
    unawaited(_videoPlayer?.setSubtitleTrack(SubtitleTrack.no()));
    _applyPlaybackMode();
  }

  void _handleSelectEmbeddedSubtitle(SubtitleTrack? track) {
    setState(() {
      _selectedEmbeddedSubtitleId = track?.id;
      if (track != null) {
        state.setSubtitleMode('隐藏');
      }
    });
    if (track != null) {
      ref.read(learningSettingsProvider.notifier).setSubtitleMode('隐藏');
    }
    unawaited(_videoPlayer?.setSubtitleTrack(track ?? SubtitleTrack.no()));
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
      _studyTab = StudyModeTab.shadowing;
    });
    ref.read(learningActivityProvider.notifier).recordShadowingToggle(
      enabled: true,
    );
    _showMessage('已进入跟读模式：句末暂停已开启');
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
    setState(() => _episodeFavorited = true);
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
                      ? Icon(
                          Icons.check_rounded,
                          color: sheetColors.accent,
                        )
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
                  style: TextStyle(
                    color: colors.textSecondary,
                    height: 1.45,
                  ),
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
      _showMessage(added ? '已加入听写队列并标记困难' : '已标记为困难句');
    } else {
      _showMessage(added ? '已加入听写队列' : '该句已在听写队列中');
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
      await Future<void>.delayed(
        Duration(seconds: _loopSettings.intervalSec),
      );
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
  }) async {
    if (_generatingAiSubtitles) {
      return;
    }
    final String? videoPath = _videoAsset;
    if (videoPath == null || videoPath.isEmpty) {
      _showMessage('当前视频不可用');
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
      final bool hasOfficialEnglish =
          usableReferenceSubtitles(referenceLines).isNotEmpty;
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
    final String? source =
        resource.course?.description ??
        resource.episode?.videoAsset ??
        _videoAsset;
    if (source == null ||
        (!BilibiliImport.isWatchPageUrl(source) &&
            !BilibiliImport.looksLikeBilibiliInput(source) &&
            !(resource.course?.id.startsWith('bilibili-') ?? false))) {
      return existing;
    }
    if (mounted) {
      setState(() {
        _aiSubtitleProgressText = '正在拉取 B 站官方字幕…';
        _aiSubtitlePreviewText = '有官方字幕则跳过 Whisper';
      });
    }
    final String query = resource.course?.id.startsWith('bilibili-') ?? false
        ? resource.course!.id.substring('bilibili-'.length)
        : source;
    final Map<String, String?> tracks = await BilibiliImportService.withCookie(
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
        ref.read(libraryCatalogProvider.notifier).importCourse(
          course.copyWith(
            episodes: course.episodes
                .map(
                  (LibraryEpisodeItem item) => item.id == episode.id
                      ? item.copyWith(
                          enSubtitleAsset: hasEn
                              ? enPath
                              : item.enSubtitleAsset,
                          cnSubtitleAsset: hasZh
                              ? zhPath
                              : item.cnSubtitleAsset,
                          hasEnglishSubtitles:
                              hasEn || item.hasEnglishSubtitles,
                          hasChineseSubtitles:
                              hasZh || item.hasChineseSubtitles,
                          subtitleTracks: <LibrarySubtitleTrackItem>[
                            if (hasEn)
                              LibrarySubtitleTrackItem(
                                languageCode: 'en',
                                languageLabel: 'English',
                                path: enPath,
                              ),
                            if (hasZh)
                              LibrarySubtitleTrackItem(
                                languageCode: 'zh',
                                languageLabel: '中文',
                                path: zhPath,
                              ),
                          ],
                        )
                      : item,
                )
                .toList(growable: false),
          ),
        ),
      );
    }
    if (!hasEn) {
      return existing;
    }
    try {
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

  void _handleFavoriteWord(String word) {
    if (!state.hasLines) return;
    final PlayerSubtitleLine line = state.activeLine;
    final PlayerCourseLookupResult courseContext =
        resolvePlayerCourseForEpisode(
          courses: ref.read(libraryCatalogProvider),
          episodeId: widget.episodeId,
        );
    final LibraryEpisodeItem? episode = courseContext.episode;
    final bool added = ref
        .read(wordBookProvider.notifier)
        .addFavoriteWord(
          rawWord: word,
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
              state.generatedWordDefinitions[normalizeWord(word)],
        );
    _showMessage(added ? '已收藏单词 "$word"' : '未能收藏，请选择独立英文单词。');
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
    });
    _seekToActiveLine();
    final PlayerCourseLookupResult courseContext =
        resolvePlayerCourseForEpisode(
          courses: ref.read(libraryCatalogProvider),
          episodeId: widget.episodeId,
        );
    unawaited(
      _handleAddDictationQueue(courseContext, difficult: false),
    );
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
    return Consumer(
      builder: (BuildContext context, WidgetRef ref, _) {
        final double fontScale = ref.watch(
          learningSettingsProvider.select(
            (LearningSettingsState settings) => settings.fontScale,
          ),
        );
        const SubtitleViewConfiguration defaults = SubtitleViewConfiguration();
        return Video(
          controller: controller,
          controls: null,
          subtitleViewConfiguration: SubtitleViewConfiguration(
            style: defaults.style.copyWith(
              fontSize: defaults.style.fontSize! * fontScale,
            ),
          ),
          pauseUponEnteringBackgroundMode: false,
          filterQuality: FilterQuality.medium,
        );
      },
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
