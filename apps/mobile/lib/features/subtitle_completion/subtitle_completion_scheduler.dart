import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../library/presentation/library_catalog_provider.dart';
import '../library/presentation/library_mock_data.dart';
import '../player/presentation/asr_subtitle_job.dart';
import '../settings/presentation/settings_provider.dart';
import 'reset_episode_subtitles.dart';
import 'subtitle_completion_background.dart';
import 'subtitle_completion_enqueue.dart';
import 'subtitle_completion_queue.dart';
import 'subtitle_completion_runtime.dart';
import 'subtitle_completion_worker.dart';
import 'subtitle_fill_label.dart';

/// Drains the subtitle completion queue one episode at a time.
///
/// Android: [SubtitleCompletionRuntime] keeps a foreground service + overlay
/// ball alive so work continues across background / lock screen.
class SubtitleCompletionScheduler with WidgetsBindingObserver {
  SubtitleCompletionScheduler._();

  static final SubtitleCompletionScheduler instance =
      SubtitleCompletionScheduler._();

  final SubtitleCompletionQueue queue = SubtitleCompletionQueue.shared;
  SubtitleCompletionWorker? _worker;
  LearningSettingsState Function()? _settingsReader;
  List<LibraryCourseData> Function()? _catalogReader;
  LibraryCatalogNotifier Function()? _catalogNotifier;
  SubtitleCompletionPersistedHook? _onPersisted;
  SubtitleCompletionProgress? _onProgress;
  void Function()? _onQueueChanged;
  bool _attached = false;
  bool _busy = false;
  bool _playerActive = false;
  bool _scanning = false;
  AsrSubtitleCancellationToken? _token;
  Timer? _debounce;
  Timer? _heartbeat;

  void attach({
    required LearningSettingsState Function() settingsReader,
    List<LibraryCourseData> Function()? catalogReader,
    LibraryCatalogNotifier Function()? catalogNotifier,
    SubtitleCompletionPersistedHook? onPersisted,
    SubtitleCompletionProgress? onProgress,
    void Function()? onQueueChanged,
    SubtitleCompletionWorker? worker,
  }) {
    _settingsReader = settingsReader;
    _catalogReader = catalogReader;
    _catalogNotifier = catalogNotifier;
    _onPersisted = onPersisted;
    _onProgress = onProgress;
    _onQueueChanged = onQueueChanged;
    _worker =
        worker ??
        SubtitleCompletionWorker(queue: queue, onPersisted: onPersisted);
    if (!_attached) {
      WidgetsBinding.instance.addObserver(this);
      _attached = true;
    }
    _startHeartbeat();
    unawaited(_bootstrap());
  }

  void detach() {
    if (_attached) {
      WidgetsBinding.instance.removeObserver(this);
      _attached = false;
    }
    _debounce?.cancel();
    _heartbeat?.cancel();
    _token?.cancel();
  }

  /// Playback no longer cancels import-time subtitle ASR.
  ///
  /// Missing EN/ZH must be filled when the video is imported (queue + Whisper),
  /// not deferred until the player opens. Cancelling here left imports half
  /// done whenever the user started watching immediately.
  void setPlayerActive(bool active) {
    if (_playerActive == active) {
      return;
    }
    _playerActive = active;
    // Keep draining either way; kick when leaving the player as a safety net.
    kick(delay: active ? const Duration(milliseconds: 800) : Duration.zero);
  }

