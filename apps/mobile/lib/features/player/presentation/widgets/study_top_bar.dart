import 'package:flutter/material.dart';

import 'study_shell_tokens.dart';

class StudyTopBar extends StatelessWidget {
  const StudyTopBar({
    required this.title,
    required this.onBack,
    this.onFavorite,
    this.isFavorite = false,
    this.lessonBadge,
    super.key,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback? onFavorite;
  final bool isFavorite;
  final String? lessonBadge;

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
