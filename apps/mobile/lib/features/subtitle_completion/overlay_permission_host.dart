import 'dart:async';

import 'package:flutter/material.dart';

import 'native_subtitle_ball.dart';
import 'subtitle_completion_queue.dart';
import 'subtitle_completion_runtime.dart';

/// When subtitle jobs are pending:
/// 1) auto-open overlay settings if permission missing
/// 2) force-show the native system ball once granted
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
  Timer? _kick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = SubtitleCompletionRuntime.instance.snapshots.listen((
      SubtitleRuntimeSnapshot snap,
    ) {
      if (snap.needsOverlayPermission || snap.active) {
        unawaited(_syncOverlay());
      }
    });
    _kick = Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_syncOverlay());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncOverlay());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _kick?.cancel();
    unawaited(_sub?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncOverlay(forcePrompt: true));
    }
  }

  Future<void> _syncOverlay({bool forcePrompt = false}) async {
    if (!mounted) {
      return;
    }
    final bool pending = await SubtitleCompletionQueue.shared.hasPendingWork();
    final SubtitleRuntimeSnapshot snap =
        SubtitleCompletionRuntime.instance.currentSnapshot;
    if (!pending && !snap.active) {
      return;
    }
    final bool granted = await NativeSubtitleBall.canDrawOverlays();
    if (!granted) {
      await _maybePrompt(force: forcePrompt);
      return;
    }
    SubtitleCompletionRuntime.instance.clearOverlayPermissionNeeded();
    // Keep FGS + native ball in sync while jobs drain.
    await SubtitleCompletionRuntime.instance.ensureRunning(
      label: snap.label.isEmpty ? '正在补全字幕…' : snap.label,
      progress: snap.progress <= 0 ? 0.08 : snap.progress,
    );
    final bool showing = await NativeSubtitleBall.show(
      progress: (snap.progress <= 0 ? 0.08 : snap.progress).clamp(0.05, 0.99),
      label: snap.label.isEmpty ? '补字幕中' : snap.label,
    );
    if (!showing) {
      // Retry once after a tick (WindowManager sometimes needs Activity resume).
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await NativeSubtitleBall.show(
        progress: (snap.progress <= 0 ? 0.08 : snap.progress).clamp(0.05, 0.99),
        label: snap.label.isEmpty ? '补字幕中' : snap.label,
      );
    }
  }

  Future<void> _maybePrompt({bool force = false}) async {
    if (!mounted || _dialogOpen) {
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
              '补字幕在后台/锁屏时需要「显示在其他应用上层」。'
              '系统设置页已打开，请找到本应用并允许。'
              '开启后返回 App，右下角按钮会显示「补字幕」进度，并出现系统悬浮球。',
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
