import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../router/app_router.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../sync/data/acquire_api_client.dart';
import '../../../sync/presentation/cloud_catalog_sync.dart';
import '../../domain/register_response.dart';
import '../account_hub_sheet.dart';
import '../login/login_controller.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _codeController;
  late final TextEditingController _passwordController;
  late final TextEditingController _confirmController;
  bool _obscure = true;
  bool _submitting = false;
  bool _sendingCode = false;
  int _codeCooldown = 0;
  String? _debugCode;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _codeController = TextEditingController();
    _passwordController = TextEditingController();
    _confirmController = TextEditingController();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_sendingCode || _codeCooldown > 0) {
      return;
    }
    final String email = _emailController.text.trim();
    if (email.isEmpty) {
      _toast('请输入邮箱');
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _toast('邮箱格式不正确');
      return;
    }
    setState(() => _sendingCode = true);
    try {
      final AcquireSmsSendResult sent = await ref
          .read(loginControllerProvider.notifier)
          .sendEmailCode(email: email);
      if (!mounted) {
        return;
      }
      setState(() {
        _codeCooldown = sent.expiresIn.clamp(30, 120);
        _debugCode = sent.debugCode;
        if (sent.debugCode != null && _codeController.text.isEmpty) {
          _codeController.text = sent.debugCode!;
        }
      });
      _cooldownTimer?.cancel();
      _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (_codeCooldown <= 1) {
          t.cancel();
          setState(() => _codeCooldown = 0);
          return;
        }
        setState(() => _codeCooldown -= 1);
      });
      _toast(sent.mock ? '已发送（开发模式，验证码已自动填入）' : '验证码已发送到邮箱');
    } catch (error) {
      if (mounted) {
        _toast('$error'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _sendingCode = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false) || _submitting) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final RegisterResponse result = await ref
          .read(loginControllerProvider.notifier)
          .register(
            email: _emailController.text,
            password: _passwordController.text,
            code: _codeController.text,
            displayName: _nameController.text.trim().isEmpty
                ? null
                : _nameController.text.trim(),
          );
      if (!mounted) {
        return;
      }
      if (result.token.isNotEmpty) {
        await setSkipDefaultAccountLogin(skip: false);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('注册成功')));
        ref.invalidate(cloudCatalogSyncProvider);
        unawaited(syncCloudCatalogAndFeed(ref));
        context.go(SGRoute.vocabularyPlacement.route);
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

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppDesignTokens.textPrimary,
        title: const Text('注册'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: <Widget>[
            Text(
              '创建爱快英语账号',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '先获取邮箱验证码，再设置密码完成注册。',
              style: TextStyle(
                fontSize: 14,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _label('昵称（可选）'),
                  TextFormField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    style: TextStyle(color: AppDesignTokens.textPrimary),
                    decoration: _decoration('例如 Elon Musk'),
                  ),
                  const SizedBox(height: 14),
                  _label('邮箱'),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
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
                    decoration: _decoration('name@example.com'),
                  ),
                  const SizedBox(height: 14),
                  _label('邮箱验证码'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: TextFormField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          style: TextStyle(color: AppDesignTokens.textPrimary),
                          validator: (String? value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入验证码';
                            }
                            if (value.trim().length < 4) {
                              return '验证码格式不正确';
                            }
                            return null;
                          },
                          decoration: _decoration(
                            _debugCode == null ? '邮箱验证码' : '验证码（已填开发码）',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed:
                              (_sendingCode || _codeCooldown > 0) ? null : _sendCode,
                          child: Text(
                            _codeCooldown > 0
                                ? '${_codeCooldown}s'
                                : (_sendingCode ? '发送中' : '获取验证码'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _label('密码'),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.next,
                    style: TextStyle(color: AppDesignTokens.textPrimary),
                    validator: (String? value) {
                      if (value == null || value.isEmpty) {
                        return '请输入密码';
                      }
                      if (value.length < 6) {
                        return '密码至少 6 位';
                      }
                      return null;
                    },
                    decoration: _decoration('至少 6 位').copyWith(
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppDesignTokens.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _label('确认密码'),
                  TextFormField(
                    controller: _confirmController,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    style: TextStyle(color: AppDesignTokens.textPrimary),
                    validator: (String? value) {
                      if (value != _passwordController.text) {
                        return '两次密码不一致';
                      }
                      return null;
                    },
                    decoration: _decoration('再输入一次密码'),
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
                              '注册并登录',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () => context.go(SGRoute.login.route),
                      child: Text(
                        '已有账号？去登录',
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
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w800,
        color: AppDesignTokens.textPrimary,
      ),
    ),
  );

  InputDecoration _decoration(String hint) => InputDecoration(
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
