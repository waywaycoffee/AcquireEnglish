import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/widgets/bilibili_brand_icon.dart';
import 'bilibili_import_sheet.dart';
import 'import_course_screen.dart';
import 'netdisk_import_sheet.dart';
import 'youtube_import_sheet.dart';

/// Shared YouTube / B站 / 本地导入 entry used by 学习页 and 首页.
class CourseImportActionButtons extends ConsumerWidget {
  const CourseImportActionButtons({
    this.enabled = true,
    this.compact = false,
    super.key,
  });

  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final EdgeInsets pad = EdgeInsets.symmetric(
      horizontal: compact ? 8 : 10,
      vertical: compact ? 12 : 14,
    );
    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            onPressed: enabled
                ? () {
                    unawaited(showYoutubeImportSheet(context, ref));
                  }
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppDesignTokens.primaryBlueDark,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.standard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              padding: pad,
              elevation: 0,
            ),
            icon: const Icon(Icons.ondemand_video_rounded, size: 18),
            label: const Text(
              'YouTube',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: enabled
                ? () {
                    unawaited(showBilibiliImportSheet(context, ref));
                  }
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFB7299),
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.standard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              padding: pad,
              elevation: 0,
            ),
            icon: const BilibiliBrandIcon(size: 18),
            label: const Text(
              'B站',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: enabled
                ? () {
                    openImportCourseExperience(context);
                  }
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppDesignTokens.brandGreen,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.standard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              padding: pad,
              elevation: 0,
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text(
              '本地',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: enabled
                ? () {
                    unawaited(showNetdiskImportSheet(context, ref));
                  }
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.standard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              padding: pad,
              elevation: 0,
            ),
            icon: const Icon(Icons.cloud_download_rounded, size: 18),
            label: const Text(
              '网盘',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bottom sheet with the same three import actions as 学习页.
Future<void> showCourseImportEntrySheet(
  BuildContext context,
  WidgetRef ref,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppDesignTokens.appWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '导入课程',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'YouTube、B站、本地或自己的百度/夸克网盘',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              const CourseImportActionButtons(compact: true),
            ],
          ),
        ),
      );
    },
  );
}
