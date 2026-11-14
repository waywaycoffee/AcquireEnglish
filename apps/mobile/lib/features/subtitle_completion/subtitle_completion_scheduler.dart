import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hive_ce/hive.dart';

import '../library/presentation/library_mock_data.dart';
import '../player/presentation/asr_subtitle_job.dart';
import '../settings/presentation/settings_provider.dart';
import 'subtitle_completion_background.dart';
import 'subtitle_completion_enqueue.dart';
import 'subtitle_completion_queue.dart';
import 'subtitle_completion_worker.dart';

/// Foreground runner: while the app is open, drains the subtitle completion
/// queue one episode at a time (keeps draining during playback).
class SubtitleCompletionScheduler with WidgetsBindingObserver {
  SubtitleCompletionScheduler._();

  static final SubtitleCompletionScheduler instance =
      SubtitleCompletionScheduler._();

  final SubtitleCompletionQueue queue = SubtitleCompletionQueue();
  SubtitleCompletionWorker? _worker;
  LearningSettingsState Function()? _settingsReader;
  List<LibraryCourseData> Function()? _catalogReader;
  SubtitleCompletionPersistedHook? _onPersisted;
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
    SubtitleCompletionPersistedHook? onPersisted,
    SubtitleCompletionWorker? worker,
  }) {
    _settingsReader = settingsReader;
    _catalogReader = catalogReader;
    _onPersisted = onPersisted;
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
    } else if (state == AppLifecycleState.paused) {
      // Keep Whisper running across brief locks / app switches. Cancelling here
      // burned maxAttempts and left imports permanently failed overnight.
      _heartbeat?.cancel();
    } else if (state == AppLifecycleState.detached) {
      _heartbeat?.cancel();
      _token?.cancel();
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

  Future<void> _bootstrap() async {
    await queue.recoverInterrupted();
    // Import jobs often failed while Bailian key was missing; reopen them so
    // the worker can drain with local Whisper (or a fixed cloud key).
    try {
      await queue.requeueFailedJobs(onlyConfigErrors: true);
    } catch (_) {}
    await _consumeBackgroundNudge();
    await _scanCatalogIfNeeded();
    kick(delay: Duration.zero);
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
      await enqueuePendingSubtitleCompletionsForCatalog(courses: reader());
    } catch (_) {
    } finally {
      _scanning = false;
    }
  }

  Future<void> _tick() async {
    if (_busy || _settingsReader == null) {
      return;
    }
    final AppLifecycleState? life = WidgetsBinding.instance.lifecycleState;
    if (life != null &&
        life != AppLifecycleState.resumed &&
        life != AppLifecycleState.inactive) {
      return;
    }
    if (!await queue.hasPendingWork()) {
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
              );
      if (ran && !token.isCancelled) {
        // Chain the next pending import job while the app stays open.
        kick(delay: const Duration(milliseconds: 200));
      }
    } finally {
      if (identical(_token, token)) {
        _token = null;
      }
      _busy = false;
    }
  }
}
