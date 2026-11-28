import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../navigation/presentation/navigation_destination.dart';
import 'pad/app_design_tokens.dart';

/// Pencil shell header: search field + local-files + notifications.
class ShellTopChrome extends StatelessWidget {
  const ShellTopChrome({
    super.key,
    this.searchHint = '搜索',
    this.onSearchTap,
  });

  final String searchHint;
  final VoidCallback? onSearchTap;

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
                      // Prefer library search when available.
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
          const SizedBox(width: 8),
          _ChromeIconButton(
            icon: Icons.folder_outlined,
            tooltip: '本地文件',
            onTap: () => context.push('/importCourse'),
          ),
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
