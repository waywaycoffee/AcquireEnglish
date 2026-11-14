import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../sync/data/acquire_api_client.dart';
import '../../data/authentication_repository.dart';
import '../../data/hive/user_repository.dart';
import '../../domain/login_request.dart';
import '../../domain/login_response.dart';
import '../../domain/register_response.dart';
import '../auth_session.dart';
import 'auth_ui_model.dart';

part 'login_controller.g.dart';

@riverpod
class LoginController extends _$LoginController {
  @override
  FutureOr<AuthUiModel> build() async {
    final AuthSessionState session = ref.watch(authSessionProvider);
    final LoginCredentials? cached = await ref.read(
      userRepositoryProvider.future,
    );
    return AuthUiModel(
      user: LoginCredentials(
        email: session.email.isNotEmpty
            ? session.email
            : (cached?.email ?? ''),
        password: '',
      ),
      rememberMe: true,
    );
  }

  void updateRememberMe({required bool rememberMe}) {
    final AuthUiModel? current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData<AuthUiModel>(current.copyWith(rememberMe: rememberMe));
  }

  void updateShowPassword({required bool showPassword}) {
    final AuthUiModel? current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData<AuthUiModel>(
      current.copyWith(showPassword: showPassword),
    );
  }

  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    final String trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty || password.isEmpty) {
      throw Exception('请输入邮箱和密码');
    }
    final LoginResponse loginResponse = await ref
        .read(authenticationRepositoryProvider)
        .login(trimmedEmail, password);
    if (loginResponse.token.isEmpty) {
      throw Exception('登录失败');
    }
    final AuthUiModel? current = state.value;
    if (current?.rememberMe ?? true) {
      await ref
          .read(userRepositoryProvider.notifier)
          .cacheUser(
            LoginCredentials(email: trimmedEmail, password: ''),
          );
    }
    return loginResponse;
  }

  Future<RegisterResponse> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final String trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty || password.isEmpty) {
      throw Exception('请输入邮箱和密码');
    }
    if (password.length < 6) {
      throw Exception('密码至少 6 位');
    }
    final RegisterResponse registerResponse = await ref
        .read(authenticationRepositoryProvider)
        .register(trimmedEmail, password, displayName: displayName);
    if (registerResponse.token.isEmpty) {
      throw Exception('注册失败');
    }
    await ref
        .read(userRepositoryProvider.notifier)
        .cacheUser(LoginCredentials(email: trimmedEmail, password: ''));
    return registerResponse;
  }

  Future<AcquireSmsSendResult> sendSmsCode({required String phone}) {
    final String trimmed = phone.trim();
    if (trimmed.isEmpty) {
      throw Exception('请输入手机号');
    }
    return ref.read(authenticationRepositoryProvider).sendSmsCode(trimmed);
  }

  Future<LoginResponse> loginWithSms({
    required String phone,
    required String code,
  }) async {
    final String trimmedPhone = phone.trim();
    final String trimmedCode = code.trim();
    if (trimmedPhone.isEmpty || trimmedCode.isEmpty) {
      throw Exception('请输入手机号和验证码');
    }
    final LoginResponse response = await ref
        .read(authenticationRepositoryProvider)
        .loginWithSms(phone: trimmedPhone, code: trimmedCode);
    if (response.token.isEmpty) {
      throw Exception('登录失败');
    }
    await ref
        .read(userRepositoryProvider.notifier)
        .cacheUser(LoginCredentials(email: trimmedPhone, password: ''));
    return response;
  }

  Future<LoginResponse> loginWithWechat({
    required String code,
    String? nickname,
  }) async {
    final String trimmed = code.trim();
    if (trimmed.isEmpty) {
      throw Exception('缺少微信授权码');
    }
    final LoginResponse response = await ref
        .read(authenticationRepositoryProvider)
        .loginWithWechat(code: trimmed, nickname: nickname);
    if (response.token.isEmpty) {
      throw Exception('微信登录失败');
    }
    return response;
  }
}
