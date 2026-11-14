import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../sync/data/acquire_api_client.dart';
import '../domain/login_response.dart';
import '../domain/register_response.dart';
import '../presentation/auth_session.dart';

part 'authentication_repository.g.dart';

/// An abstract class that defines the authentication methods.
abstract class AuthenticationRepository {
  /// Authenticates a user with the given [email] and [password].
  Future<LoginResponse> login(String email, String password);

  /// Registers a new user with the given [email] and [password].
  Future<RegisterResponse> register(
    String email,
    String password, {
    String? displayName,
  });

  Future<AcquireSmsSendResult> sendSmsCode(String phone);

  /// Phone SMS login; auto-registers when the number is new.
  Future<LoginResponse> loginWithSms({
    required String phone,
    required String code,
  });

  /// WeChat OAuth `code` login; auto-registers when openid is new.
  Future<LoginResponse> loginWithWechat({
    required String code,
    String? nickname,
  });
}

/// AcquireEnglish API auth (JWT access_token).
class HttpAuthRepository implements AuthenticationRepository {
  HttpAuthRepository(this._api, this._session);

  final AcquireApiClient _api;
  final AuthSession _session;

  Future<LoginResponse> _signInFromToken(AcquireTokenResult result) async {
    await _session.signIn(
      accessToken: result.accessToken,
      email: result.user.email,
      displayName: result.user.displayName,
    );
    return LoginResponse(
      token: result.accessToken,
      isNewUser: result.isNewUser,
    );
  }

  String _dioMessage(DioException e, String fallback) {
    final Object? detail = e.response?.data;
    if (detail is Map && detail['detail'] != null) {
      return '${detail['detail']}';
    }
    if (detail is String && detail.trim().isNotEmpty) {
      return detail.trim();
    }
    return fallback;
  }

  @override
  Future<LoginResponse> login(String email, String password) async {
    try {
      final AcquireTokenResult result = await _api.login(
        email: email,
        password: password,
      );
      return _signInFromToken(result);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('邮箱或密码不正确');
      }
      if (e.response?.statusCode == 400) {
        throw Exception('账号不存在或请求无效');
      }
      throw Exception(_dioMessage(e, '登录失败，请检查网络后重试'));
    }
  }

  @override
  Future<RegisterResponse> register(
    String email,
    String password, {
    String? displayName,
  }) async {
    try {
      final AcquireTokenResult result = await _api.register(
        email: email,
        password: password,
        displayName: displayName,
      );
      await _session.signIn(
        accessToken: result.accessToken,
        email: result.user.email,
        displayName: result.user.displayName ?? displayName,
      );
      return RegisterResponse(id: result.user.id, token: result.accessToken);
    } on DioException catch (e) {
      if (e.response?.statusCode == 400) {
        throw Exception('该邮箱已注册');
      }
      throw Exception(_dioMessage(e, '注册失败，请检查网络后重试'));
    }
  }

  @override
  Future<AcquireSmsSendResult> sendSmsCode(String phone) async {
    try {
      return await _api.sendSmsCode(phone: phone);
    } on DioException catch (e) {
      throw Exception(_dioMessage(e, '验证码发送失败'));
    }
  }

  @override
  Future<LoginResponse> loginWithSms({
    required String phone,
    required String code,
  }) async {
    try {
      final AcquireTokenResult result = await _api.loginWithSms(
        phone: phone,
        code: code,
      );
      return _signInFromToken(result);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('验证码错误或已过期');
      }
      throw Exception(_dioMessage(e, '手机号登录失败'));
    }
  }

  @override
  Future<LoginResponse> loginWithWechat({
    required String code,
    String? nickname,
  }) async {
    try {
      final AcquireTokenResult result = await _api.loginWithWechat(
        code: code,
        nickname: nickname,
      );
      return _signInFromToken(result);
    } on DioException catch (e) {
      throw Exception(_dioMessage(e, '微信登录失败'));
    }
  }
}

@Riverpod(keepAlive: true)
AuthenticationRepository authenticationRepository(Ref ref) {
  return HttpAuthRepository(
    ref.read(acquireApiClientProvider),
    ref.read(authSessionProvider.notifier),
  );
}
