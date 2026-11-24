import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';

/// Personal referral QR + conversion stats (successful app registrations).
Future<void> showInvitePromoSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppDesignTokens.appWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext ctx) => const _InvitePromoSheet(),
  );
}

class _InvitePromoSheet extends ConsumerStatefulWidget {
  const _InvitePromoSheet();

  @override
  ConsumerState<_InvitePromoSheet> createState() => _InvitePromoSheetState();
}

class _InvitePromoSheetState extends ConsumerState<_InvitePromoSheet> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(acquireApiClientProvider).fetchInviteCode();
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets inset = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + inset.bottom),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (
          BuildContext context,
          AsyncSnapshot<Map<String, dynamic>> snapshot,
        ) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  '加载失败：${snapshot.error}',
                  style: TextStyle(color: AppDesignTokens.dangerText),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _future =
                          ref.read(acquireApiClientProvider).fetchInviteCode();
                    });
                  },
                  child: const Text('重试'),
                ),
              ],
            );
          }
          final Map<String, dynamic> data =
              snapshot.data ?? const <String, dynamic>{};
          final String code = '${data['invite_code'] ?? ''}'.trim();
          final String url = '${data['download_url'] ?? ''}'.trim().isNotEmpty
              ? '${data['download_url']}'.trim()
              : '${data['download_url_android'] ?? ''}'.trim();
          final int success =
              (data['successful_registrations'] as num?)?.toInt() ?? 0;
          final int points =
              (data['points_earned_from_referrals'] as num?)?.toInt() ?? 0;
          final int weeks =
              (data['pro_weeks_earned'] as num?)?.toInt() ?? 0;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '我的推广二维码',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '专属邀请码，好友扫码下载并注册成功后计入你的推广人数；你可得积分与 Pro 一周。',
                  style: TextStyle(
                    color: AppDesignTokens.textSecondary,
                    height: 1.4,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: url.isEmpty
                        ? const SizedBox(width: 200, height: 200)
                        : QrImageView(
                            data: url,
                            size: 200,
                            backgroundColor: Colors.white,
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    '邀请码 $code',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _StatCard(
                        value: '$success',
                        label: '成功注册用户',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        value: '$points',
                        label: '推广所得积分',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        value: '$weeks',
                        label: '获得 Pro 周数',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: url.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: url));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制专属推广链接')),
                          );
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppDesignTokens.textPrimary,
                    side: BorderSide(color: AppDesignTokens.borderGray),
                  ),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('复制专属链接'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppDesignTokens.softWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppDesignTokens.borderGray),
      ),
      child: Column(
        children: <Widget>[
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppDesignTokens.brandGreen,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
