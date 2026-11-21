import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../import_course/data/bilibili_collection_download.dart';
import '../../import_course/data/netdisk_local_download.dart';
import '../../import_course/data/video_download_progress_ui.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../player/presentation/learning_resume_provider.dart';
import '../../subtitle_completion/native_subtitle_ball.dart';
import 'pad/app_design_tokens.dart';

/// Global FAB: while video downloads run, shows blue progress; otherwise「继续播放」.
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

  @override
  void initState() {
    super.initState();
    unawaited(_refreshOverlayDismissed());
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
              ? '已隐藏后台悬浮球（下载仍继续）'
              : '已恢复后台悬浮球（离开 App 后显示）',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final BilibiliCollectionDownloadProgress? bilibili = ref.watch(
      bilibiliCollectionDownloadProgressProvider,
    );
    final NetdiskDownloadProgress? netdisk = ref.watch(
      netdiskDownloadProgressProvider,
    );
    final ActiveVideoDownload? download = resolveActiveVideoDownload(
      bilibili: bilibili,
      netdisk: netdisk,
    );

    if (download != null) {
      final double progress = download.progress.clamp(0.05, 0.99);
      final String tooltip = download.message.trim().isEmpty
          ? '正在下载视频 ${download.compactLabel}'
          : download.message;
      return GestureDetector(
        onLongPress: () => unawaited(_toggleOverlayBall()),
        child: FloatingActionButton.extended(
          key: const ValueKey<String>('video-download-fab'),
          heroTag: 'global-video-download',
          tooltip: _overlayDismissed
              ? '$tooltip · 长按可恢复悬浮球'
              : '$tooltip · 长按可隐藏悬浮球',
          onPressed: () {
            unawaited(_refreshOverlayDismissed());
            final String courseId = download.courseId.trim();
            if (courseId.isNotEmpty) {
              context.go(
                Uri(
                  path: AppNavDestination.library.route,
                  queryParameters: <String, String>{
                    'view': 'detail',
                    'courseId': courseId,
                  },
                ).toString(),
              );
              return;
            }
            context.go(SGRoute.library.route);
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
                      : Icons.download_rounded,
                  size: 12,
                ),
              ],
            ),
          ),
          label: Text(
            download.compactLabel,
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
