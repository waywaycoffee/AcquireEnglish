import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../player/presentation/learning_resume_provider.dart';
import '../../subtitle_completion/native_subtitle_ball.dart';
import '../../subtitle_completion/subtitle_completion_runtime.dart';
import '../../subtitle_completion/subtitle_completion_status_provider.dart';
import 'pad/app_design_tokens.dart';

/// Global FAB: while补字幕 jobs run, shows blue progress; otherwise「继续播放」.
class ContinueLearningButton extends ConsumerStatefulWidget {
  const ContinueLearningButton({super.key});

  @override
  ConsumerState<ContinueLearningButton> createState() =>
      _ContinueLearningButtonState();
}

class _ContinueLearningButtonState
    extends ConsumerState<ContinueLearningButton> {
  bool _isOpening = false;
  bool _overlayDismissed = false;
  SubtitleRuntimeSnapshot _runtime =
      SubtitleCompletionRuntime.instance.currentSnapshot;
  StreamSubscription<SubtitleRuntimeSnapshot>? _runtimeSub;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshOverlayDismissed());
    _runtimeSub = SubtitleCompletionRuntime.instance.snapshots.listen((
      SubtitleRuntimeSnapshot snap,
    ) {
      if (!mounted) {
        return;
      }
      setState(() => _runtime = snap);
      unawaited(_refreshOverlayDismissed());
    });
  }

  Future<void> _refreshOverlayDismissed() async {
    final bool dismissed = await NativeSubtitleBall.isDismissed();
    if (mounted && dismissed != _overlayDismissed) {
      setState(() => _overlayDismissed = dismissed);
    }
  }

  Future<void> _toggleOverlayBall() async {
    final bool next = !_overlayDismissed;
    await NativeSubtitleBall.setDismissed(next);
    if (!mounted) {
      return;
    }
    setState(() => _overlayDismissed = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next
              ? '已隐藏后台悬浮球（补字幕仍继续）'
              : '已恢复后台悬浮球（离开 App 后显示）',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_runtimeSub?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SubtitleCompletionStatusState fill = ref.watch(
      subtitleCompletionStatusProvider,
    );
    final SubtitleFillProgressSummary? summary = fill.activeFillProgress;
    final bool runtimeBusy =
        _runtime.active ||
        _runtime.needsOverlayPermission ||
        _runtime.overlayVisible;
    if (summary != null || runtimeBusy) {
      final String compact = summary?.compactLabel ??
          (_runtime.label.startsWith('已完成')
              ? _runtime.label
              : formatSubtitleFillCompactLabel(
                  doneCount: 0,
                  totalCount: 1,
                  currentPercent: (_runtime.progress * 100).round(),
                ));
      final String tooltip =
          (summary?.detailLabel ?? _runtime.label).trim().isEmpty
          ? '正在补字幕 $compact'
          : (summary?.detailLabel ?? _runtime.label);
      final double progress =
          (summary?.overallProgress ?? _runtime.progress).clamp(0.05, 0.99);
      return GestureDetector(
        onLongPress: () => unawaited(_toggleOverlayBall()),
        child: FloatingActionButton.extended(
          key: const ValueKey<String>('subtitle-fill-fab'),
          heroTag: 'global-subtitle-fill',
          tooltip: _overlayDismissed
              ? '$tooltip · 长按可恢复悬浮球'
              : '$tooltip · 长按可隐藏悬浮球',
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _overlayDismissed
                      ? '$tooltip（后台悬浮球已隐藏，长按可恢复）'
                      : '$tooltip（长按可隐藏后台悬浮球）',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          backgroundColor: const Color(0xFF3B7CFF),
          foregroundColor: Colors.white,
          elevation: 3,
          shape: const StadiumBorder(),
          icon: SizedBox(
            width: 22,
            height: 22,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2.4,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
                Icon(
                  _overlayDismissed
                      ? Icons.visibility_off_rounded
                      : Icons.subtitles_rounded,
                  size: 12,
                ),
              ],
            ),
          ),
          label: Text(
            compact,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    final ContinueLearningTarget? target = ref.watch(
      continueLearningTargetProvider,
    );
    if (target == null) {
      return const SizedBox.shrink();
    }
    return FloatingActionButton.extended(
      key: const ValueKey<String>('continue-learning-button'),
      heroTag: 'global-continue-learning',
      tooltip: '继续学习《${target.course.title}》 · 第 ${target.episode.numberStr} 集',
      onPressed: _isOpening
          ? null
          : () async {
              if (_isOpening) {
                return;
              }
              setState(() => _isOpening = true);
              try {
                await context.pushNamed<void>(
                  SGRoute.player.name,
                  pathParameters: <String, String>{
                    'episodeId': target.episode.id,
                  },
                  queryParameters: const <String, String>{'autoplay': '1'},
                );
              } finally {
                if (mounted) {
                  setState(() => _isOpening = false);
                }
              }
            },
      backgroundColor: AppDesignTokens.brandGreen,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: const StadiumBorder(),
      icon: const Icon(Icons.play_circle_fill_rounded),
      label: Text(
        '继续播放第 ${target.episode.numberStr} 集',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}
