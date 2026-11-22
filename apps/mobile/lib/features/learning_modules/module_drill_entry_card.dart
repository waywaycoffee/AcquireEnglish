import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared/presentation/pad/app_design_tokens.dart';

/// Entry to the original ModuleScreen drills (TTS + quiz), kept alongside
/// Bilibili shadowing courses so the authored curriculum is not discarded.
class ModuleDrillEntryCard extends StatelessWidget {
  const ModuleDrillEntryCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: AppDesignTokens.brandGreenDark.withValues(alpha: 0.06),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor:
              AppDesignTokens.brandGreenDark.withValues(alpha: 0.14),
          child: const Icon(Icons.school_outlined),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle, style: const TextStyle(height: 1.35)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(route),
      ),
    );
  }
}
