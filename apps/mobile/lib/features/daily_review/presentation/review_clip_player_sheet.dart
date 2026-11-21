import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';

/// Plays roughly [durationMs] of a local video starting at [startMs].
Future<void> showReviewClipPlayerSheet(
  BuildContext context, {
  required String title,
  required String videoPath,
  required int startMs,
  int durationMs = 2000,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) {
      return _ReviewClipPlayerSheet(
        title: title,
        videoPath: videoPath,
        startMs: startMs,
        durationMs: durationMs,
      );
    },
  );
}

class _ReviewClipPlayerSheet extends StatefulWidget {
  const _ReviewClipPlayerSheet({
    required this.title,
    required this.videoPath,
    required this.startMs,
    required this.durationMs,
  });

  final String title;
  final String videoPath;
  final int startMs;
  final int durationMs;

  @override
  State<_ReviewClipPlayerSheet> createState() => _ReviewClipPlayerSheetState();
}

class _ReviewClipPlayerSheetState extends State<_ReviewClipPlayerSheet> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  StreamSubscription<Duration>? _positionSub;
  String? _error;
  bool _looping = true;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await _player.open(Media(widget.videoPath), play: false);
      final int start = widget.startMs < 0 ? 0 : widget.startMs;
      await _player.seek(Duration(milliseconds: start));
      await _player.play();
      final int end = start + widget.durationMs.clamp(1200, 6000);
      _positionSub = _player.stream.position.listen((Duration pos) {
        if (!_looping) return;
        if (pos.inMilliseconds >= end) {
          unawaited(_replay(start));
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '片段播放失败，请检查本地视频是否仍可用。');
    }
  }

  Future<void> _replay(int startMs) async {
    try {
      await _player.seek(Duration(milliseconds: startMs));
      await _player.play();
    } catch (_) {}
  }

  @override
  void dispose() {
    _looping = false;
    unawaited(_positionSub?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double height = MediaQuery.sizeOf(context).height * 0.48;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '原片约 ${(widget.durationMs / 1000).toStringAsFixed(1)} 秒 · 循环播放',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: ColoredBox(
                    color: Colors.black,
                    child: _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          )
                        : Video(controller: _controller),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
