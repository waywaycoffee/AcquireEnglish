import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../navigation/presentation/navigation_destination.dart';
import 'pad/app_design_tokens.dart';

/// Pencil shell header: search field + local-files (+ optional notifications).
class ShellTopChrome extends StatelessWidget {
  const ShellTopChrome({
    super.key,
    this.searchHint = '搜索',
    this.onSearchTap,
    this.onFilesTap,
    this.showNotifications = true,
    this.filesLabeled = false,
  });

  final String searchHint;
  final VoidCallback? onSearchTap;
  final VoidCallback? onFilesTap;
  final bool showNotifications;

  /// Pencil video-home: show「本地文件」caption under the folder icon.
  final bool filesLabeled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Material(
              color: AppDesignTokens.appWhite,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: onSearchTap ??
                    () {
                      context.go(AppNavDestination.library.route);
                    },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: AppDesignTokens.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          searchHint,
                          style: TextStyle(
                            color: AppDesignTokens.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (filesLabeled)
            _LabeledFilesButton(
              onTap: onFilesTap ?? () => context.push('/library/local-files'),
            )
          else
            _ChromeIconButton(
              icon: Icons.folder_outlined,
              tooltip: '本地文件',
              onTap: onFilesTap ?? () => context.push('/library/local-files'),
            ),
          if (showNotifications)
            _ChromeIconButton(
              icon: Icons.notifications_none_rounded,
              tooltip: '通知',
              onTap: () => context.push(AppNavDestination.settings.route),
            ),
        ],
      ),
    );
  }
}

class _LabeledFilesButton extends StatelessWidget {
  const _LabeledFilesButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '本地文件',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.folder_outlined,
                size: 22,
                color: AppDesignTokens.textPrimary,
              ),
              const SizedBox(height: 2),
              Text(
                '本地文件',
                style: TextStyle(
                  color: AppDesignTokens.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: AppDesignTokens.textPrimary),
    );
  }
}
