import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../constants/assets.dart';
import '../../../data/repository/network_repository.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../import_course/presentation/netdisk_import_sheet.dart';
import '../../import_course/presentation/youtube_import_sheet.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../settings/presentation/bilibili_login_sheet.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_compact.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';

/// Settings hub for Bilibili / YouTube / netdisk authorization.
class AuthSourcesSettingsScreen extends ConsumerStatefulWidget {
  const AuthSourcesSettingsScreen({super.key});

  static const String route = '/settings/auth-sources';

  @override
  ConsumerState<AuthSourcesSettingsScreen> createState() =>
      _AuthSourcesSettingsScreenState();
}

class _AuthSourcesSettingsScreenState
    extends ConsumerState<AuthSourcesSettingsScreen> {
  late final AppLifecycleListener _lifecycle;
  bool _available = false;
  bool _verified = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refreshBilibili);
    _refreshBilibili();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Dio _client() {
    final Dio network = ref.read(networkRepositoryProvider);
    return Dio(
      BaseOptions(
        baseUrl: network.options.baseUrl,
        headers: Map<String, dynamic>.of(network.options.headers),
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
      ),
    );
  }

  Future<void> _refreshBilibili() async {
    if (!ref.read(authSessionProvider).isLoggedIn) return;
    final Dio client = _client();
    try {
      final Response<Map<String, dynamic>> response = await client
          .get<Map<String, dynamic>>('api/bilibili/oauth/status');
      if (!mounted) return;
      setState(() {
        _available = response.data?['available'] == true;
        _verified = response.data?['verified'] == true;
      });
    } on DioException {
      // The existing login remains available if the OAuth API is unreachable.
    } finally {
      client.close();
    }
  }

  Future<void> _connectBilibili() async {
    if (_busy) return;
    setState(() => _busy = true);
    final Dio client = _client();
    try {
      if (!ref.read(authSessionProvider).isLoggedIn) {
        _showBilibiliMessage('请先登录爱快英语账号。');
        return;
      }
      final Response<Map<String, dynamic>> response = await client
          .post<Map<String, dynamic>>('api/bilibili/oauth/start');
      final Uri? url = Uri.tryParse(response.data?['url'] as String? ?? '');
      if (!mounted) return;
      if (url == null ||
          url.scheme != 'https' ||
          url.authority != 'account.bilibili.com' ||
          url.path != '/h5/account-h5/auth/oauth') {
        throw const FormatException('Unexpected Bilibili authorization URL');
      }
      bool opened = false;
      try {
        opened = await launchUrl(
          url,
          mode: LaunchMode.externalNonBrowserApplication,
        );
      } on Exception {
        // Browser fallback for devices without an app handler.
      }
      if (!opened && mounted) {
        opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      }
      if (!opened) _showBilibiliMessage('无法打开授权页，请稍后重试。');
    } on DioException catch (error) {
      final int? status = error.response?.statusCode;
      _showBilibiliMessage(
        status == 503 || status == 404
            ? 'B 站官方授权暂未开通。需要登录态时可选「跨设备扫码」。'
            : '无法发起 B 站授权，请检查网络后重试。',
      );
    } on Exception {
      _showBilibiliMessage('无法打开授权页，请稍后重试。');
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showBilibiliMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final bool biliOk = ref.watch(learningSettingsProvider).isBilibiliLoggedIn;

    return PadScaffold(
      currentDestination: AppNavDestination.settings,
      showContinueLearning: false,
      topBar: const PadTopBar(title: '授权与素材来源', subtitle: 'B 站 · YouTube · 网盘'),
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
            '按需连接素材来源。公开视频和已有字幕可直接使用。',
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
            state: <String>[
              if (biliOk) '扫码/Cookie 登录已就绪',
              if (_verified) '官方账号授权已验证',
              if (!biliOk && !_verified) '暂保留扫码授权；公开视频也可先导入',
            ].join(' · '),
            // Keep QR login as the primary path for now.
            actionLabel: biliOk ? '重新扫码' : '扫码授权',
            onAction: () => showBilibiliLoginSheet(context, ref),
            secondaryLabel: _busy ? '正在打开…' : '官方授权页',
            onSecondary: _connectBilibili,
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
            'B 站扫码授权暂时保留：用手机哔哩哔哩 App 扫码即可拉取官方字幕与受限视频；官方 OAuth 页作为备选。',
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
              style: const TextStyle(
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
