import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../shared/audio/success_sfx.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/user_assets_provider.dart';

/// Shows a claim dialog when the server says Pro welcome is still claimable.
class WelcomeProClaimHost extends ConsumerStatefulWidget {
  const WelcomeProClaimHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<WelcomeProClaimHost> createState() =>
      _WelcomeProClaimHostState();
}

class _WelcomeProClaimHostState extends ConsumerState<WelcomeProClaimHost> {
  static const String _dismissPrefix = 'welcomeProClaimDismissed:';

  bool _checking = false;
  bool _dialogOpen = false;
  bool _dismissedThisSession = false;

  String? get _dismissStorageKey {
    final String email =
        ref.read(authSessionProvider).email.trim().toLowerCase();
    if (email.isEmpty) {
      return null;
    }
    return '$_dismissPrefix$email';
  }

  bool _isDismissedPersisted() {
    final String? key = _dismissStorageKey;
    if (key == null || !Hive.isBoxOpen('prefs')) {
      return false;
    }
    return Hive.box<String>('prefs').get(key) == '1';
  }

  Future<void> _persistDismissed() async {
    final String? key = _dismissStorageKey;
    if (key == null || !Hive.isBoxOpen('prefs')) {
      return;
    }
    await Hive.box<String>('prefs').put(key, '1');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybePrompt());
    });
  }

  @override
  void didUpdateWidget(covariant WelcomeProClaimHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybePrompt());
    });
  }

  Future<void> _maybePrompt() async {
    if (!mounted || _checking || _dialogOpen) {
      return;
    }
    final AuthSessionState auth = ref.read(authSessionProvider);
    if (!auth.isLoggedIn ||
        _dismissedThisSession ||
        _isDismissedPersisted()) {
      return;
    }
    _checking = true;
    try {
      final Map<String, dynamic> status =
          await ref.read(acquireApiClientProvider).commerceTrialStatus();
      if (!mounted) {
        return;
      }
      final bool claimable = status['welcome_claimable'] == true;
      if (!claimable) {
        return;
      }
      await _showClaimDialog();
    } catch (_) {
      // Offline / unauthorized — skip quietly.
    } finally {
      _checking = false;
    }
  }

  Future<void> _showClaimDialog() async {
    if (!mounted || _dialogOpen) {
      return;
    }
    _dialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          bool busy = false;
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setLocal) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: const Text('领取 1 个月 Pro'),
                content: const Text(
                  '每位用户可免费领取一次 Pro 会员（约 30 天），开通后全功能可用。\n'
                  '领取后不可重复领取。',
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            _dismissedThisSession = true;
                            await _persistDismissed();
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          },
                    child: const Text('稍后再说'),
                  ),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            setLocal(() => busy = true);
                            try {
                              await ref
                                  .read(acquireApiClientProvider)
                                  .commerceClaimWelcomePro();
                              if (!context.mounted) {
                                return;
                              }
                              playSuccessSfx(SuccessSfxKind.fanfare);
                              ref.invalidate(userAssetsProvider);
                              _dismissedThisSession = true;
                              await _persistDismissed();
                              if (dialogContext.mounted) {
                                Navigator.of(dialogContext).pop();
                              }
                              if (mounted) {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  const SnackBar(
                                    content: Text('已领取 1 个月 Pro，全功能可用'),
                                    duration: Duration(seconds: 4),
                                  ),
                                );
                              }
                            } catch (error) {
                              if (!context.mounted) {
                                return;
                              }
                              setLocal(() => busy = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '$error'.replaceFirst('Exception: ', ''),
                                  ),
                                ),
                              );
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppDesignTokens.brandGreen,
                      foregroundColor: AppDesignTokens.onAccent,
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('立即领取'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
