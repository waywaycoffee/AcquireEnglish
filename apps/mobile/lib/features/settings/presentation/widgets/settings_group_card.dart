import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/pad/pad_compact.dart';

class SettingsGroupCard extends StatelessWidget {
  const SettingsGroupCard({
    required this.title,
    required this.icon,
    required this.children,
    super.key,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final bool compact = context.isPadCompact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              icon,
              size: compact ? 16 : 18,
              color: AppDesignTokens.brandGreenDark,
            ),
            SizedBox(width: compact ? 6 : 8),
            Text(
              title,
              style: TextStyle(
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w800,
                color: AppDesignTokens.brandGreenDark,
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 10 : 12),
        // Material (not DecoratedBox) so ListTile ink/background paint correctly.
        Material(
          color: AppDesignTokens.appWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(compact ? 20 : 24),
            side: BorderSide(color: AppDesignTokens.borderGray),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}
