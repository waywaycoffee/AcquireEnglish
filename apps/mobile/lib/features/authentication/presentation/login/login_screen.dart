import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../constants/assets.dart';
import '../../../../router/app_router.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
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
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
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

  void _openWechat() => context.push(SGRoute.loginWechat.route);

  void _openPhone() => context.push(SGRoute.loginPhone.route);

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
    // True only when App was built without WECHAT_APP_ID dart-define.
    final bool wechatMock = !WechatAuthHelper.isConfigured;

    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          children: <Widget>[
            const SizedBox(height: 8),
            Center(
              child: Image.asset(
                Assets.logoLockup,
                height: 96,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '欢迎来到爱快英语',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '用真实视频练听力与跟读。微信一键登录，未注册也会自动开号。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _submitting ? null : _openWechat,
                borderRadius: BorderRadius.circular(24),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Color(0xFF07C160),
                        Color(0xFF06AD56),
                      ],
                    ),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x4006AD56),
                        blurRadius: 18,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.chat_bubble_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                wechatMock ? '微信登录 / 注册（模拟）' : '微信一键登录 / 注册',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                wechatMock
                                    ? '开发环境：进入授权模拟页完成登录'
                                    : '跳转微信授权，新用户自动创建账号',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 13,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(child: Divider(color: AppDesignTokens.borderGray)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    '其他方式',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: AppDesignTokens.borderGray)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: _SecondaryMethod(
                    icon: Icons.sms_rounded,
                    label: '手机号',
                    color: AppDesignTokens.primaryBlueDark,
                    onTap: _submitting ? null : _openPhone,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SecondaryMethod(
                    icon: Icons.mail_outline_rounded,
                    label: '邮箱',
                    color: AppDesignTokens.brandGreenDark,
                    onTap: _submitting
                        ? null
                        : () => setState(
                              () => _showEmailForm = !_showEmailForm,
                            ),
                  ),
                ),
              ],
            ),
            if (_showEmailForm) ...<Widget>[
              const SizedBox(height: 16),
              _buildEmailForm(showPassword),
            ],
            const SizedBox(height: 22),
            Center(
              child: TextButton(
                onPressed: () => context.push(SGRoute.register.route),
                child: Text(
                  '邮箱注册新账号',
                  style: TextStyle(
                    color: AppDesignTokens.primaryBlueDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '登录即表示你了解我们将使用公开资料创建学习账号，并同步进度。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: AppDesignTokens.textSecondary,
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
          boxShadow: AppDesignTokens.toyCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '邮箱登录',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const <String>[AutofillHints.email],
              style: TextStyle(color: AppDesignTokens.textPrimary),
              validator: (String? value) {
                final String text = value?.trim() ?? '';
                if (text.isEmpty) return '请输入邮箱';
                if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
                  return '邮箱格式不正确';
                }
                return null;
              },
              decoration: _fieldDecoration('name@example.com'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: !showPassword,
              textInputAction: TextInputAction.done,
              autofillHints: const <String>[AutofillHints.password],
              style: TextStyle(color: AppDesignTokens.textPrimary),
              onFieldSubmitted: (_) => _submitEmail(),
              validator: (String? value) {
                if (value == null || value.isEmpty) return '请输入密码';
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
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _submitting ? null : _submitEmail,
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignTokens.brandGreen,
                  foregroundColor: AppDesignTokens.onAccent,
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
                        '登录',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
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

class _SecondaryMethod extends StatelessWidget {
  const _SecondaryMethod({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppDesignTokens.borderGray),
          ),
          child: Column(
            children: <Widget>[
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
