import 'dart:async';

import 'package:flutter/material.dart';

import 'native_subtitle_ball.dart';
import 'subtitle_completion_queue.dart';
import 'subtitle_completion_runtime.dart';

/// When subtitle jobs are pending and overlay permission is missing, show a
/// dialog and auto-open the system「显示在其他应用上层」page.
class OverlayPermissionHost extends StatefulWidget {
  const OverlayPermissionHost({required this.child, super.key});

  final Widget child;

  @override
  State<OverlayPermissionHost> createState() => _OverlayPermissionHostState();
}

class _OverlayPermissionHostState extends State<OverlayPermissionHost>
    with WidgetsBindingObserver {
  StreamSubscription<SubtitleRuntimeSnapshot>? _sub;
  bool _dialogOpen = false;
  DateTime? _lastPromptAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = SubtitleCompletionRuntime.instance.snapshots.listen((
      SubtitleRuntimeSnapshot snap,
    ) {
      if (snap.needsOverlayPermission || snap.active) {
        unawaited(_maybePrompt());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybePrompt());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_sub?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_onResumed());
    }
  }

  Future<void> _onResumed() async {
    final bool granted = await NativeSubtitleBall.canDrawOverlays();
    if (granted) {
      SubtitleCompletionRuntime.instance.clearOverlayPermissionNeeded();
      final bool pending =
          await SubtitleCompletionQueue.shared.hasPendingWork();
      if (pending) {
        await SubtitleCompletionRuntime.instance.ensureRunning();
      }
      return;
    }
    await _maybePrompt(force: true);
  }

  Future<void> _maybePrompt({bool force = false}) async {
    if (!mounted || _dialogOpen) {
      return;
    }
    final bool pending = await SubtitleCompletionQueue.shared.hasPendingWork();
    final SubtitleRuntimeSnapshot snap =
        SubtitleCompletionRuntime.instance.currentSnapshot;
    if (!pending && !snap.active && !snap.needsOverlayPermission) {
      return;
    }
    final bool granted = await NativeSubtitleBall.canDrawOverlays();
    if (granted) {
      SubtitleCompletionRuntime.instance.clearOverlayPermissionNeeded();
      return;
    }
    final DateTime now = DateTime.now();
    if (!force &&
        _lastPromptAt != null &&
        now.difference(_lastPromptAt!) < const Duration(seconds: 8)) {
      return;
    }
    _lastPromptAt = now;
    _dialogOpen = true;
    try {
      if (!mounted) {
        return;
      }
      // Auto-launch system overlay authorization page.
      unawaited(NativeSubtitleBall.openOverlaySettings());
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) {
          return AlertDialog(
            title: const Text('需要悬浮窗权限'),
            content: const Text(
              '补字幕在后台/锁屏时需要「显示在其他应用上层」。'
              '系统设置页已打开，请找到本应用并允许。'
              '开启后返回 App，进度会显示在悬浮窗与底部「补字幕」按钮上。',
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
                child: const Text('再次打开设置'),
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
  Widget build(BuildContext context) => widget.child;
}
