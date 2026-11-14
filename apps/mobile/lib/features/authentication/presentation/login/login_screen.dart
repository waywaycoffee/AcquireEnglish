import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../constants/assets.dart';
import '../../../../router/app_router.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../sync/data/acquire_api_client.dart';
import '../../data/wechat_auth_helper.dart';
import '../../domain/login_response.dart';
import 'auth_ui_model.dart';
import 'login_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey<FormState> _emailFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _phoneFormKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late final TextEditingController _phoneController;
  late final TextEditingController _smsCodeController;
  late final TabController _tabController;
  bool _submitting = false;
  bool _sendingSms = false;
  int _smsCooldown = 0;
  Timer? _cooldownTimer;
  String? _debugSmsCode;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _phoneController = TextEditingController();
    _smsCodeController = TextEditingController();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _smsCodeController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _goHomeAfterLogin(LoginResponse result, {bool isNew = false}) async {
    if (!mounted) {
      return;
    }
    if (result.token.isEmpty) {
      return;
    }
    if (isNew) {
      _toast('已自动注册并登录');
    }
    context.go(SGRoute.home.route);
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
      await _goHomeAfterLogin(result);
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
            ? '验证码已发送（开发模式：${sent.debugCode ?? "见服务端"}）'
            : '验证码已发送',
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

  Future<void> _submitPhone() async {
    if (!(_phoneFormKey.currentState?.validate() ?? false) || _submitting) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final LoginResponse result = await ref
          .read(loginControllerProvider.notifier)
          .loginWithSms(
            phone: _phoneController.text,
            code: _smsCodeController.text,
          );
      await _goHomeAfterLogin(result, isNew: result.isNewUser);
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

  Future<void> _submitWechat() async {
    if (_submitting) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final String code;
      if (WechatAuthHelper.isConfigured) {
        code = await WechatAuthHelper.requestAuthCode();
      } else {
        final String? mock = await showDialog<String>(
          context: context,
          builder: (BuildContext context) {
            final TextEditingController controller = TextEditingController(
              text: 'mock_device_${DateTime.now().millisecondsSinceEpoch}',
            );
            return AlertDialog(
              title: const Text('微信登录'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '未配置 WECHAT_APP_ID 时使用开发模式：服务端将自动注册/登录。'
                    '正式包请用 --dart-define=WECHAT_APP_ID=… 接入 fluwx。',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: '授权码 / 设备标识',
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, controller.text),
                  child: const Text('继续'),
                ),
              ],
            );
          },
        );
        if (mock == null || mock.trim().isEmpty) {
          return;
        }
        code = mock.trim();
      }
      final LoginResponse result = await ref
          .read(loginControllerProvider.notifier)
          .loginWithWechat(code: code);
      await _goHomeAfterLogin(result, isNew: result.isNewUser);
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
            const SizedBox(height: 12),
            Center(
              child: Image.asset(
                Assets.logoLockup,
                height: 132,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '手机号 / 微信一键登录，未注册将自动创建账号',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submitWechat,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF07C160),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.chat_bubble_rounded),
                label: Text(
                  _submitting ? '请稍候…' : '微信登录',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            TabBar(
              controller: _tabController,
              labelColor: AppDesignTokens.brandGreenDark,
              unselectedLabelColor: AppDesignTokens.textSecondary,
              indicatorColor: AppDesignTokens.brandGreen,
              tabs: const <Widget>[
                Tab(text: '手机号'),
                Tab(text: '邮箱'),
              ],
            ),
            const SizedBox(height: 16),
            AnimatedBuilder(
              animation: _tabController,
              builder: (BuildContext context, Widget? child) {
                return _tabController.index == 0
                    ? _buildPhoneForm()
                    : _buildEmailForm(showPassword);
              },
            ),
            const SizedBox(height: 12),
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

  Widget _buildPhoneForm() {
    return Form(
      key: _phoneFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '手机号',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
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
            decoration: _fieldDecoration('11 位手机号'),
          ),
          const SizedBox(height: 16),
          Text(
            '验证码',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  controller: _smsCodeController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  style: TextStyle(color: AppDesignTokens.textPrimary),
                  onFieldSubmitted: (_) => _submitPhone(),
                  validator: (String? value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入验证码';
                    }
                    return null;
                  },
                  decoration: _fieldDecoration(
                    _debugSmsCode == null ? '短信验证码' : '验证码（已填开发码）',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: (_sendingSms || _smsCooldown > 0) ? null : _sendSms,
                  child: Text(
                    _smsCooldown > 0
                        ? '${_smsCooldown}s'
                        : (_sendingSms ? '发送中' : '获取验证码'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _submitting ? null : _submitPhone,
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
    );
  }

  Widget _buildEmailForm(bool showPassword) {
    return Form(
      key: _emailFormKey,
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
          const SizedBox(height: 24),
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
          const SizedBox(height: 8),
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
