import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/user_assets_service.dart';
import '../../sync/presentation/user_assets_provider.dart';

bool isProMembership(String? activeMembership) {
  final String value = (activeMembership ?? '').trim().toLowerCase();
  return value == 'pro' || value.contains('pro');
}

/// Compact exclusive Pro mark for account surfaces.
class ProMemberBadge extends StatelessWidget {
  const ProMemberBadge({
    super.key,
    this.compact = false,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF1B5E20), Color(0xFF43A047)],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppDesignTokens.brandGreen.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.workspace_premium_rounded,
            size: compact ? 11 : 13,
            color: Colors.white,
          ),
          SizedBox(width: compact ? 3 : 4),
          Text(
            'Pro',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Watches [userAssetsProvider] and only paints when Pro is active.
class ProMemberBadgeIfActive extends ConsumerWidget {
  const ProMemberBadgeIfActive({
    super.key,
    this.compact = false,
  });

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserAssetsSnapshot? assets =
        ref.watch(userAssetsProvider).asData?.value;
    if (!isProMembership(assets?.activeMembership)) {
      return const SizedBox.shrink();
    }
    return ProMemberBadge(compact: compact);
  }
}
