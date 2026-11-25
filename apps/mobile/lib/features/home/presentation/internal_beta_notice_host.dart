import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';

/// Fixed internal-beta notice: shown every time the app is opened (cold start).
/// Cannot be permanently dismissed; only closed for the current session.
class InternalBetaNoticeHost extends StatefulWidget {
  const InternalBetaNoticeHost({required this.child, super.key});

  final Widget child;

  @override
  State<InternalBetaNoticeHost> createState() => _InternalBetaNoticeHostState();
}

class _InternalBetaNoticeHostState extends State<InternalBetaNoticeHost> {
  static const String authorWechat = 'youyoufairytale';

  bool _dialogOpen = false;
  bool _shownThisProcess = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showIfNeeded());
    });
  }

  Future<void> _showIfNeeded() async {
    if (!mounted || _dialogOpen || _shownThisProcess) {
      return;
    }
    final NavigatorState? nav = Navigator.maybeOf(context, rootNavigator: true);
    if (nav == null) {
      return;
    }
    _shownThisProcess = true;
    _dialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.72),
        builder: (BuildContext context) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              backgroundColor: AppDesignTokens.appWhite,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                '内测须知',
                style: TextStyle(
                  color: AppDesignTokens.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: DefaultTextStyle(
                    style: TextStyle(
                      color: AppDesignTokens.textSecondary,
                      fontSize: 14,
                      height: 1.55,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _Bullet(
                          index: '1',
                          child: Text.rich(
                            TextSpan(
                              children: <InlineSpan>[
                                const TextSpan(
                                  text: '内测用户请把注册 ID 通过微信发给作者，作者微信号：',
                                ),
                                TextSpan(
                                  text: authorWechat,
                                  style: TextStyle(
                                    color: AppDesignTokens.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const TextSpan(text: '。'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const _Bullet(
                          index: '2',
                          child: Text(
                            '内测用户可加入「佑佑爸粉丝交流群」。有 bug 相关问题，作者都会在群里第一时间解决。',
                          ),
                        ),
                        const SizedBox(height: 12),
                        const _Bullet(
                          index: '3',
                          child: Text(
                            '内测用户可提供学习资源（各年级真题试卷、影视资源、电子书、各类教材等），'
                            '直接在 App 社区上传；审核通过后可额外赠送 Pro 会员时长。',
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Bullet(
                          index: '4',
                          child: Text(
                            '各类英语交流资料不得含有敏感内容。一经发现与国家政策法规不符，立刻永久封号处理。',
                            style: TextStyle(
                              color: AppDesignTokens.dangerText,
                              fontWeight: FontWeight.w700,
                              height: 1.55,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Material(
                          color: AppDesignTokens.softGray,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              await Clipboard.setData(
                                const ClipboardData(text: authorWechat),
                              );
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('已复制微信号 youyoufairytale'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                children: <Widget>[
                                  Icon(
                                    Icons.chat_bubble_outline,
                                    size: 18,
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '微信号：$authorWechat（点此复制）',
                                      style: TextStyle(
                                        color: AppDesignTokens.textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.copy,
                                    size: 16,
                                    color: AppDesignTokens.textSecondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: <Widget>[
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('我知道了'),
                ),
              ],
            ),
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

class _Bullet extends StatelessWidget {
  const _Bullet({required this.index, required this.child});

  final String index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppDesignTokens.brandGreen.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            index,
            style: TextStyle(
              color: AppDesignTokens.brandGreen,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    );
  }
}
