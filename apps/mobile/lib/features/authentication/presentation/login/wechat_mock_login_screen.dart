import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../constants/assets.dart';
import '../../../../router/app_router.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../data/wechat_auth_helper.dart';
import '../../domain/login_response.dart';
import '../legal/registration_agreement_checkbox.dart';
import 'login_controller.dart';
import 'login_flow_helpers.dart';

/// Full-screen mock of WeChat OAuth consent (used when WECHAT_APP_ID is unset).
class WechatMockLoginScreen extends ConsumerStatefulWidget {
  const WechatMockLoginScreen({super.key});

  @override
  ConsumerState<WechatMockLoginScreen> createState() =>
      _WechatMockLoginScreenState();
}

class _WechatMockLoginScreenState extends ConsumerState<WechatMockLoginScreen> {
  late final TextEditingController _codeController;
  bool _loadingCode = true;
  bool _submitting = false;
  bool _advanced = false;
  bool _agreedToTerms = false;
  String? _agreementError;

  static const Color _wechatGreen = Color(0xFF07C160);

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (WechatAuthHelper.isConfigured) {
      // Real SDK path: skip mock UI.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _submitRealWechat();
        }
      });
      return;
    }
    final String code = await loadOrCreateWechatMockCode();
    if (!mounted) {
      return;
    }
    setState(() {
      _codeController.text = code;
      _loadingCode = false;
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submitRealWechat() async {
    if (_submitting) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final String code = await WechatAuthHelper.requestAuthCode();
      final LoginResponse result = await ref
          .read(loginControllerProvider.notifier)
          .loginWithWechat(code: code);
      await completeLoginAndGoHome(
        ref,
        context,
        result,
        isNew: result.isNewUser,
      );
    } catch (error) {
      if (mounted) {
        _toast('$error'.replaceFirst('Exception: ', ''));
        setState(() {
          _submitting = false;
          _loadingCode = false;
        });
      }
    }
  }

  Future<void> _agreeMock() async {
    if (_submitting) {
      return;
    }
    if (!_agreedToTerms) {
      setState(() => _agreementError = '请先阅读并同意用户协议与版权声明');
      _toast('请先勾选同意用户协议与版权声明');
      return;
    }
    final String code = _codeController.text.trim();
    if (code.isEmpty) {
      _toast('请填写模拟授权码');
      return;
    }
    setState(() => _submitting = true);
    try {
      await saveWechatMockCode(code);
      final LoginResponse result = await ref
          .read(loginControllerProvider.notifier)
          .loginWithWechat(code: code);
      await completeLoginAndGoHome(
        ref,
        context,
        result,
        isNew: result.isNewUser,
      );
    } catch (error) {
      if (mounted) {
        _toast('$error'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _resetIdentity() async {
    final String fresh =
        'mock_device_${DateTime.now().millisecondsSinceEpoch}';
    _codeController.text = fresh;
    await saveWechatMockCode(fresh);
    setState(() {});
    _toast('已生成新的模拟微信身份');
  }

  @override
  Widget build(BuildContext context) {
    if (WechatAuthHelper.isConfigured && _loadingCode) {
      return Scaffold(
        backgroundColor: AppDesignTokens.softWhite,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      body: SafeArea(
        child: _loadingCode
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: Row(
                      children: <Widget>[
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          style: IconButton.styleFrom(
                            backgroundColor: AppDesignTokens.appWhite,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const Expanded(
                          child: Text(
                            '微信授权登录',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!WechatAuthHelper.isConfigured)
                          TextButton(
                            onPressed: () =>
                                setState(() => _advanced = !_advanced),
                            child: Text(
                              _advanced ? '收起' : '开发',
                              style: const TextStyle(
                                color: Color(0xFF576B95),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        else
                          const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      children: <Widget>[
                        if (!WechatAuthHelper.isConfigured)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF8E8),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFFFE0A3),
                              ),
                            ),
                            child: const Text(
                              '开发模拟：未配置 WECHAT_APP_ID 时不会跳转微信。'
                              '同意后用模拟身份完成登录/自动注册。',
                              style: TextStyle(
                                color: Color(0xFF8A5A00),
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (!WechatAuthHelper.isConfigured)
                          const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
                          decoration: BoxDecoration(
                            color: AppDesignTokens.appWhite,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: AppDesignTokens.toyCardShadow,
                          ),
                          child: Column(
                            children: <Widget>[
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: _wechatGreen.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                padding: const EdgeInsets.all(10),
                                child: Image.asset(
                                  Assets.logoLockup,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                '爱快英语 申请使用',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF111111),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '获取微信公开资料用于登录注册，并同步学习进度',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: AppDesignTokens.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 22),
                              const _PermissionRow(
                                icon: Icons.person_outline_rounded,
                                text: '获取你的公开信息（昵称、头像）',
                              ),
                              const SizedBox(height: 10),
                              const _PermissionRow(
                                icon: Icons.verified_user_outlined,
                                text: '创建学习账号并跨设备同步进度',
                              ),
                              const SizedBox(height: 10),
                              const _PermissionRow(
                                icon: Icons.workspace_premium_outlined,
                                text: '新用户自动发放试用会员与陪练额度',
                              ),
                              if (_advanced) ...<Widget>[
                                const SizedBox(height: 20),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '模拟授权码（同一码 = 同一微信账号）',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppDesignTokens.textSecondary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _codeController,
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: AppDesignTokens.softGray,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    suffixIcon: IconButton(
                                      tooltip: '复制',
                                      onPressed: () async {
                                        await Clipboard.setData(
                                          ClipboardData(
                                            text: _codeController.text,
                                          ),
                                        );
                                        _toast('已复制模拟授权码');
                                      },
                                      icon: const Icon(
                                        Icons.copy_rounded,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed:
                                        _submitting ? null : _resetIdentity,
                                    child: const Text('换一个新身份'),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              RegistrationAgreementCheckbox(
                                value: _agreedToTerms,
                                errorText: _agreementError,
                                onChanged: (bool? next) {
                                  setState(() {
                                    _agreedToTerms = next ?? false;
                                    if (_agreedToTerms) {
                                      _agreementError = null;
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: FilledButton(
                                  onPressed: _submitting ? null : _agreeMock,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _wechatGreen,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: _submitting
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          '同意并继续',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: OutlinedButton(
                                  onPressed: _submitting
                                      ? null
                                      : () =>
                                          Navigator.of(context).maybePop(),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor:
                                        AppDesignTokens.textSecondary,
                                    side: BorderSide(
                                      color: AppDesignTokens.borderGray,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: const Text(
                                    '拒绝',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            onPressed: () =>
                                context.push(SGRoute.loginPhone.route),
                            child: Text(
                              '改用手机号登录',
                              style: TextStyle(
                                color: AppDesignTokens.primaryBlueDark,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: const Color(0xFF07C160)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF333333),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
