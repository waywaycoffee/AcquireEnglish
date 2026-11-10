import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../constants/assets.dart';
import '../../../../router/app_router.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../domain/login_response.dart';
import 'auth_ui_model.dart';
import 'login_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  bool _submitting = false;

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

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false) || _submitting) {
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
      if (!mounted) {
        return;
      }
      if (result.token.isNotEmpty) {
        context.go(SGRoute.home.route);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
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
          _emailController.text.isEmpty) {
        _emailController.text = email;
      }
    });

    final bool showPassword = authAsync.value?.showPassword ?? false;

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
              '注册',
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
            const SizedBox(height: 18),
            Center(
              child: Image.asset(
                Assets.logoLockup,
                height: 148,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '登录后可同步学习进度、词库与偏好',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            Form(
              key: _formKey,
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
                      if (!RegExp(
                        r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                      ).hasMatch(text)) {
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
                    onFieldSubmitted: (_) => _submit(),
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
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
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
                  const SizedBox(height: 14),
                  Center(
                    child: TextButton(
                      onPressed: () => context.push(SGRoute.register.route),
                      child: Text(
                        '还没有账号？去注册',
                        style: TextStyle(
                          color: AppDesignTokens.primaryBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () => context.go(SGRoute.home.route),
                      child: Text(
                        '先逛逛，稍后再登录',
                        style: TextStyle(
                          color: AppDesignTokens.textSecondary,
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
