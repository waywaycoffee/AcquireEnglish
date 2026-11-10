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
}

/// AcquireEnglish API auth (JWT access_token).
class HttpAuthRepository implements AuthenticationRepository {
  HttpAuthRepository(this._api, this._session);

  final AcquireApiClient _api;
  final AuthSession _session;

  @override
  Future<LoginResponse> login(String email, String password) async {
    try {
      final AcquireTokenResult result = await _api.login(
        email: email,
        password: password,
      );
      await _session.signIn(
        accessToken: result.accessToken,
        email: result.user.email,
        displayName: result.user.displayName,
      );
      return LoginResponse(token: result.accessToken);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('邮箱或密码不正确');
      }
      if (e.response?.statusCode == 400) {
        throw Exception('账号不存在或请求无效');
      }
      throw Exception('登录失败，请检查网络后重试');
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
      throw Exception('注册失败，请检查网络后重试');
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
