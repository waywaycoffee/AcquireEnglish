import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';

import '../../../router/app_router.dart';
import '../../membership/presentation/pro_member_badge.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../settings/presentation/learning_preferences_screen.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../words/presentation/vocabulary_placement_provider.dart';
import '../../sync/presentation/cloud_catalog_sync.dart';
import '../data/authentication_repository.dart';
import '../data/default_account.dart';
import 'auth_session.dart';

/// Pref key: after explicit logout, do not silently re-login the default account.
const String kSkipDefaultAccountLoginKey = 'authSkipDefaultAccountLogin';

bool shouldSkipDefaultAccountLogin() {
  if (!Hive.isBoxOpen('prefs')) {
    return false;
  }
  return Hive.box<String>('prefs').get(kSkipDefaultAccountLoginKey) == '1';
}

Future<void> setSkipDefaultAccountLogin({required bool skip}) async {
  if (!Hive.isBoxOpen('prefs')) {
    return;
  }
  final Box<String> box = Hive.box<String>('prefs');
  if (skip) {
    await box.put(kSkipDefaultAccountLoginKey, '1');
  } else {
    await box.delete(kSkipDefaultAccountLoginKey);
  }
}

Future<void> showAccountHubSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppDesignTokens.appWhite,
    builder: (BuildContext sheetContext) => const _AccountHubSheet(),
  );
}

class _AccountHubSheet extends ConsumerStatefulWidget {
  const _AccountHubSheet();

  @override
  ConsumerState<_AccountHubSheet> createState() => _AccountHubSheetState();
}

class _AccountHubSheetState extends ConsumerState<_AccountHubSheet> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshProfile());
    });
  }

  Future<void> _refreshProfile() async {
    final AuthSessionState auth = ref.read(authSessionProvider);
    if (!auth.isLoggedIn) return;
    try {
      final AcquireUser me =
          await ref.read(acquireApiClientProvider).fetchMe();
      await ref.read(authSessionProvider.notifier).updateProfile(
            displayName: me.displayName ?? auth.displayName,
            memberNo: me.memberNo,
          );
    } catch (_) {}
  }

  Future<void> _toast(String message) async {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loginDefault() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await setSkipDefaultAccountLogin(skip: false);
      await ref
          .read(authenticationRepositoryProvider)
          .login(DefaultAccount.email, DefaultAccount.password);
      await ref
          .read(authSessionProvider.notifier)
          .signIn(
            accessToken: ref.read(authSessionProvider).accessToken,
            email: DefaultAccount.email,
            displayName: DefaultAccount.displayName,
          );
      ref.invalidate(cloudCatalogSyncProvider);
      unawaited(syncCloudCatalogAndFeed(ref));
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      await _toast('已登录 ${DefaultAccount.displayName}');
    } catch (error) {
      await _toast('$error'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _signOut() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await setSkipDefaultAccountLogin(skip: true);
      await ref.read(authSessionProvider.notifier).signOut();
      if (!mounted) {
        return;
      }
      await _toast('已退出登录');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _syncAssets() async {
    if (_busy) {
      return;
    }
    final AuthSessionState auth = ref.read(authSessionProvider);
    if (!auth.isLoggedIn) {
      await _toast('请先登录账号');
      return;
    }
    setState(() => _busy = true);
    try {
      ref.invalidate(cloudCatalogSyncProvider);
      await syncCloudCatalogAndFeed(ref);
      await _toast('已开始同步云端视频与字幕');
    } catch (error) {
      await _toast('同步失败：$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthSessionState auth = ref.watch(authSessionProvider);
    final int? vocabulary = ref.watch(predictedVocabularyProvider);
    final bool loggedIn = auth.isLoggedIn;
    final String title = loggedIn
        ? (auth.displayName.trim().isEmpty ? auth.email : auth.displayName)
        : '未登录';
    final String subtitle = loggedIn ? auth.email : '登录后可同步进度、词库与个人字幕资产';

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              '爱快账号',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppDesignTokens.skyLight.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppDesignTokens.brandGreen,
                    child: Text(
                      loggedIn && title.isNotEmpty
                          ? title.substring(0, 1).toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (loggedIn) ...<Widget>[
                              const SizedBox(width: 8),
                              const ProMemberBadgeIfActive(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: AppDesignTokens.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (loggedIn &&
                            auth.memberNo.trim().isNotEmpty) ...<Widget>[
                          const SizedBox(height: 6),
                          Text(
                            '注册序号 ${auth.memberNo.trim()}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppDesignTokens.textSecondary,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(vocabulary == null ? '测词汇量' : '重新测词汇量'),
              subtitle: vocabulary == null ? null : Text('目前约 $vocabulary 个词形'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy
                  ? null
                  : () {
                      final GoRouter router = GoRouter.of(context);
                      Navigator.of(context).pop();
                      router.push(SGRoute.vocabularyPlacement.route);
                    },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune_rounded),
              title: const Text('修改学习偏好'),
              subtitle: const Text('英语水平、兴趣和每日推荐数量'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy
                  ? null
                  : () {
                      final NavigatorState navigator = Navigator.of(context);
                      navigator.pop();
                      navigator.push(
                        MaterialPageRoute<void>(
                          builder: (_) => const LearningPreferencesScreen(),
                        ),
                      );
                    },
            ),
            const SizedBox(height: 12),
            if (!loggedIn) ...<Widget>[
              FilledButton(
                onPressed: _busy
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        context.push(SGRoute.login.route);
                      },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: AppDesignTokens.brandGreenDark,
                ),
                child: const Text(
                  '登录账号',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        context.push(SGRoute.register.route);
                      },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text(
                  '注册新账号',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 10),
              if (DefaultAccount.email.isNotEmpty &&
                  DefaultAccount.password.isNotEmpty)
                TextButton(
                  onPressed: _busy ? null : _loginDefault,
                  child: Text(
                    _busy ? '正在登录…' : '使用默认账号 weiwei 登录',
                    style: TextStyle(
                      color: AppDesignTokens.brandGreenDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ] else ...<Widget>[
              FilledButton.icon(
                onPressed: _busy ? null : _syncAssets,
                icon: const Icon(Icons.cloud_sync_rounded),
                label: Text(_busy ? '同步中…' : '同步云端资产到本机'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: AppDesignTokens.brandGreenDark,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        context.push(SGRoute.login.route);
                      },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text(
                  '切换账号 / 重新登录',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _busy ? null : _signOut,
                child: Text(
                  '退出登录',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.go(SGRoute.settings.route);
              },
              child: Text(
                '打开设置里的账号与同步',
                style: TextStyle(color: AppDesignTokens.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
