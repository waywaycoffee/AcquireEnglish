import 'dart:async';

import 'package:flutter/material.dart';

import 'subtitle_completion_runtime.dart';

/// In-app draggable progress ball (fallback when system overlay is denied).
class SubtitleInAppBallHost extends StatefulWidget {
  const SubtitleInAppBallHost({required this.child, super.key});

  final Widget child;

  @override
  State<SubtitleInAppBallHost> createState() => _SubtitleInAppBallHostState();
}

class _SubtitleInAppBallHostState extends State<SubtitleInAppBallHost> {
  StreamSubscription<SubtitleRuntimeSnapshot>? _sub;
  SubtitleRuntimeSnapshot _snap = const SubtitleRuntimeSnapshot(
    active: false,
    label: '',
    progress: 0,
    overlayVisible: false,
  );
  Offset _offset = const Offset(16, 160);

  @override
  void initState() {
    super.initState();
    _snap = SubtitleCompletionRuntime.instance.currentSnapshot;
    _sub = SubtitleCompletionRuntime.instance.snapshots.listen((
      SubtitleRuntimeSnapshot next,
    ) {
      if (!mounted) {
        return;
      }
      setState(() => _snap = next);
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Always show while jobs run; native system ball may also be up.
    final bool show = _snap.active && _snap.progress < 1.0;
    return Stack(
      children: <Widget>[
        widget.child,
        if (show)
          Positioned(
            right: _offset.dx,
            bottom: _offset.dy,
            child: GestureDetector(
              onPanUpdate: (DragUpdateDetails d) {
                setState(() {
                  _offset = Offset(
                    (_offset.dx - d.delta.dx).clamp(8, 280),
                    (_offset.dy - d.delta.dy).clamp(80, 640),
                  );
                });
              },
              child: _Ball(progress: _snap.progress, label: _snap.label),
            ),
          ),
      ],
    );
  }
}

class _Ball extends StatelessWidget {
  const _Ball({required this.progress, required this.label});

  final double progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final int pct = (progress * 100).round().clamp(0, 100);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF3B7CFF), Color(0xFF1B4FD8)],
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF3B7CFF).withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.85),
            width: 2,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                value: progress.clamp(0.05, 1.0),
                strokeWidth: 3.5,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '$pct%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '字幕',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ],
            ),
            Semantics(label: label, child: const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}
