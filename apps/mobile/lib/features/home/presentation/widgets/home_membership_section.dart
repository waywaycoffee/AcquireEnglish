import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../router/app_router.dart';
import '../../../authentication/presentation/auth_session.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/pad/hub_ui.dart';
import '../../../sync/data/user_assets_service.dart';
import '../../../sync/presentation/user_assets_provider.dart';

class HomeMembershipSection extends ConsumerWidget {
  const HomeMembershipSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool loggedIn = ref.watch(authSessionProvider).isLoggedIn;
    final UserAssetsSnapshot? assets =
        ref.watch(userAssetsProvider).asData?.value;
    final String? membership = assets?.activeMembership?.trim();
    final bool isMember =
        membership != null && membership.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _MembershipPayCard(
          loggedIn: loggedIn,
          isMember: isMember,
          membership: membership,
          onOpen: () {
            if (!loggedIn) {
              context.push(SGRoute.login.route);
              return;
            }
            context.push(SGRoute.membership.route);
          },
        ),
        const SizedBox(height: 14),
        _MemberBadgesRow(isMember: isMember, membership: membership),
      ],
    );
  }
}

class _MembershipPayCard extends StatelessWidget {
  const _MembershipPayCard({
    required this.loggedIn,
    required this.isMember,
    required this.membership,
    required this.onOpen,
  });

  final bool loggedIn;
  final bool isMember;
  final String? membership;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final String title = isMember ? 'Pro 会员已开通' : '开通 Pro 会员';
    final String subtitle = !loggedIn
        ? '登录后可开通会员，解锁专属权益与勋章'
        : isMember
            ? '当前方案 · ${membership!.toUpperCase()} · 管理续费与权益'
            : '微信支付开通 · 口语额度 · 专属勋章 · 学习加速';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isMember
                  ? const <Color>[Color(0xFFFFC800), Color(0xFFFF9600)]
                  : const <Color>[Color(0xFF1CB0F6), Color(0xFF58CC02)],
            ),
            boxShadow: AppDesignTokens.toyCardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
            child: Row(
              children: <Widget>[
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    isMember
                        ? Icons.workspace_premium_rounded
                        : Icons.diamond_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 12.5,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    isMember ? '查看' : '去开通',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: isMember
                          ? AppDesignTokens.orange
                          : AppDesignTokens.primaryBlueDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberBadgesRow extends StatelessWidget {
  const _MemberBadgesRow({
    required this.isMember,
    required this.membership,
  });

  final bool isMember;
  final String? membership;

  @override
  Widget build(BuildContext context) {
    final List<_BadgeSpec> badges = <_BadgeSpec>[
      _BadgeSpec(
        label: 'Pro 会员',
        icon: Icons.workspace_premium_rounded,
        unlocked: isMember,
        color: const Color(0xFFFF9600),
        bg: const Color(0xFFFFF1D6),
      ),
      _BadgeSpec(
        label: '绿叶学伴',
        icon: Icons.eco_rounded,
        unlocked: isMember,
        color: AppDesignTokens.brandGreenDark,
        bg: const Color(0xFFE8F8D8),
      ),
      _BadgeSpec(
        label: '口语加速',
        icon: Icons.record_voice_over_rounded,
        unlocked: isMember,
        color: AppDesignTokens.primaryBlueDark,
        bg: AppDesignTokens.skyLight,
      ),
      _BadgeSpec(
        label: '专属勋章',
        icon: Icons.military_tech_rounded,
        unlocked: isMember &&
            (membership?.toLowerCase().contains('pro') ?? false),
        color: const Color(0xFFC2185B),
        bg: AppDesignTokens.pinkLight,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        HubSectionTitle(
          '会员勋章',
          action: isMember ? null : '开通解锁',
          onAction: isMember
              ? null
              : () => context.push(SGRoute.membership.route),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: badges.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (BuildContext context, int index) {
              final _BadgeSpec b = badges[index];
              return _BadgeChip(spec: b);
            },
          ),
        ),
      ],
    );
  }
}

class _BadgeSpec {
  const _BadgeSpec({
    required this.label,
    required this.icon,
    required this.unlocked,
    required this.color,
    required this.bg,
  });

  final String label;
  final IconData icon;
  final bool unlocked;
  final Color color;
  final Color bg;
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.spec});

  final _BadgeSpec spec;

  @override
  Widget build(BuildContext context) {
    final bool on = spec.unlocked;
    return Opacity(
      opacity: on ? 1 : 0.55,
      child: Container(
        width: 96,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        decoration: BoxDecoration(
          color: AppDesignTokens.appWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: on ? spec.color.withValues(alpha: 0.35) : AppDesignTokens.borderGray,
          ),
          boxShadow: on ? AppDesignTokens.toyCardShadow : null,
        ),
        child: Column(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: on ? spec.bg : AppDesignTokens.softGray,
                shape: BoxShape.circle,
              ),
              child: Icon(
                on ? spec.icon : Icons.lock_outline_rounded,
                color: on ? spec.color : AppDesignTokens.textSecondary,
                size: 22,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              spec.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            Text(
              on ? '已点亮' : '未解锁',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: on ? spec.color : AppDesignTokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
