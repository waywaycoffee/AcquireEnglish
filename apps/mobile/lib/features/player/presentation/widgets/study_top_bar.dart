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
    final double topInset = MediaQuery.paddingOf(context).top;
    return Container(
      color: StudyShellTokens.background,
      padding: EdgeInsets.fromLTRB(8, topInset + 4, 8, 6),
      child: SizedBox(
        height: 44,
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: '返回',
              onPressed: onBack,
              icon: const Icon(
                Icons.chevron_left_rounded,
                color: StudyShellTokens.textPrimary,
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
                    style: const TextStyle(
                      color: StudyShellTokens.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (lessonBadge != null)
                    Text(
                      lessonBadge!,
                      style: const TextStyle(
                        color: StudyShellTokens.textMuted,
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
                isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFavorite
                    ? const Color(0xFFFF5A7A)
                    : StudyShellTokens.textPrimary,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