  void kick({Duration delay = const Duration(milliseconds: 400)}) {
    _debounce?.cancel();
    _debounce = Timer(delay, () {
      unawaited(_tick());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startHeartbeat();
      unawaited(_bootstrap());
    } else if (state == AppLifecycleState.inactive) {
      // Android 12+: start FGS *before* paused, while start is still allowed.
      unawaited(_promoteToBackgroundRuntime());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Do not cancel in-flight Whisper. Keep draining via FGS kicks.
      unawaited(_promoteToBackgroundRuntime());
    } else if (state == AppLifecycleState.detached) {
      _heartbeat?.cancel();
      _token?.cancel();
      unawaited(SubtitleCompletionRuntime.instance.stop());
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    // Keep draining while the app stays open (e.g. user browses elsewhere).
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_busy) {
        kick(delay: Duration.zero);
      }
    });
  }

  Future<void> _promoteToBackgroundRuntime() async {
    try {
      if (!await queue.hasPendingWork()) {
        return;
      }
      await SubtitleCompletionRuntime.instance.ensureRunning();
      // Heartbeat alone is paused by OS; FGS repeat + this kick keep draining.
      _startHeartbeat();
      kick(delay: Duration.zero);
    } catch (_) {}
  }

  Future<void> _bootstrap() async {
    await queue.recoverInterrupted();
    // Reopen failed jobs (including EN→ZH translation timeouts) so episode 2+
    // Chinese fill can drain again after a fix / network recovery.
    try {
      await queue.requeueFailedJobs(onlyConfigErrors: false);
    } catch (_) {}
    await _consumeBackgroundNudge();
    await _maybeReimportSubtitlesFromFlag();
    // Re-attach on-disk ASR before enqueue scan so "already generated"
    // subtitles show as linked and are not treated as missing.
    try {
      await _catalogNotifier?.call().relinkAllEpisodeSubtitleFiles();
    } catch (_) {}
    await _scanCatalogIfNeeded();
    kick(delay: Duration.zero);
  }

  /// One-shot: `files/reimport_subtitles.flag` → reimport every course.
  Future<void> _maybeReimportSubtitlesFromFlag() async {
    final LibraryCatalogNotifier Function()? notifierReader = _catalogNotifier;
    final List<LibraryCourseData> Function()? catalogReader = _catalogReader;
    final LearningSettingsState Function()? settingsReader = _settingsReader;
    if (notifierReader == null || catalogReader == null) {
      return;
    }
    try {
      final Directory root = await getApplicationSupportDirectory();
      final File flag = File(
        '${root.path}${Platform.pathSeparator}$kReimportSubtitlesFlagName',
      );
      if (!flag.existsSync()) {
        return;
      }
      try {
        await flag.delete();
      } catch (_) {}
      final LibraryCatalogNotifier catalog = notifierReader();
      final String? cookie = settingsReader
          ?.call()
          .resolvedBilibiliCookieHeader;
      for (final LibraryCourseData course in catalogReader()) {
        if (course.episodes.isEmpty) {
          continue;
        }
        await reimportCourseSubtitles(
          catalog: catalog,
          course: course,
          bilibiliCookieHeader: cookie,
        );
      }
    } catch (_) {}
  }

  Future<void> _consumeBackgroundNudge() async {
    try {
      if (!Hive.isBoxOpen('prefs')) {
        return;
      }
      final Box<String> box = Hive.box<String>('prefs');
      if (box.containsKey(kSubtitleCompletionNudgeKey)) {
        await box.delete(kSubtitleCompletionNudgeKey);
      }
    } catch (_) {}
  }

  Future<void> _scanCatalogIfNeeded() async {
    final List<LibraryCourseData> Function()? reader = _catalogReader;
    if (reader == null || _scanning) {
      return;
    }
    _scanning = true;
    try {
      final String? cookie = _settingsReader
          ?.call()
          .resolvedBilibiliCookieHeader;
      await enqueuePendingSubtitleCompletionsForCatalog(
        courses: reader(),
        bilibiliCookieHeader: cookie,
      );
    } catch (_) {
    } finally {
      _scanning = false;
    }
  }

  Future<void> _tick() async {
    if (_busy || _settingsReader == null) {
      return;
    }
    if (!await queue.hasPendingWork()) {
      await SubtitleCompletionRuntime.instance.stop();
      return;
    }
    // Start FGS + floating ball before work so background/lock cannot freeze us.
    final bool runtimeOk =
        await SubtitleCompletionRuntime.instance.ensureRunning();
    final AppLifecycleState? life = WidgetsBinding.instance.lifecycleState;
    final bool foregroundish =
        life == null ||
        life == AppLifecycleState.resumed ||
        life == AppLifecycleState.inactive;
    // Background drain requires a live FGS. If start failed (often: started
    // too late after pause), skip this tick — resume will retry.
    if (!foregroundish &&
        !runtimeOk &&
        !SubtitleCompletionRuntime.instance.isActive) {
      return;
    }
    _busy = true;
    final AsrSubtitleCancellationToken token = AsrSubtitleCancellationToken();
    _token = token;
    try {
      final bool ran =
          await (_worker ??
                  SubtitleCompletionWorker(
                    queue: queue,
                    onPersisted: _onPersisted,
                  ))
              .processNext(
                settings: _settingsReader!(),
                cancellationToken: token,
                onProgress: (String episodeId, String label) {
                  _onProgress?.call(episodeId, label);
                  _onQueueChanged?.call();
                  unawaited(_publishRuntimeProgress(label));
                },
              );
      _onQueueChanged?.call();
      if (ran && !token.isCancelled) {
        // Chain the next pending import job (works in background via FGS).
        kick(delay: const Duration(milliseconds: 200));
      } else if (!await queue.hasPendingWork()) {
        await SubtitleCompletionRuntime.instance.stop();
      }
    } finally {
      if (identical(_token, token)) {
        _token = null;
      }
      _busy = false;
    }
  }

  Future<void> _publishRuntimeProgress(String label) async {
    try {
      final List<SubtitleCompletionJob> jobs = await queue.loadJobs();
      final int done = jobs
          .where(
            (SubtitleCompletionJob j) =>
                j.status == SubtitleCompletionStatus.done,
          )
          .length;
      final int total = jobs.isEmpty ? 1 : jobs.length;
      final double currentFrac = _progressFromLabel(label);
      final int currentPercent = (currentFrac * 100).round().clamp(0, 99);
      final String compact = formatSubtitleFillCompactLabel(
        doneCount: done,
        totalCount: total,
        currentPercent: currentPercent,
      );
      await SubtitleCompletionRuntime.instance.updateProgress(
        label: compact,
        progress: subtitleFillOverallProgress(
          doneCount: done,
          totalCount: total,
          currentFraction: currentFrac,
        ),
      );
    } catch (_) {}
  }

  double _progressFromLabel(String label) {
    return progressFractionFromSubtitleLabel(label);
  }
}
