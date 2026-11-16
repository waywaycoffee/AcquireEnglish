import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// Overlay UI host. Invoked from [overlayMain] in `main.dart`
/// (plugin hard-codes that entry-point name).
void runSubtitleOverlayApp() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _SubtitleOverlayApp());
}

class _SubtitleOverlayApp extends StatelessWidget {
  const _SubtitleOverlayApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SubtitleOverlayBall(),
    );
  }
}

/// Compact progress bubble shown over other apps / home screen.
class SubtitleOverlayBall extends StatefulWidget {
  const SubtitleOverlayBall({super.key});

  @override
  State<SubtitleOverlayBall> createState() => _SubtitleOverlayBallState();
}

class _SubtitleOverlayBallState extends State<SubtitleOverlayBall> {
  StreamSubscription<dynamic>? _sub;
  double _progress = 0.08;
  String _label = '补字幕';
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _sub = FlutterOverlayWindow.overlayListener.listen((dynamic raw) {
      if (raw is! Map) {
        return;
      }
      final Map<dynamic, dynamic> data = raw;
      final Object? p = data['progress'];
      final Object? label = data['label'];
      final Object? busy = data['busy'];
      if (!mounted) {
        return;
      }
      setState(() {
        if (p is num) {
          _progress = p.toDouble().clamp(0.0, 1.0);
        }
        if (label is String && label.trim().isNotEmpty) {
          _label = label.trim();
        }
        if (busy is bool) {
          _busy = busy;
        }
      });
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int pct = (_progress * 100).round().clamp(0, 100);
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () {
          unawaited(
            FlutterOverlayWindow.shareData(<String, dynamic>{
              'cmd': 'open_app',
            }),
          );
        },
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
                color: const Color(0xFF3B7CFF).withValues(alpha: 0.45),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              SizedBox(
                width: 58,
                height: 58,
                child: CircularProgressIndicator(
                  value: _busy ? _progress.clamp(0.05, 1.0) : 1.0,
                  strokeWidth: 4,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _busy ? '$pct%' : '✓',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _busy ? '字幕' : '完成',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ],
              ),
              // Keep analyzer happy if label unused visually; used for a11y.
              Semantics(label: _label, child: const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }
}
