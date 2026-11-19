import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../router/app_router.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../sync/data/acquire_api_client.dart';
import '../../domain/login_response.dart';
import '../legal/registration_agreement_checkbox.dart';
import 'login_controller.dart';
import 'login_flow_helpers.dart';

/// Dedicated phone + SMS login page (works with live Aliyun or AUTH_SMS_MOCK).
class PhoneLoginScreen extends ConsumerStatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  ConsumerState<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends ConsumerState<PhoneLoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _phoneController;
  late final TextEditingController _smsCodeController;
  bool _submitting = false;
  bool _sendingSms = false;
  bool _agreedToTerms = false;
  String? _agreementError;
  int _smsCooldown = 0;
  Timer? _cooldownTimer;
  String? _debugSmsCode;
  bool? _mockMode;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
    _smsCodeController = TextEditingController();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _phoneController.dispose();
    _smsCodeController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendSms() async {
    if (_sendingSms || _smsCooldown > 0) {
      return;
    }
    final String phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _toast('请输入手机号');
      return;
    }
    setState(() => _sendingSms = true);
    try {
      final AcquireSmsSendResult sent = await ref
          .read(loginControllerProvider.notifier)
          .sendSmsCode(phone: phone);
      if (!mounted) {
        return;
      }
      setState(() {
        _mockMode = sent.mock;
        _smsCooldown = sent.expiresIn.clamp(30, 120);
        _debugSmsCode = sent.debugCode;
        if (sent.debugCode != null && _smsCodeController.text.isEmpty) {
          _smsCodeController.text = sent.debugCode!;
        }
      });
      _cooldownTimer?.cancel();
      _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (_smsCooldown <= 1) {
          t.cancel();
          setState(() => _smsCooldown = 0);
          return;
        }
        setState(() => _smsCooldown -= 1);
      });
      _toast(
        sent.mock
            ? '模拟短信已发送，验证码已自动填入'
            : '验证码已发送到手机',
      );
    } catch (error) {
      if (mounted) {
        _toast('$error'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _sendingSms = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false) || _submitting) {
      return;
    }
    if (!_agreedToTerms) {
      setState(() => _agreementError = '请先阅读并同意用户协议与版权声明');
      _toast('请先勾选同意用户协议与版权声明');
      return;
    }
    setState(() {
      _agreementError = null;
      _submitting = true;
    });
    try {
      final LoginResponse result = await ref
          .read(loginControllerProvider.notifier)
          .loginWithSms(
            phone: _phoneController.text,
            code: _smsCodeController.text,
          );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppDesignTokens.textPrimary,
        title: const Text('手机号登录'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppDesignTokens.appWhite,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppDesignTokens.borderGray),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppDesignTokens.skyLight,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.sms_rounded,
                      color: AppDesignTokens.primaryBlueDark,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '短信验证码登录',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '未注册手机号将自动创建账号并领取试用权益。',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_mockMode == true) ...<Widget>[
              const SizedBox(height: 14),
              _MockBanner(
                text: _debugSmsCode == null
                    ? '当前为短信模拟模式（AUTH_SMS_MOCK），不会真实下发短信。'
                    : '模拟模式：验证码 $_debugSmsCode 已自动填入，可直接登录。',
              ),
            ],
            const SizedBox(height: 22),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _label('手机号'),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    style: TextStyle(color: AppDesignTokens.textPrimary),
                    validator: (String? value) {
                      final String text = value?.trim() ?? '';
                      if (text.isEmpty) {
                        return '请输入手机号';
                      }
                      final String digits = text.replaceAll(RegExp(r'\D'), '');
                      if (digits.length < 8) {
                        return '手机号格式不正确';
                      }
                      return null;
                    },
                    decoration: _decoration('11 位手机号'),
                  ),
                  const SizedBox(height: 16),
                  _label('验证码'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: TextFormField(
                          controller: _smsCodeController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          style: TextStyle(color: AppDesignTokens.textPrimary),
                          validator: (String? value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入验证码';
                            }
                            return null;
                          },
                          decoration: _decoration(
                            _debugSmsCode == null ? '短信验证码' : '验证码（已填开发码）',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed:
                              (_sendingSms || _smsCooldown > 0) ? null : _sendSms,
                          child: Text(
                            _smsCooldown > 0
                                ? '${_smsCooldown}s'
                                : (_sendingSms ? '发送中' : '获取验证码'),
                          ),
                        ),
                      ),
                    ],
                  ),
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
                  const SizedBox(height: 20),
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
                              '登录 / 自动注册',
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
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () => context.push(SGRoute.loginWechat.route),
                child: Text(
                  '改用微信登录',
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

class _MockBanner extends StatelessWidget {
  const _MockBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6DB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD666)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.science_outlined, color: Color(0xFFB78103)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF7A5A00),
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
