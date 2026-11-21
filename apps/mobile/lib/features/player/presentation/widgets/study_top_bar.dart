import 'package:flutter/material.dart';

import 'study_shell_tokens.dart';

class StudyTopBar extends StatelessWidget {
  const StudyTopBar({
    required this.title,
    required this.onBack,
    this.onFavorite,
    this.isFavorite = false,
    this.lessonBadge,
    this.watchModeLabel,
    this.onToggleWatchMode,
    super.key,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback? onFavorite;
  final bool isFavorite;
  final String? lessonBadge;

  /// `精听` / `追剧` chip; null hides the toggle.
  final String? watchModeLabel;
  final VoidCallback? onToggleWatchMode;

  @override
  Widget build(BuildContext context) {
    final StudyShellColors colors = StudyShellColors.of(context);
    final double topInset = MediaQuery.paddingOf(context).top;
    return Container(
      color: colors.background,
      padding: EdgeInsets.fromLTRB(4, topInset + 2, 4, 4),
      child: SizedBox(
        height: 44,
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: '返回',
              onPressed: onBack,
              icon: Icon(
                Icons.chevron_left_rounded,
                color: colors.textPrimary,
                size: 30,
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (lessonBadge != null)
                    Text(
                      lessonBadge!,
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            if (watchModeLabel != null && onToggleWatchMode != null)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Material(
                  color: watchModeLabel == '追剧'
                      ? colors.accent.withValues(alpha: 0.2)
                      : colors.chipIdle,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    key: const ValueKey<String>('player-watch-mode-toggle'),
                    onTap: onToggleWatchMode,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        watchModeLabel!,
                        style: TextStyle(
                          color: watchModeLabel == '追剧'
                              ? colors.accent
                              : colors.textSecondary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            IconButton(
              tooltip: '收藏',
              onPressed: onFavorite,
              icon: Icon(
                isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: isFavorite ? colors.favorite : colors.textPrimary,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
