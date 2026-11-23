import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../constants/assets.dart';
import '../../import_course/presentation/netdisk_import_sheet.dart';
import '../../import_course/presentation/youtube_import_sheet.dart';
import '../../settings/presentation/bilibili_login_sheet.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_compact.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';

/// Settings hub for Bilibili / YouTube / netdisk authorization.
class AuthSourcesSettingsScreen extends ConsumerWidget {
  const AuthSourcesSettingsScreen({super.key});

  static const String route = '/settings/auth-sources';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LearningSettingsState settings = ref.watch(learningSettingsProvider);
    final bool biliOk = settings.isBilibiliLoggedIn;

    return PadScaffold(
      currentDestination: AppNavDestination.settings,
      showContinueLearning: false,
      topBar: const PadTopBar(
        title: '授权与素材来源',
        subtitle: 'B 站 · YouTube · 网盘',
      ),
      body: ListView(
        padding: EdgeInsets.all(context.padPagePadding),
        children: <Widget>[
          Text(
            '授权与素材来源',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '管好来源之后，学习页里的课、字幕和复习才会同步。授权随时可撤销。',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w600,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.asset(Assets.onboardingOral, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 16),
          _SourceCard(
            name: '哔哩哔哩',
            color: const Color(0xFFFB7299),
            state: biliOk
                ? (settings.bilibiliUserId.isEmpty
                    ? '已授权 · 可同步课程与字幕'
                    : '已授权 · UID ${settings.bilibiliUserId}')
                : '未授权 · 扫码登录后同步课程',
            actionLabel: biliOk ? '重新登录' : '去授权',
            onAction: () => showBilibiliLoginSheet(context, ref),
            secondaryLabel: biliOk ? '退出登录' : null,
            onSecondary: biliOk
                ? () => ref
                    .read(learningSettingsProvider.notifier)
                    .clearBilibiliLogin()
                : null,
          ),
          const SizedBox(height: 10),
          _SourceCard(
            name: 'YouTube',
            color: const Color(0xFFFF4E45),
            state: '导入时按需授权 · 登录后拉取视频',
            actionLabel: '去导入',
            onAction: () => showYoutubeImportSheet(context, ref),
          ),
          const SizedBox(height: 10),
          _SourceCard(
            name: '网盘',
            color: const Color(0xFF3B82F6),
            state: '未连接 · 授权后导入剧集与课件',
            actionLabel: '去连接',
            onAction: () => showNetdiskImportSheet(context, ref),
          ),
          const SizedBox(height: 18),
          Text(
            '打开相关功能时弹出的授权页是正常流程，不是广告。未授权仍可使用本地已有内容。',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppDesignTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.name,
    required this.color,
    required this.state,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String name;
  final Color color;
  final String state;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppDesignTokens.borderGray),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  state,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onAction,
            child: Text(
              actionLabel,
              style: TextStyle(
                color: AppDesignTokens.brandGreen,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (secondaryLabel != null && onSecondary != null)
            TextButton(
              onPressed: onSecondary,
              child: Text(
                secondaryLabel!,
                style: TextStyle(
                  color: AppDesignTokens.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
