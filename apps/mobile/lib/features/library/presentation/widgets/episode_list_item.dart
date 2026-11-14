import 'dart:io';

import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../library_mock_data.dart';
import 'library_course_poster.dart';

bool _isDisplayableCoverPath(String raw) {
  final String value = raw.trim();
  if (value.isEmpty || value.startsWith('assets/')) {
    return false;
  }
  if (value.startsWith('http://') ||
      value.startsWith('https://') ||
      value.startsWith('//')) {
    return true;
  }
  try {
    return File(value).existsSync();
  } catch (_) {
    return false;
  }
}

class EpisodeListItem extends StatelessWidget {
  const EpisodeListItem({
    required this.item,
    required this.selected,
    required this.onTap,
    this.onViewTranscript,
    this.trailing,
    this.fallbackCoverImage,
    super.key,
  });

  final LibraryEpisodeItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onViewTranscript;
  final Widget? trailing;

  /// Course-level cover used when the episode has no poster of its own.
  final String? fallbackCoverImage;

  @override
  Widget build(BuildContext context) {
    final bool inProgress = item.progressPercent > 0 && !item.completed;
    final bool notStarted = !item.completed && item.progressPercent == 0;
    final String statusText = item.completed
        ? '已完成'
        : inProgress
        ? _progressStatusText(item)
        : '开始学习';

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
            600;
        final Widget title = Text(
          item.title,
          maxLines: narrow ? 3 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: narrow ? 17 : 20,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.textPrimary,
          ),
        );
        final Widget meta = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _StatusChip(
                  icon: item.completed
                      ? Icons.check_circle_rounded
                      : inProgress
                      ? Icons.play_circle_rounded
                      : Icons.bolt_rounded,
                  label: statusText,
                  backgroundColor: selected
                      ? const Color(0xFFDDF7E8)
                      : AppDesignTokens.softWhite,
                  textColor: AppDesignTokens.brandGreenDark,
                ),
                if (item.videoMissing)
                  _InfoChip(
                    icon: _isPendingBilibiliDownload(item)
                        ? Icons.cloud_download_rounded
                        : Icons.warning_amber_rounded,
                    label: _isPendingBilibiliDownload(item) ? '待下载' : '文件缺失',
                    backgroundColor: _isPendingBilibiliDownload(item)
                        ? const Color(0xFFE8F1FF)
                        : const Color(0xFFFFE1E1),
                    textColor: _isPendingBilibiliDownload(item)
                        ? AppDesignTokens.primaryBlueDark
                        : const Color(0xFFBA1A1A),
                  ),
                _InfoChip(
                  icon: Icons.closed_caption_rounded,
                  label: item.hasEnglishSubtitles
                      ? '英文字幕'
                      : (_isPendingBilibiliDownload(item)
                            ? '英文字幕待获取'
                            : '无外部英文字幕'),
                ),
                _InfoChip(
                  icon: item.hasChineseSubtitles
                      ? Icons.translate_rounded
                      : (_isPendingBilibiliDownload(item)
                            ? Icons.cloud_download_rounded
                            : Icons.warning_rounded),
                  label: item.hasChineseSubtitles
                      ? '中文字幕'
                      : (_isPendingBilibiliDownload(item)
                            ? '中文字幕待获取'
                            : '无中文字幕'),
                  backgroundColor: item.hasChineseSubtitles
                      ? AppDesignTokens.pinkLight
                      : (_isPendingBilibiliDownload(item)
                            ? const Color(0xFFE8F1FF)
                            : const Color(0xFFFFE1E1)),
                  textColor: item.hasChineseSubtitles
                      ? AppDesignTokens.textPrimary
                      : (_isPendingBilibiliDownload(item)
                            ? AppDesignTokens.primaryBlueDark
                            : const Color(0xFFBA1A1A)),
                ),
                _InfoChip(
                  icon: Icons.schedule_rounded,
                  label: '${item.durationMinutes} 分钟',
                  textColor: AppDesignTokens.textSecondary,
                ),
                if ((item.lastWatchedStr ?? '').isNotEmpty)
                  _InfoChip(
                    icon: Icons.history_rounded,
                    label: item.lastWatchedStr!,
                    backgroundColor: AppDesignTokens.purpleLight,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: item.progressPercent / 100,
                minHeight: 10,
                backgroundColor: AppDesignTokens.softGray,
                valueColor: AlwaysStoppedAnimation<Color>(
                  item.completed
                      ? AppDesignTokens.primaryBlue
                      : AppDesignTokens.brandGreen,
                ),
              ),
            ),
          ],
        );
        final Widget thumb = _EpisodeThumb(
          item: item,
          selected: selected,
          narrow: narrow,
          fallbackCoverImage: fallbackCoverImage,
        );
        final Widget playIndicator = Icon(
          selected
              ? Icons.play_circle_fill_rounded
              : notStarted
              ? Icons.arrow_forward_rounded
              : Icons.chevron_right_rounded,
          size: 28,
          color: selected
              ? AppDesignTokens.brandGreenDark
              : AppDesignTokens.primaryBlueDark,
        );
        final Widget? transcriptButton = onViewTranscript == null
            ? null
            : OutlinedButton.icon(
                key: ValueKey<String>('episode-view-transcript-${item.id}'),
                onPressed: onViewTranscript,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                icon: const Icon(Icons.menu_book_rounded, size: 18),
                label: const Text('查看全文'),
              );
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(26),
          child: Ink(
            padding: EdgeInsets.all(narrow ? 14 : 18),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFEFFFF5)
                  : AppDesignTokens.appWhite,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: selected
                    ? AppDesignTokens.brandGreen
                    : AppDesignTokens.borderGray,
                width: selected ? 2 : 1.2,
              ),
              boxShadow: AppDesignTokens.toyCardShadow,
            ),
            child: narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          thumb,
                          const SizedBox(width: 12),
                          Expanded(child: title),
                          const SizedBox(width: 8),
                          trailing ?? playIndicator,
                        ],
                      ),
                      const SizedBox(height: 12),
                      meta,
                      if (transcriptButton != null) ...<Widget>[
                        const SizedBox(height: 12),
                        transcriptButton,
                      ],
                    ],
                  )
                : Row(
                    children: <Widget>[
                      thumb,
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            title,
                            const SizedBox(height: 10),
                            meta,
                          ],
                        ),
                      ),
                      if (transcriptButton != null) ...<Widget>[
                        const SizedBox(width: 12),
                        transcriptButton,
                      ],
                      const SizedBox(width: 16),
                      trailing ?? playIndicator,
                    ],
                  ),
          ),
        );
      },
    );
  }

  bool _isPendingBilibiliDownload(LibraryEpisodeItem item) {
    final String asset = (item.videoAsset ?? '').trim();
    if (!item.videoMissing || asset.isEmpty) {
      return false;
    }
    final String lower = asset.toLowerCase();
    return lower.contains('bilibili.com') ||
        lower.contains('b23.tv') ||
        lower.contains('bili2233.cn') ||
        asset.toUpperCase().contains('BV') ||
        lower.startsWith('av');
  }

  String _progressStatusText(LibraryEpisodeItem item) {
    final int totalSeconds = item.durationMinutes * 60;
    final int progressSeconds = (totalSeconds * item.progressPercent / 100)
        .round();
    final String progress = (item.progressTimeStr?.isNotEmpty ?? false)
        ? item.progressTimeStr!
        : _formatSeconds(progressSeconds);
    final String total = (item.totalTimeStr?.isNotEmpty ?? false)
        ? item.totalTimeStr!
        : _formatSeconds(totalSeconds);
    return '$progress / $total';
  }

  String _formatSeconds(int totalSeconds) {
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _EpisodeThumb extends StatelessWidget {
  const _EpisodeThumb({
    required this.item,
    required this.selected,
    required this.narrow,
    this.fallbackCoverImage,
  });

  final LibraryEpisodeItem item;
  final bool selected;
  final bool narrow;
  final String? fallbackCoverImage;

  String get _resolvedCover {
    final String own = item.coverImage.trim();
    if (_isDisplayableCoverPath(own)) {
      return own.startsWith('//') ? 'https:$own' : own;
    }
    final String fallback = (fallbackCoverImage ?? '').trim();
    if (_isDisplayableCoverPath(fallback)) {
      return fallback.startsWith('//') ? 'https:$fallback' : fallback;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final double width = narrow ? 96 : 120;
    final double height = narrow ? 72 : 90;
    final BorderRadius radius = BorderRadius.circular(16);
    final String cover = _resolvedCover;
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Reuse course poster renderer — already proven to load B 站 covers.
            LibraryCoursePoster(
              title: item.numberStr,
              path: cover,
              borderRadius: radius,
              fit: BoxFit.cover,
            ),
            if (selected)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppDesignTokens.brandGreen,
                    width: 2,
                  ),
                  borderRadius: radius,
                ),
              ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                margin: const EdgeInsets.all(6),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.numberStr,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.backgroundColor,
    this.textColor,
  });

  final IconData icon;
  final String label;
  final Color? backgroundColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final Color bg = backgroundColor ?? AppDesignTokens.softWhite;
    final Color fg = textColor ?? AppDesignTokens.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
