import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../../player/presentation/player_native_subtitles.dart';
import 'ear_grind_foreground.dart';

class EarGrindSession {
  const EarGrindSession({
    required this.title,
    required this.mediaPath,
    this.isVideo = true,
  });

  final String title;
  final String mediaPath;
  final bool isVideo;
}

class EarGrindState {
  const EarGrindState({
    this.session,
    this.playing = false,
    this.loop = true,
    this.speed = 1.0,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.audioOnly = false,
    this.backgroundArmed = false,
    this.error,
  });

  final EarGrindSession? session;
  final bool playing;
  final bool loop;
  final double speed;
  final Duration position;
  final Duration duration;
  final bool audioOnly;
  final bool backgroundArmed;
  final String? error;

  EarGrindState copyWith({
    EarGrindSession? session,
    bool clearSession = false,
    bool? playing,
    bool? loop,
    double? speed,
    Duration? position,
    Duration? duration,
    bool? audioOnly,
    bool? backgroundArmed,
    String? error,
    bool clearError = false,
  }) =>
      EarGrindState(
        session: clearSession ? null : (session ?? this.session),
        playing: playing ?? this.playing,
        loop: loop ?? this.loop,
        speed: speed ?? this.speed,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        audioOnly: audioOnly ?? this.audioOnly,
        backgroundArmed: backgroundArmed ?? this.backgroundArmed,
        error: clearError ? null : (error ?? this.error),
      );
}

class EarGrindController extends Notifier<EarGrindState> {
  Player? _player;
  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];
  bool _fgCallbackBound = false;

  @override
  EarGrindState build() {
    ref.onDispose(() {
      unawaited(_tearDown(stopFg: true));
    });
    return const EarGrindState();
  }

  Player? get player => _player;

  void _ensureFgCallback() {
    if (_fgCallbackBound || kIsWeb) return;
    FlutterForegroundTask.addTaskDataCallback(_onFgData);
    _fgCallbackBound = true;
  }

  void _onFgData(Object data) {
    if (data is! Map) return;
    final String cmd = '${data['cmd'] ?? ''}';
    if (cmd == 'toggle') {
      unawaited(togglePlay());
    } else if (cmd == 'open') {
      // App launch handled by FG handler; no-op here.
    }
  }

  Future<void> open(EarGrindSession session) async {
    await _tearDown(stopFg: false);
    _ensureFgCallback();
    final Player player = createStudyVideoPlayer();
    _player = player;
    _subs.add(
      player.stream.playing.listen((bool v) {
        state = state.copyWith(playing: v);
        unawaited(_syncFg());
      }),
    );
    _subs.add(
      player.stream.position.listen((Duration d) {
        state = state.copyWith(position: d);
      }),
    );
    _subs.add(
      player.stream.duration.listen((Duration d) {
        state = state.copyWith(duration: d);
      }),
    );
    _subs.add(
      player.stream.completed.listen((bool done) async {
        if (!done) return;
        if (state.loop && _player != null) {
          await _player!.seek(Duration.zero);
          await _player!.play();
        }
      }),
    );

    state = state.copyWith(
      session: session,
      audioOnly: !session.isVideo,
      clearError: true,
      backgroundArmed: true,
    );
    try {
      await player.open(Media(session.mediaPath), play: true);
      await player.setRate(state.speed);
      await player.setPlaylistMode(
        state.loop ? PlaylistMode.single : PlaylistMode.none,
      );
      if (!session.isVideo) {
        await setAudioOnly(true);
      }
      await EarGrindForeground.start(
        title: '磨耳朵 · ${session.title}',
        body: '锁屏也可继续听 · 点通知可暂停',
      );
    } catch (e) {
      state = state.copyWith(error: '无法打开媒体：$e');
    }
  }

  Future<void> togglePlay() async {
    final Player? p = _player;
    if (p == null) return;
    if (p.state.playing) {
      await p.pause();
    } else {
      await p.play();
      await _syncFg();
    }
  }

  Future<void> setLoop(bool loop) async {
    state = state.copyWith(loop: loop);
    await _player?.setPlaylistMode(
      loop ? PlaylistMode.single : PlaylistMode.none,
    );
  }

  Future<void> setSpeed(double speed) async {
    state = state.copyWith(speed: speed);
    await _player?.setRate(speed);
  }

  Future<void> seek(Duration d) async {
    await _player?.seek(d);
  }

  /// When screen locks / app backgrounds: keep audio, drop video decode.
  Future<void> setAudioOnly(bool audioOnly) async {
    final Player? p = _player;
    if (p == null) return;
    state = state.copyWith(audioOnly: audioOnly);
    try {
      if (audioOnly) {
        await p.setVideoTrack(VideoTrack.no());
      } else {
        await p.setVideoTrack(VideoTrack.auto());
      }
    } catch (_) {}
    await _syncFg();
  }

  Future<void> onAppLifecycle(AppLifecycleHint hint) async {
    if (!state.backgroundArmed || state.session == null) return;
    if (hint == AppLifecycleHint.background) {
      await setAudioOnly(true);
      await _syncFg();
    } else if (hint == AppLifecycleHint.foreground) {
      // Restore video track only for video sources while on-screen.
      if (state.session?.isVideo == true) {
        await setAudioOnly(false);
      }
    }
  }

  Future<void> _syncFg() async {
    final EarGrindSession? s = state.session;
    if (s == null) return;
    final String body = state.playing
        ? (state.audioOnly ? '仅声音播放中（息屏友好）' : '播放中')
        : '已暂停';
    await EarGrindForeground.update(
      title: '磨耳朵 · ${s.title}',
      body: body,
    );
  }

  Future<void> stopAndClose() async {
    await _tearDown(stopFg: true);
    state = const EarGrindState();
  }

  Future<void> _tearDown({required bool stopFg}) async {
    for (final StreamSubscription<dynamic> s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    try {
      await _player?.stop();
    } catch (_) {}
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    if (stopFg) {
      await EarGrindForeground.stop();
    }
  }
}

enum AppLifecycleHint { background, foreground }

final NotifierProvider<EarGrindController, EarGrindState> earGrindProvider =
    NotifierProvider<EarGrindController, EarGrindState>(EarGrindController.new);

bool looksLikeVideoPath(String path) {
  final String lower = path.toLowerCase();
  return lower.endsWith('.mp4') ||
      lower.endsWith('.mkv') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.avi') ||
      lower.endsWith('.m4v');
}

bool looksLikeAudioPath(String path) {
  final String lower = path.toLowerCase();
  return lower.endsWith('.mp3') ||
      lower.endsWith('.m4a') ||
      lower.endsWith('.aac') ||
      lower.endsWith('.wav') ||
      lower.endsWith('.flac') ||
      lower.endsWith('.ogg') ||
      lower.endsWith('.opus');
}

Future<String?> copyPickedMediaToCache(String path, String name) async {
  try {
    final Directory tmp = await getTemporaryDirectory();
    final Directory base =
        await Directory('${tmp.path}/ear_grind').create(recursive: true);
    final String safe = name.replaceAll(RegExp(r'[^\w\.\-]+'), '_');
    final File dest = File('${base.path}/$safe');
    await File(path).copy(dest.path);
    return dest.path;
  } catch (_) {
    return path;
  }
}
