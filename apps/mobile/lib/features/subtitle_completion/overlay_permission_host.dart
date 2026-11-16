import 'dart:async';

import 'package:flutter/material.dart';

import 'native_subtitle_ball.dart';
import 'subtitle_completion_queue.dart';
import 'subtitle_completion_runtime.dart';

/// Handles overlay permission + shows the **system** ball only in background.
/// While the app is resumed, the in-app FAB owns progress UI (no double ball).
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
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(SubtitleCompletionRuntime.instance.setAppForeground(true));
    _sub = SubtitleCompletionRuntime.instance.snapshots.listen((
      SubtitleRuntimeSnapshot snap,
    ) {
      if (snap.needsOverlayPermission && _foreground) {
        unawaited(_maybePrompt());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_onResumed());
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
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        unawaited(_onResumed());
      case AppLifecycleState.inactive:
        // Don't hide yet — rotation / permission sheets briefly go inactive.
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _foreground = false;
        unawaited(_onBackgrounded());
    }
  }

  Future<void> _onResumed() async {
    await SubtitleCompletionRuntime.instance.setAppForeground(true);
    // Hide repeatedly — OEM WindowManager can keep a stale second pill briefly.
    await NativeSubtitleBall.hide();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await NativeSubtitleBall.hide();
    final bool pending = await SubtitleCompletionQueue.shared.hasPendingWork();
    if (!pending) {
      return;
    }
    final bool granted = await NativeSubtitleBall.canDrawOverlays();
    if (!granted) {
      await _maybePrompt(force: true);
      return;
    }
    SubtitleCompletionRuntime.instance.clearOverlayPermissionNeeded();
    // Keep FGS alive; do not show the system ball while foreground.
    await SubtitleCompletionRuntime.instance.ensureRunning();
    await NativeSubtitleBall.hide();
  }

  Future<void> _onBackgrounded() async {
    await SubtitleCompletionRuntime.instance.setAppForeground(false);
    final bool pending = await SubtitleCompletionQueue.shared.hasPendingWork();
    final SubtitleRuntimeSnapshot snap =
        SubtitleCompletionRuntime.instance.currentSnapshot;
    if (!pending && !snap.active) {
      return;
    }
    final bool granted = await NativeSubtitleBall.canDrawOverlays();
    if (!granted) {
      return;
    }
    // ensureRunning always rewrites label to 已完成N（P%）/T.
    await SubtitleCompletionRuntime.instance.ensureRunning(
      progress: snap.progress <= 0 ? 0.08 : snap.progress,
    );
  }

  Future<void> _maybePrompt({bool force = false}) async {
    if (!mounted || _dialogOpen || !_foreground) {
      return;
    }
    final bool pending = await SubtitleCompletionQueue.shared.hasPendingWork();
    if (!pending) {
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
      unawaited(NativeSubtitleBall.openOverlaySettings());
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) {
          return AlertDialog(
            title: const Text('需要悬浮窗权限'),
            content: const Text(
              '补字幕切到后台/锁屏时需要「显示在其他应用上层」。'
              '请允许本应用；App 内用右下角按钮看进度，离开 App 后才显示系统悬浮窗。',
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
