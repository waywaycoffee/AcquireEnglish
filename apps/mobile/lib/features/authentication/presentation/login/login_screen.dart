import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../constants/assets.dart';
import '../../../../router/app_router.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../data/default_account.dart';
import '../../data/wechat_auth_helper.dart';
import '../../domain/login_response.dart';
import 'auth_ui_model.dart';
import 'login_controller.dart';
import 'login_flow_helpers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _emailFormKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  bool _submitting = false;
  bool _showEmailForm = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: DefaultAccount.email);
    _passwordController = TextEditingController(text: DefaultAccount.password);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submitEmail() async {
    if (!(_emailFormKey.currentState?.validate() ?? false) || _submitting) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final LoginResponse result = await ref
          .read(loginControllerProvider.notifier)
          .login(
            email: _emailController.text,
            password: _passwordController.text,
          );
      await completeLoginAndGoHome(ref, context, result, isNew: false);
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

  void _openWechat() {
    context.push(SGRoute.loginWechat.route);
  }

  void _openPhone() {
    context.push(SGRoute.loginPhone.route);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AuthUiModel> authAsync = ref.watch(loginControllerProvider);
    ref.listen(loginControllerProvider, (
      AsyncValue<AuthUiModel>? previous,
      AsyncValue<AuthUiModel> next,
    ) {
      final String? email = next.value?.user?.email;
      if (email != null &&
          email.isNotEmpty &&
          _emailController.text.isEmpty &&
          email.contains('@')) {
        _emailController.text = email;
      }
    });

    final bool showPassword = authAsync.value?.showPassword ?? false;
    final bool wechatMock = !WechatAuthHelper.isConfigured;

    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppDesignTokens.textPrimary,
        title: const Text('登录'),
        actions: <Widget>[
          TextButton(
            onPressed: () => context.push(SGRoute.register.route),
            child: Text(
              '邮箱注册',
              style: TextStyle(
                color: AppDesignTokens.brandGreenDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: <Widget>[
            const SizedBox(height: 8),
            Center(
              child: Image.asset(
                Assets.logoLockup,
                height: 120,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '选择登录方式',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '微信 / 手机号未注册将自动创建账号；邮箱可用于已有账号登录。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppDesignTokens.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            _MethodCard(
              color: const Color(0xFF07C160),
              icon: Icons.chat_bubble_rounded,
              title: wechatMock ? '微信登录（模拟）' : '微信登录',
              subtitle: wechatMock
                  ? '未配置 AppID，进入授权模拟页完成登录'
                  : '跳转微信 App 授权后自动登录',
              onTap: _submitting ? null : _openWechat,
            ),
            const SizedBox(height: 12),
            _MethodCard(
              color: AppDesignTokens.primaryBlueDark,
              icon: Icons.sms_rounded,
              title: '手机号登录',
              subtitle: '短信验证码登录；模拟模式下验证码自动填入',
              onTap: _submitting ? null : _openPhone,
            ),
            const SizedBox(height: 12),
            _MethodCard(
              color: AppDesignTokens.brandGreenDark,
              icon: Icons.mail_outline_rounded,
              title: '邮箱登录',
              subtitle: '使用邮箱与密码登录已有账号',
              onTap: _submitting
                  ? null
                  : () => setState(() => _showEmailForm = !_showEmailForm),
              trailing: Icon(
                _showEmailForm
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: Colors.white,
              ),
            ),
            if (_showEmailForm) ...<Widget>[
              const SizedBox(height: 16),
              _buildEmailForm(showPassword),
            ],
            const SizedBox(height: 20),
            Center(
              child: TextButton(
                onPressed: () => context.go(SGRoute.home.route),
                child: Text(
                  '先逛逛，稍后再登录',
                  style: TextStyle(color: AppDesignTokens.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailForm(bool showPassword) {
    return Form(
      key: _emailFormKey,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppDesignTokens.appWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppDesignTokens.borderGray),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '邮箱',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const <String>[AutofillHints.email],
              style: TextStyle(color: AppDesignTokens.textPrimary),
              validator: (String? value) {
                final String text = value?.trim() ?? '';
                if (text.isEmpty) {
                  return '请输入邮箱';
                }
                if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
                  return '邮箱格式不正确';
                }
                return null;
              },
              decoration: _fieldDecoration('name@example.com'),
            ),
            const SizedBox(height: 16),
            Text(
              '密码',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _passwordController,
              obscureText: !showPassword,
              textInputAction: TextInputAction.done,
              autofillHints: const <String>[AutofillHints.password],
              style: TextStyle(color: AppDesignTokens.textPrimary),
              onFieldSubmitted: (_) => _submitEmail(),
              validator: (String? value) {
                if (value == null || value.isEmpty) {
                  return '请输入密码';
                }
                return null;
              },
              decoration: _fieldDecoration('请输入密码').copyWith(
                suffixIcon: IconButton(
                  onPressed: () {
                    ref
                        .read(loginControllerProvider.notifier)
                        .updateShowPassword(showPassword: !showPassword);
                  },
                  icon: Icon(
                    showPassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _submitting ? null : _submitEmail,
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignTokens.brandGreen,
                  foregroundColor: AppDesignTokens.onAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
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
                        '登录',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => context.push(SGRoute.register.route),
                child: Text(
                  '还没有账号？邮箱注册',
                  style: TextStyle(
                    color: AppDesignTokens.primaryBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppDesignTokens.textSecondary),
    filled: true,
    fillColor: AppDesignTokens.isDark
        ? AppDesignTokens.softGray
        : Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: AppDesignTokens.borderGray),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: AppDesignTokens.borderGray),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(
        color: AppDesignTokens.brandGreen,
        width: 1.4,
      ),
    ),
  );
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 14),
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
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              trailing ??
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
