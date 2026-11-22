import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
