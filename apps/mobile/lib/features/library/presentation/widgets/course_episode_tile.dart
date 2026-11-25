import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../idle_jobs/idle_job_drain.dart';
import '../../../import_course/data/netdisk_drama_reservation.dart';
import '../../../import_course/data/netdisk_local_download.dart';
import '../../../player/domain/episode_study_progress.dart';
import '../../../player/presentation/episode_study_progress_provider.dart';
import '../../../subtitle_completion/subtitle_completion_status_provider.dart';
import '../library_mock_data.dart';
import 'episode_list_item.dart';

/// One virtualized course-detail episode row.
///
/// Watches only this episode's subtitle-fill slice so a 200+ 集 list does not
/// rebuild every row when the completion poller ticks.
class CourseEpisodeTile extends ConsumerWidget {
  const CourseEpisodeTile({
    required this.item,
    required this.selected,
    required this.fallbackCoverImage,
    required this.onTap,
    required this.onViewTranscript,
    required this.onRerecognizeEnglish,
    required this.onRerecognizeChinese,
    required this.onMissingEnglishTap,
    required this.onMissingChineseTap,
    this.courseId,
    this.trailing,
    this.bottomPadding = 16,
    super.key,
  });

  final LibraryEpisodeItem item;
  final bool selected;
  final String? fallbackCoverImage;
  final VoidCallback onTap;
  final VoidCallback onViewTranscript;
  final VoidCallback onRerecognizeEnglish;
  final VoidCallback onRerecognizeChinese;
  final VoidCallback onMissingEnglishTap;
  final VoidCallback onMissingChineseTap;
  final String? courseId;
  final Widget? trailing;
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ({
      String? englishLabel,
      String? chineseLabel,
      bool englishFailed,
      bool chineseFailed,
      bool active,
      double? progress,
    })?
    fill = ref.watch(
      subtitleCompletionStatusProvider.select((
        SubtitleCompletionStatusState state,
      ) {
        final SubtitleCompletionEpisodeUi? ui = state.forEpisode(item.id);
        if (ui == null) {
          return null;
        }
        return (
          englishLabel: ui.englishChipProgressLabel,
          chineseLabel: ui.chineseChipProgressLabel,
          englishFailed: ui.isFailed && ui.needEnglish,
          chineseFailed: ui.isFailed && ui.needChinese,
          active: ui.isActive,
          progress: ui.progressFraction,
        );
      }),
    );
    final EpisodeStudyStage studyStage = ref.watch(
      episodeStudyProgressProvider.select(
        (Map<String, EpisodeStudyProgress> map) =>
            episodeProgressOf(map, item.id).stage,
      ),
    );
    final String? cacheKey = netdiskEpisodeCacheKey(item);
    final NetdiskEpisodeCacheInfo? cache = cacheKey == null
        ? null
        : ref.watch(
            netdiskEpisodeCacheProvider.select(
              (Map<String, NetdiskEpisodeCacheInfo> map) => map[cacheKey],
            ),
          );
    final bool showDownload = cacheKey != null &&
        (netdiskPlayUrlForEpisode(item) != null || cache != null);
    final bool reserved = isNetdiskDramaEpisodeReserved(item.id) ||
        (cache?.isScheduled ?? false);
    final String? downloadLabel = !showDownload
        ? null
        : (cache?.label ?? (reserved ? '已预约字幕' : '未下载'));

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: EpisodeListItem(
        item: item,
        selected: selected,
        fallbackCoverImage: fallbackCoverImage,
        englishFillLabel: fill?.englishLabel,
        chineseFillLabel: fill?.chineseLabel,
        englishFillFailed: fill?.englishFailed ?? false,
        chineseFillFailed: fill?.chineseFailed ?? false,
        subtitleFillActive: fill?.active ?? false,
        subtitleFillProgress: fill?.progress,
        studyStage: studyStage,
        downloadLabel: downloadLabel,
        downloadProgress: cache?.progress,
        downloadReady: cache?.isReady ?? false,
        downloadActive: (cache?.isDownloading ?? false) ||
            ((cache?.progress != null) &&
                !(cache?.isReady ?? false) &&
                (reserved ||
                    cache?.phase == NetdiskEpisodeCachePhase.partial)),
        onDownloadTap: showDownload &&
                !(cache?.isReady ?? false) &&
                !(cache?.isDownloading ?? false)
            ? () {
                if (reserved) {
                  unawaited(cancelNetdiskDramaEpisode(item.id));
                  return;
                }
                final String? cid = courseId;
                if (cid == null || cid.isEmpty) return;
                unawaited(() async {
                  final bool ok = await scheduleNetdiskDramaEpisode(
                    episode: item,
                    courseId: cid,
                  );
                  if (ok) {
                    kickNetdiskDramaIdleDrain(ref);
                  }
                }());
              }
            : null,
        onTap: onTap,
        onViewTranscript: onViewTranscript,
        onRerecognizeEnglish: onRerecognizeEnglish,
        onRerecognizeChinese: onRerecognizeChinese,
        onMissingEnglishTap: onMissingEnglishTap,
        onMissingChineseTap: onMissingChineseTap,
        trailing: trailing,
      ),
    );
  }
}
