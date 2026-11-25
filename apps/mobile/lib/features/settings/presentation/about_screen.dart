import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../utils/url_utils.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_compact.dart';
import '../domain/app_legal_info.dart';
import 'app_update_provider.dart';

/// Clean About / 尾页 for store & WeChat Pay review (no API keys).
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  static const String route = '/settings/about';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool compact = context.isPadCompact;
    final AsyncValue<String> appVersion = ref.watch(appVersionProvider);

    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        backgroundColor: AppDesignTokens.appWhite,
        foregroundColor: AppDesignTokens.textPrimary,
        title: const Text('关于爱快英语'),
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          context.padPagePadding,
          24,
          context.padPagePadding,
          40,
        ),
        children: <Widget>[
          Center(
            child: Column(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset(
                    'assets/img/app_icon.png',
                    width: 88,
                    height: 88,
                    errorBuilder: (_, _, _) => Container(
                      width: 88,
                      height: 88,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppDesignTokens.successSoft,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Text(
                        'AQ',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: AppDesignTokens.brandGreenDark,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppLegalInfo.appDisplayName,
                  style: TextStyle(
                    fontSize: compact ? 26 : 28,
                    fontWeight: FontWeight.w900,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppLegalInfo.appEnglishName,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  appVersion.when(
                    data: (String v) => '版本 v$v',
                    loading: () => '版本加载中…',
                    error: (_, _) => '版本未知',
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _AboutCard(
            children: <Widget>[
              _AboutLine(label: '应用名称', value: AppLegalInfo.appDisplayName),
              _AboutLine(label: '开发公司', value: AppLegalInfo.companyName),
              _AboutLine(label: '应用包名', value: AppLegalInfo.packageName),
              if (AppLegalInfo.icpFilingNumber.trim().isNotEmpty)
                _AboutLine(
                  label: 'APP 备案号',
                  value: AppLegalInfo.icpFilingNumber,
                  onTap: () => openUrl(Uri.parse(AppLegalInfo.icpQueryUrl)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _AboutCard(
            children: <Widget>[
              _AboutLink(
                title: '用户协议',
                onTap: () => openUrl(Uri.parse(AppLegalInfo.termsUrl)),
              ),
              _AboutLink(
                title: '隐私政策',
                onTap: () => openUrl(Uri.parse(AppLegalInfo.privacyUrl)),
              ),
              _AboutLink(
                title: '联系邮箱',
                subtitle: AppLegalInfo.supportEmail,
                onTap: () => openUrl(
                  Uri.parse('mailto:${AppLegalInfo.supportEmail}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            '© ${DateTime.now().year} ${AppLegalInfo.companyName}\n保留所有权利。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppDesignTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppDesignTokens.borderGray),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0)
              Divider(height: 1, color: AppDesignTokens.borderGray),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _AboutLine extends StatelessWidget {
  const _AboutLine({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppDesignTokens.textPrimary,
              ),
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.open_in_new_rounded,
              size: 16,
              color: AppDesignTokens.textSecondary,
            ),
        ],
      ),
    );
    if (onTap == null) return child;
    return InkWell(onTap: onTap, child: child);
  }
}

class _AboutLink extends StatelessWidget {
  const _AboutLink({
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: AppDesignTokens.textPrimary,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(color: AppDesignTokens.textSecondary),
            ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: AppDesignTokens.textSecondary,
      ),
      onTap: onTap,
    );
  }
}
