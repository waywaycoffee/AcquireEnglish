import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../subtitle_completion/native_subtitle_ball.dart';
import '../data/bilibili_collection_download.dart';
import '../data/netdisk_local_download.dart';
import '../data/video_download_progress_ui.dart';

/// Drives the system overlay floating ball from **video download** progress.
///
/// While the app is resumed the in-app FAB owns the UI; when backgrounded,
/// this host shows/updates [NativeSubtitleBall] with download % / count.
class VideoDownloadProgressHost extends ConsumerStatefulWidget {
  const VideoDownloadProgressHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<VideoDownloadProgressHost> createState() =>
      _VideoDownloadProgressHostState();
}

class _VideoDownloadProgressHostState
    extends ConsumerState<VideoDownloadProgressHost>
    with WidgetsBindingObserver {
  bool _foreground = true;
  ActiveVideoDownload? _lastDownload;
  bool _listenersBound = false;
  bool _dialogOpen = false;
  DateTime? _lastPromptAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        unawaited(_syncOverlay());
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _foreground = false;
        unawaited(_syncOverlay());
    }
  }

  void _bindListeners() {
    if (_listenersBound) {
      return;
    }
    _listenersBound = true;
    ref
      ..listen<BilibiliCollectionDownloadProgress?>(
        bilibiliCollectionDownloadProgressProvider,
        (_, __) => unawaited(_onProgressChanged()),
      )
      ..listen<NetdiskDownloadProgress?>(
        netdiskDownloadProgressProvider,
        (_, __) => unawaited(_onProgressChanged()),
      );
  }

  Future<void> _onProgressChanged() async {
    final ActiveVideoDownload? download = resolveActiveVideoDownload(
      bilibili: ref.read(bilibiliCollectionDownloadProgressProvider),
      netdisk: ref.read(netdiskDownloadProgressProvider),
    );
    _lastDownload = download;
    if (download != null && _foreground) {
      unawaited(_maybePromptOverlay());
    }
    await _syncOverlay();
  }

  Future<void> _syncOverlay() async {
    final ActiveVideoDownload? download = _lastDownload;
    if (_foreground || download == null) {
      await NativeSubtitleBall.hide();
      return;
    }
    if (await NativeSubtitleBall.isDismissed()) {
      return;
    }
    if (!await NativeSubtitleBall.canDrawOverlays()) {
      return;
    }
    final double progress = download.progress.clamp(0.05, 0.99);
    await NativeSubtitleBall.show(
      progress: progress,
      label: download.compactLabel,
    );
  }

  Future<void> _maybePromptOverlay() async {
    if (!mounted || _dialogOpen || !_foreground || _lastDownload == null) {
      return;
    }
    final bool granted = await NativeSubtitleBall.canDrawOverlays();
    if (granted) {
      return;
    }
    final DateTime now = DateTime.now();
    if (_lastPromptAt != null &&
        now.difference(_lastPromptAt!) < const Duration(seconds: 30)) {
      return;
    }
    _lastPromptAt = now;
    _dialogOpen = true;
    try {
      if (!mounted) {
        return;
      }
      unawaited(NativeSubtitleBall.openOverlaySettings());
      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
            title: const Text('需要悬浮窗权限'),
            content: const Text(
              '下载视频切到后台时需要「显示在其他应用上层」以显示进度悬浮球。'
              'App 内用右下角按钮看进度，离开 App 后才显示系统悬浮窗。',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
              ),
              FilledButton(
                onPressed: () {
                  unawaited(NativeSubtitleBall.openOverlaySettings());
                },
                child: const Text('打开设置'),
              ),
            ],
          );
        },
      );
    } finally {
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    _bindListeners();
    _lastDownload = resolveActiveVideoDownload(
      bilibili: ref.watch(bilibiliCollectionDownloadProgressProvider),
      netdisk: ref.watch(netdiskDownloadProgressProvider),
    );
    return widget.child;
  }
}
